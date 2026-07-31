import ContentKit
import CryptoKit
import Darwin
import Foundation

public struct ManagedAssetPackCleanupIntent: Codable, Equatable, Sendable {
    public let packageID: PackageID
    public let rawManifestSHA256: String
    public let contentVersion: SchemaVersion

    public init(
        packageID: PackageID,
        rawManifestSHA256: String,
        contentVersion: SchemaVersion
    ) {
        self.packageID = packageID
        self.rawManifestSHA256 = rawManifestSHA256
        self.contentVersion = contentVersion
    }
}

public enum ManagedAssetPackCleanupError: Error, Equatable, Sendable {
    case requiresNewerApp(Int)
    case corruptAuthority
    case unsafeAuthorityStorage(String)
    case authorityTooLarge(actual: Int, maximum: Int)
    case storageFailure(operation: String, code: Int32)
}

/// Serializes cleanup decisions for one materializer. The Apple-managed copy
/// is never removed until an exact raw-manifest identity has crossed the
/// durable two-slot authority boundary.
actor ManagedAssetPackCleanupCoordinator {
    nonisolated let directoryURL: URL

    private let provider: any ManagedAssetPackProviding

    init(provider: any ManagedAssetPackProviding, directoryURL: URL) {
        self.provider = provider
        self.directoryURL = directoryURL.standardizedFileURL
    }

    func recordAndAttemptCleanup(
        packageID: PackageID,
        rawManifestSHA256: String,
        contentVersion: SchemaVersion
    ) async throws {
        let intent = ManagedAssetPackCleanupIntent(
            packageID: packageID,
            rawManifestSHA256: rawManifestSHA256,
            contentVersion: contentVersion
        )
        let store = try ManagedAssetPackCleanupAuthorityStore(directoryURL: directoryURL)
        var authority = try store.load()
        try authority.record(intent)

        // This synchronized atomic replacement is the removal gate. If it
        // fails, the Apple cache remains untouched.
        try store.save(authority)
        try await process(intent, store: store)
    }

    func retryPendingCleanup() async throws {
        let store = try ManagedAssetPackCleanupAuthorityStore(directoryURL: directoryURL)
        let intents = try store.load().intents
        var firstError: (any Error)?
        for intent in intents {
            do {
                try await process(intent, store: store)
            } catch {
                if firstError == nil { firstError = error }
            }
        }
        if let firstError { throw firstError }
    }

    private func process(
        _ intent: ManagedAssetPackCleanupIntent,
        store: ManagedAssetPackCleanupAuthorityStore
    ) async throws {
        guard try store.load().intent(
            for: intent.packageID,
            rawManifestSHA256: intent.rawManifestSHA256
        ) == intent else {
            return
        }

        switch try await provider.localStatus(of: intent.packageID) {
        case .absent:
            try retire(intent, store: store)
        case .indeterminate:
            return
        case .downloaded:
            let localDigest = try currentRawManifestSHA256(for: intent.packageID)
            guard localDigest == intent.rawManifestSHA256 else {
                // A newer or otherwise different local pack owns this ID now.
                // Retire only the stale receipt; never remove those bytes.
                try retire(intent, store: store)
                return
            }

            // Reconfirm that another cleanup decision did not supersede this
            // intent while local state was being inspected.
            guard try store.load().intent(
                for: intent.packageID,
                rawManifestSHA256: intent.rawManifestSHA256
            ) == intent else {
                return
            }
            try await provider.removeLocalAssetPack(intent.packageID)
            // A failure here leaves a harmless pending receipt. On retry, a
            // definitively absent pack retires it without a second removal.
            try retire(intent, store: store)
        }
    }

    private func retire(
        _ intent: ManagedAssetPackCleanupIntent,
        store: ManagedAssetPackCleanupAuthorityStore
    ) throws {
        var authority = try store.load()
        guard authority.intent(
            for: intent.packageID,
            rawManifestSHA256: intent.rawManifestSHA256
        ) == intent else {
            return
        }
        authority.retire(intent)
        try store.save(authority)
    }

    private func currentRawManifestSHA256(for packageID: PackageID) throws -> String {
        let descriptor = try provider.descriptor(
            at: ManagedAssetPackLayout.manifestPath(for: packageID),
            in: packageID
        )
        defer { try? descriptor.close() }

        var hasher = SHA256()
        var totalBytes = 0
        var buffer = [UInt8](repeating: 0, count: 64 * 1_024)
        while true {
            let remaining = ManagedPackageMaterializer.maximumManifestBytes - totalBytes
            let readLimit = min(buffer.count, remaining + 1)
            let readCount = try buffer.withUnsafeMutableBytes { rawBuffer in
                try descriptor.read(
                    into: UnsafeMutableRawBufferPointer(rebasing: rawBuffer[..<readLimit])
                )
            }
            guard readCount > 0 else {
                return hasher.finalize().map { String(format: "%02x", $0) }.joined()
            }
            totalBytes += readCount
            guard totalBytes <= ManagedPackageMaterializer.maximumManifestBytes else {
                throw ManagedPackageMaterializationError.manifestTooLarge(
                    actual: totalBytes,
                    maximum: ManagedPackageMaterializer.maximumManifestBytes
                )
            }
            buffer.withUnsafeBytes { rawBuffer in
                hasher.update(
                    bufferPointer: UnsafeRawBufferPointer(
                        rebasing: rawBuffer[..<readCount]
                    )
                )
            }
        }
    }
}

private struct ManagedAssetPackCleanupAuthority: Codable, Equatable, Sendable {
    static let currentFormatVersion = 1

    let formatVersion: Int
    var intents: [ManagedAssetPackCleanupIntent]

    init(
        formatVersion: Int = currentFormatVersion,
        intents: [ManagedAssetPackCleanupIntent] = []
    ) {
        self.formatVersion = formatVersion
        self.intents = intents
    }

    static let empty = ManagedAssetPackCleanupAuthority()

    func intent(
        for packageID: PackageID,
        rawManifestSHA256: String
    ) -> ManagedAssetPackCleanupIntent? {
        intents.first {
            $0.packageID == packageID && $0.rawManifestSHA256 == rawManifestSHA256
        }
    }

    mutating func record(_ intent: ManagedAssetPackCleanupIntent) throws {
        intents.removeAll { $0.packageID == intent.packageID }
        intents.append(intent)
        intents.sort { $0.packageID < $1.packageID }
        try validate()
    }

    mutating func retire(_ intent: ManagedAssetPackCleanupIntent) {
        intents.removeAll { $0 == intent }
    }

    func validate() throws {
        guard formatVersion == Self.currentFormatVersion,
              Set(intents.map(\.packageID)).count == intents.count,
              intents == intents.sorted(by: { $0.packageID < $1.packageID }),
              intents.allSatisfy({ intent in
                  (try? ManagedAssetPackLayout.manifestPath(for: intent.packageID)) != nil
                      && Self.isLowercaseSHA256(intent.rawManifestSHA256)
                      && intent.contentVersion.isValid
              }) else {
            throw ManagedAssetPackCleanupError.corruptAuthority
        }
    }

    private static func isLowercaseSHA256(_ value: String) -> Bool {
        value.utf8.count == 64 && value.utf8.allSatisfy {
            ($0 >= 48 && $0 <= 57) || ($0 >= 97 && $0 <= 102)
        }
    }
}

/// Digest-checked two-slot authority. Reads and writes use O_NOFOLLOW, and
/// replacements synchronize both the file and parent directory before a
/// removal operation can begin.
private struct ManagedAssetPackCleanupAuthorityStore {
    private static let envelopeFormatVersion = 1
    private static let maximumAuthorityBytes = 1 * 1_024 * 1_024

    let directoryURL: URL

    private var slotAURL: URL {
        directoryURL.appending(path: "asset-pack-cleanup-a.json", directoryHint: .notDirectory)
    }

    private var slotBURL: URL {
        directoryURL.appending(path: "asset-pack-cleanup-b.json", directoryHint: .notDirectory)
    }

    init(directoryURL: URL) throws {
        self.directoryURL = directoryURL.standardizedFileURL
        try Self.requireOrCreateUnlinkedDirectory(self.directoryURL)
    }

    func load() throws -> ManagedAssetPackCleanupAuthority {
        try loadEnvelope()?.authority ?? .empty
    }

    func save(_ authority: ManagedAssetPackCleanupAuthority) throws {
        try authority.validate()
        let prior = try loadEnvelope()
        let nextGeneration = (prior?.generation ?? 0).addingReportingOverflow(1)
        guard !nextGeneration.overflow else {
            throw ManagedAssetPackCleanupError.corruptAuthority
        }
        let generation = nextGeneration.partialValue
        let material = ManagedAssetPackCleanupDigestMaterial(
            envelopeFormatVersion: Self.envelopeFormatVersion,
            generation: generation,
            authority: authority
        )
        let envelope = ManagedAssetPackCleanupEnvelope(
            envelopeFormatVersion: Self.envelopeFormatVersion,
            generation: generation,
            authority: authority,
            digest: try Self.digest(material)
        )
        let target = generation.isMultiple(of: 2) ? slotBURL : slotAURL
        try Self.replaceAtomicallyAndSynchronize(Self.encode(envelope), at: target)
    }

    private func loadEnvelope() throws -> ManagedAssetPackCleanupEnvelope? {
        try Self.requireUnlinkedDirectory(directoryURL)
        let slotData = try [slotAURL, slotBURL].compactMap(Self.readRegularFileIfPresent)
        guard !slotData.isEmpty else { return nil }

        let valid = slotData.compactMap(Self.validCurrentEnvelope)
        let newest = valid.max { $0.generation < $1.generation }
        let newestFuture = slotData.compactMap {
            TwoSlotFutureAuthority.inspect(
                data: $0,
                payloadKey: "authority",
                currentEnvelopeFormatVersion: Self.envelopeFormatVersion,
                currentPayloadFormatVersion: ManagedAssetPackCleanupAuthority.currentFormatVersion
            )
        }.max { $0.generation < $1.generation }
        if let newestFuture,
           newestFuture.generation >= (newest?.generation ?? 0) {
            throw ManagedAssetPackCleanupError.requiresNewerApp(
                newestFuture.requiredFormatVersion
            )
        }

        // Unlike a read-only cache, cleanup can delete bytes. Any unexplained
        // slot is therefore preserved as possible newer authority rather than
        // being overwritten through fallback.
        guard valid.count == slotData.count, let newest else {
            throw ManagedAssetPackCleanupError.corruptAuthority
        }
        return newest
    }

    private static func validCurrentEnvelope(
        from data: Data
    ) -> ManagedAssetPackCleanupEnvelope? {
        guard let envelope = try? decoder.decode(
            ManagedAssetPackCleanupEnvelope.self,
            from: data
        ),
        envelope.envelopeFormatVersion == envelopeFormatVersion,
        envelope.generation > 0,
        (try? envelope.authority.validate()) != nil else {
            return nil
        }
        let material = ManagedAssetPackCleanupDigestMaterial(
            envelopeFormatVersion: envelope.envelopeFormatVersion,
            generation: envelope.generation,
            authority: envelope.authority
        )
        guard (try? digest(material)) == envelope.digest else { return nil }
        return envelope
    }

    private static func digest<T: Encodable>(_ value: T) throws -> String {
        SHA256.hash(data: try encode(value))
            .map { String(format: "%02x", $0) }
            .joined()
    }

    private static func encode<T: Encodable>(_ value: T) throws -> Data {
        try encoder.encode(value)
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }()

    private static let decoder = JSONDecoder()

    private static func requireOrCreateUnlinkedDirectory(_ url: URL) throws {
        let parent = url.deletingLastPathComponent()
        try requireUnlinkedDirectory(parent)
        switch try nodeKind(at: url) {
        case .absent:
            do {
                try FileManager.default.createDirectory(
                    at: url,
                    withIntermediateDirectories: false
                )
                try synchronizeDirectory(parent)
            } catch let error as ManagedAssetPackCleanupError {
                throw error
            } catch {
                let nsError = error as NSError
                throw ManagedAssetPackCleanupError.storageFailure(
                    operation: "create cleanup authority directory",
                    code: Int32(nsError.code)
                )
            }
            try requireUnlinkedDirectory(url)
        case .directory:
            break
        case .regular, .symbolicLink, .other:
            throw ManagedAssetPackCleanupError.unsafeAuthorityStorage(url.path)
        }
    }

    private static func requireUnlinkedDirectory(_ url: URL) throws {
        guard try nodeKind(at: url) == .directory else {
            throw ManagedAssetPackCleanupError.unsafeAuthorityStorage(url.path)
        }
    }

    private static func readRegularFileIfPresent(at url: URL) throws -> Data? {
        switch try nodeKind(at: url) {
        case .absent:
            return nil
        case .regular:
            break
        case .directory, .symbolicLink, .other:
            throw ManagedAssetPackCleanupError.unsafeAuthorityStorage(url.path)
        }

        let descriptor = url.path.withCString {
            Darwin.open($0, O_RDONLY | O_CLOEXEC | O_NOFOLLOW)
        }
        guard descriptor >= 0 else {
            throw storageFailure("open cleanup authority", errno)
        }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? handle.close() }

        var data = Data()
        while true {
            let remaining = maximumAuthorityBytes - data.count
            let chunk = try handle.read(upToCount: min(64 * 1_024, remaining + 1)) ?? Data()
            guard !chunk.isEmpty else { return data }
            data.append(chunk)
            guard data.count <= maximumAuthorityBytes else {
                throw ManagedAssetPackCleanupError.authorityTooLarge(
                    actual: data.count,
                    maximum: maximumAuthorityBytes
                )
            }
        }
    }

    private static func replaceAtomicallyAndSynchronize(
        _ data: Data,
        at destinationURL: URL
    ) throws {
        let directory = destinationURL.deletingLastPathComponent()
        try requireUnlinkedDirectory(directory)
        switch try nodeKind(at: destinationURL) {
        case .absent, .regular:
            break
        case .directory, .symbolicLink, .other:
            throw ManagedAssetPackCleanupError.unsafeAuthorityStorage(destinationURL.path)
        }

        let temporaryURL = directory.appending(
            path: ".\(destinationURL.lastPathComponent).\(UUID().uuidString.lowercased()).replacement",
            directoryHint: .notDirectory
        )
        let descriptor = temporaryURL.path.withCString {
            Darwin.open(
                $0,
                O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC | O_NOFOLLOW,
                S_IRUSR | S_IWUSR
            )
        }
        guard descriptor >= 0 else {
            throw storageFailure("create cleanup authority replacement", errno)
        }
        var handle: FileHandle? = FileHandle(
            fileDescriptor: descriptor,
            closeOnDealloc: true
        )
        defer {
            try? handle?.close()
            _ = temporaryURL.path.withCString { Darwin.unlink($0) }
        }
        do {
            try handle?.write(contentsOf: data)
            try handle?.synchronize()
            try handle?.close()
            handle = nil
        } catch {
            throw error
        }

        // Refuse to replace a symlink or foreign node introduced since the
        // first check. rename(2) would replace a symlink rather than follow it,
        // but cleanup authority does not touch foreign filesystem objects.
        switch try nodeKind(at: destinationURL) {
        case .absent, .regular:
            break
        case .directory, .symbolicLink, .other:
            throw ManagedAssetPackCleanupError.unsafeAuthorityStorage(destinationURL.path)
        }
        let renameResult = temporaryURL.path.withCString { sourcePath in
            destinationURL.path.withCString { destinationPath in
                Darwin.rename(sourcePath, destinationPath)
            }
        }
        guard renameResult == 0 else {
            throw storageFailure("replace cleanup authority", errno)
        }
        try synchronizeDirectory(directory)
    }

    private static func synchronizeDirectory(_ url: URL) throws {
        let descriptor = url.path.withCString {
            Darwin.open($0, O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW)
        }
        guard descriptor >= 0 else {
            throw storageFailure("open cleanup authority directory", errno)
        }
        defer { _ = Darwin.close(descriptor) }
        guard Darwin.fsync(descriptor) == 0 else {
            throw storageFailure("synchronize cleanup authority directory", errno)
        }
    }

    private static func storageFailure(
        _ operation: String,
        _ code: Int32
    ) -> ManagedAssetPackCleanupError {
        .storageFailure(operation: operation, code: code)
    }

    private enum NodeKind: Equatable {
        case absent
        case regular
        case directory
        case symbolicLink
        case other
    }

    private static func nodeKind(at url: URL) throws -> NodeKind {
        var information = stat()
        let result = url.path.withCString { Darwin.lstat($0, &information) }
        guard result == 0 else {
            if errno == ENOENT { return .absent }
            throw storageFailure("inspect cleanup authority storage", errno)
        }
        switch information.st_mode & S_IFMT {
        case S_IFREG: return .regular
        case S_IFDIR: return .directory
        case S_IFLNK: return .symbolicLink
        default: return .other
        }
    }
}

private struct ManagedAssetPackCleanupEnvelope: Codable, Sendable {
    let envelopeFormatVersion: Int
    let generation: UInt64
    let authority: ManagedAssetPackCleanupAuthority
    let digest: String
}

private struct ManagedAssetPackCleanupDigestMaterial: Codable, Sendable {
    let envelopeFormatVersion: Int
    let generation: UInt64
    let authority: ManagedAssetPackCleanupAuthority
}
