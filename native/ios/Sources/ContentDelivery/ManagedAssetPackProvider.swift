import ContentKit
import CryptoKit
import Foundation
import System

public enum AssetPackTransferStatus: Equatable, Sendable {
    case began
    case paused
    case downloading(completedUnitCount: Int64, totalUnitCount: Int64)
    case finished
    case failed(domain: String, code: Int)
}

/// Offline-only local state used by cache maintenance. `indeterminate` keeps
/// a cleanup receipt pending; only a definitively absent pack retires it
/// without first reading the exact local manifest.
public enum ManagedAssetPackLocalStatus: Equatable, Sendable {
    case absent
    case downloaded
    case indeterminate
}

/// The narrow boundary between Apple-hosted managed asset packs and the
/// package verifier. Tests can exercise interruption and corrupt inventories
/// without contacting Apple; the production implementation remains native.
public protocol ManagedAssetPackProviding: Sendable {
    func ensureLocalAvailability(
        of packageID: PackageID,
        requireLatestVersion: Bool
    ) async throws

    /// Returns a newly owned, read-only descriptor positioned at the start of
    /// the requested file. The caller is responsible for closing it.
    func descriptor(
        at assetPackRelativePath: String,
        in packageID: PackageID
    ) throws -> FileDescriptor

    /// Reads only local system state. Implementations must not check the
    /// network for updates or trigger a download/removal.
    func localStatus(of packageID: PackageID) async throws -> ManagedAssetPackLocalStatus

    /// Removes the currently local Apple-managed copy for this identifier.
    /// Callers bind this operation to exact manifest bytes before invoking it.
    func removeLocalAssetPack(_ packageID: PackageID) async throws

    func statusUpdates(for packageID: PackageID) -> AsyncStream<AssetPackTransferStatus>
}

/// Supplies the capacity that the system currently makes available for an
/// important app write on the volume containing the private installed copy.
/// The managed Apple pack is already local when this value is read, so the
/// check measures the space still available for isolated staging and the
/// atomic activation index.
public protocol ManagedPackageStorageCapacityProviding: Sendable {
    func availableCapacityForImportantUsage(at volumeURL: URL) throws -> Int64?
}

public struct VolumeManagedPackageStorageCapacityProvider:
    ManagedPackageStorageCapacityProviding
{
    public init() {}

    public func availableCapacityForImportantUsage(at volumeURL: URL) throws -> Int64? {
        try volumeURL.resourceValues(
            forKeys: [.volumeAvailableCapacityForImportantUsageKey]
        ).volumeAvailableCapacityForImportantUsage
    }
}

public enum ManagedAssetPackLayout {
    public static let rootDirectoryName = "packages"

    public static func manifestPath(for packageID: PackageID) throws -> String {
        try path(for: packageID, packageRelativePath: ContentPackageVerifier.manifestFileName)
    }

    public static func filePath(
        for packageID: PackageID,
        packageRelativePath: String
    ) throws -> String {
        try path(for: packageID, packageRelativePath: packageRelativePath)
    }

    private static func path(
        for packageID: PackageID,
        packageRelativePath: String
    ) throws -> String {
        guard isStableComponent(packageID.rawValue) else {
            throw ManagedPackageMaterializationError.invalidPackageIdentifier(packageID.rawValue)
        }
        try validateSafeRelativePath(packageRelativePath)
        return "\(rootDirectoryName)/\(packageID.rawValue)/\(packageRelativePath)"
    }

    fileprivate static func validateSafeRelativePath(_ path: String) throws {
        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        let containsControl = path.unicodeScalars.contains { scalar in
            scalar.value <= 0x1F || scalar.value == 0x7F
        }
        guard !path.isEmpty,
              !path.hasPrefix("/"),
              !path.contains("\\"),
              !path.contains("://"),
              !containsControl,
              components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
            throw ManagedPackageMaterializationError.unsafePackagePath(path)
        }
    }

    private static func isStableComponent(_ value: String) -> Bool {
        guard let first = value.utf8.first, (97 ... 122).contains(first),
              let last = value.utf8.last,
              (97 ... 122).contains(last) || (48 ... 57).contains(last) else {
            return false
        }
        var previousWasHyphen = false
        for byte in value.utf8 {
            if byte == 45 {
                if previousWasHyphen { return false }
                previousWasHyphen = true
            } else if (97 ... 122).contains(byte) || (48 ... 57).contains(byte) {
                previousWasHyphen = false
            } else {
                return false
            }
        }
        return true
    }
}

public enum ManagedPackageMaterializationError: Error, Equatable, Sendable {
    case invalidPackageIdentifier(String)
    case unsafePackagePath(String)
    case manifestTooLarge(actual: Int, maximum: Int)
    case destinationWriteStalled(String)
    case insufficientStorage(available: Int64, required: Int64)
}

extension ManagedPackageMaterializationError: CustomNSError {
    public static var errorDomain: String {
        "com.thelongwest.eurocentric.managed-package-materialization"
    }

    public static let insufficientStorageErrorCode = 5

    public var errorCode: Int {
        switch self {
        case .invalidPackageIdentifier: 1
        case .unsafePackagePath: 2
        case .manifestTooLarge: 3
        case .destinationWriteStalled: 4
        case .insufficientStorage: Self.insufficientStorageErrorCode
        }
    }
}

/// Copies a complete Apple-hosted pack into an isolated staging generation,
/// then delegates trust, inventory, schema and payload checks to the same
/// verifier used by local packages. Downloaded bytes never become active
/// before the signed manifest and every inventoried file pass verification.
public struct ManagedPackageMaterializer: Sendable {
    public static let maximumManifestBytes = 4 * 1_024 * 1_024
    /// Leaves enough room for the final index replacement and ordinary app
    /// persistence even when the package reaches its signed maximum.
    public static let stagingSafetyReserveBytes: Int64 = 64 * 1_024 * 1_024
    private static let copyBufferBytes = 64 * 1_024

    private let provider: any ManagedAssetPackProviding
    private let activator: PackageActivator
    private let storageCapacityProvider: any ManagedPackageStorageCapacityProviding
    private let cleanupCoordinator: ManagedAssetPackCleanupCoordinator

    public let cleanupAuthorityDirectoryURL: URL

    public init(
        provider: any ManagedAssetPackProviding,
        activator: PackageActivator,
        storageCapacityProvider: any ManagedPackageStorageCapacityProviding =
            VolumeManagedPackageStorageCapacityProvider()
    ) {
        self.provider = provider
        self.activator = activator
        self.storageCapacityProvider = storageCapacityProvider
        cleanupAuthorityDirectoryURL = activator.rootURL.appending(
            path: "managed-asset-cleanup",
            directoryHint: .isDirectory
        )
        cleanupCoordinator = ManagedAssetPackCleanupCoordinator(
            provider: provider,
            directoryURL: cleanupAuthorityDirectoryURL
        )
    }

    public func downloadAndActivate(
        expectedPackage: ContentPackageSpec,
        trustedPublicKeys: [String: Data],
        supportedSchema: SchemaVersion,
        runtimeVersion: SchemaVersion,
        requireLatestVersion: Bool = true
    ) async throws -> ActivatedPackage {
        // A failed cleanup never blocks a fresh download. If the pending
        // receipt still names the local bytes, this releases the old Apple
        // cache before ensureLocalAvailability downloads them again.
        try? await cleanupCoordinator.retryPendingCleanup()
        try await provider.ensureLocalAvailability(
            of: expectedPackage.id,
            requireLatestVersion: requireLatestVersion
        )
        try requireStagingCapacity(for: expectedPackage)

        let manifestPath = try ManagedAssetPackLayout.manifestPath(for: expectedPackage.id)
        let manifestData = try readBoundedManifest(
            at: manifestPath,
            in: expectedPackage.id
        )
        let rawManifestSHA256 = SHA256.hash(data: manifestData)
            .map { String(format: "%02x", $0) }
            .joined()

        // Canonical JSON, schema/runtime compatibility, trusted package spec,
        // signature and the declared byte budget all pass before staging.
        // PackageActivator repeats trust and file checks over the staged tree.
        let manifest = try ContentPackageVerifier.verifyManifest(
            manifestData,
            expectedPackage: expectedPackage,
            trustedPublicKeys: trustedPublicKeys,
            supportedSchema: supportedSchema,
            runtimeVersion: runtimeVersion
        )
        guard let manifestByteCount = Int64(exactly: manifestData.count) else {
            throw PackageVerificationError.installedByteCountOverflow
        }
        var installedBytes = manifestByteCount

        let stagingURL = try await activator.makeStagingDirectory()
        var activationSucceeded = false
        defer {
            if !activationSucceeded {
                try? FileManager.default.removeItem(at: stagingURL)
            }
        }

        try manifestData.write(
            to: stagingURL.appending(path: ContentPackageVerifier.manifestFileName),
            options: [.atomic]
        )
        for record in manifest.files {
            try ManagedAssetPackLayout.validateSafeRelativePath(record.path)
            let sourcePath = try ManagedAssetPackLayout.filePath(
                for: expectedPackage.id,
                packageRelativePath: record.path
            )
            let destinationURL = stagingURL.appending(
                path: record.path,
                directoryHint: .notDirectory
            ).standardizedFileURL
            guard destinationURL.path.hasPrefix(stagingURL.standardizedFileURL.path + "/") else {
                throw ManagedPackageMaterializationError.unsafePackagePath(record.path)
            }
            try FileManager.default.createDirectory(
                at: destinationURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try copyAndVerify(
                at: sourcePath,
                in: expectedPackage.id,
                to: destinationURL,
                record: record,
                installedBytes: &installedBytes,
                maximumInstalledBytes: expectedPackage.maximumInstalledBytes
            )
        }

        let activated = try await activator.activate(
            stagedPackageURL: stagingURL,
            expectedPackage: expectedPackage,
            trustedPublicKeys: trustedPublicKeys,
            supportedSchema: supportedSchema,
            runtimeVersion: runtimeVersion
        )
        activationSucceeded = true
        // The private generation and its atomic index pointer are already
        // committed. Cleanup journaling and Apple-cache removal are strictly
        // best-effort maintenance and cannot change the activation result.
        try? await cleanupCoordinator.recordAndAttemptCleanup(
            packageID: expectedPackage.id,
            rawManifestSHA256: rawManifestSHA256,
            contentVersion: expectedPackage.version
        )
        return activated
    }

    /// Bootstrap and download orchestration can explicitly resume cleanup.
    /// The hook never checks for updates or touches private generations.
    public func retryPendingCleanup() async throws {
        try await cleanupCoordinator.retryPendingCleanup()
    }

    public func statusUpdates(for packageID: PackageID) -> AsyncStream<AssetPackTransferStatus> {
        provider.statusUpdates(for: packageID)
    }

    private func requireStagingCapacity(for package: ContentPackageSpec) throws {
        let required = package.maximumInstalledBytes.addingReportingOverflow(
            Self.stagingSafetyReserveBytes
        )
        guard !required.overflow else {
            throw PackageVerificationError.installedByteCountOverflow
        }
        guard let available = try storageCapacityProvider
            .availableCapacityForImportantUsage(at: activator.rootURL) else {
            // Capacity is advisory. If the volume cannot report it, bounded
            // streaming and isolated staging still preserve the active copy
            // when a later write reports ENOSPC.
            return
        }
        guard available >= required.partialValue else {
            throw ManagedPackageMaterializationError.insufficientStorage(
                available: available,
                required: required.partialValue
            )
        }
    }

    private func readBoundedManifest(
        at assetPackRelativePath: String,
        in packageID: PackageID
    ) throws -> Data {
        let descriptor = try provider.descriptor(
            at: assetPackRelativePath,
            in: packageID
        )
        defer { try? descriptor.close() }

        var data = Data()
        data.reserveCapacity(Self.copyBufferBytes)
        var buffer = [UInt8](repeating: 0, count: Self.copyBufferBytes)

        while true {
            let bytesUntilLimit = Self.maximumManifestBytes - data.count
            let readLimit = min(buffer.count, bytesUntilLimit + 1)
            let readCount = try buffer.withUnsafeMutableBytes { rawBuffer in
                try descriptor.read(
                    into: UnsafeMutableRawBufferPointer(rebasing: rawBuffer[..<readLimit])
                )
            }
            guard readCount > 0 else { return data }
            data.append(contentsOf: buffer.prefix(readCount))
            guard data.count <= Self.maximumManifestBytes else {
                throw ManagedPackageMaterializationError.manifestTooLarge(
                    actual: data.count,
                    maximum: Self.maximumManifestBytes
                )
            }
        }
    }

    private func copyAndVerify(
        at assetPackRelativePath: String,
        in packageID: PackageID,
        to destinationURL: URL,
        record: PackageFileRecord,
        installedBytes: inout Int64,
        maximumInstalledBytes: Int64
    ) throws {
        let source = try provider.descriptor(
            at: assetPackRelativePath,
            in: packageID
        )
        defer { try? source.close() }

        let destination = try FileDescriptor.open(
            FilePath(destinationURL.path),
            .writeOnly,
            options: [.create, .exclusiveCreate],
            permissions: .ownerReadWrite
        )
        defer { try? destination.close() }

        var fileBytes: Int64 = 0
        var hasher = SHA256()
        var buffer = [UInt8](repeating: 0, count: Self.copyBufferBytes)

        while true {
            let readCount = try buffer.withUnsafeMutableBytes { rawBuffer in
                try source.read(into: rawBuffer)
            }
            guard readCount > 0 else { break }
            guard let readByteCount = Int64(exactly: readCount) else {
                throw PackageVerificationError.installedByteCountOverflow
            }

            let nextFileBytes = fileBytes.addingReportingOverflow(readByteCount)
            let nextInstalledBytes = installedBytes.addingReportingOverflow(readByteCount)
            guard !nextFileBytes.overflow, !nextInstalledBytes.overflow else {
                throw PackageVerificationError.installedByteCountOverflow
            }
            guard nextInstalledBytes.partialValue <= maximumInstalledBytes else {
                throw PackageVerificationError.installedByteBudgetExceeded(
                    actual: nextInstalledBytes.partialValue,
                    maximum: maximumInstalledBytes
                )
            }
            guard nextFileBytes.partialValue <= record.bytes else {
                throw PackageVerificationError.fileSizeMismatch(record.path)
            }

            try buffer.withUnsafeBytes { rawBuffer in
                let chunk = UnsafeRawBufferPointer(rebasing: rawBuffer[..<readCount])
                hasher.update(bufferPointer: chunk)
                var written = 0
                while written < chunk.count {
                    let writeCount = try destination.write(
                        UnsafeRawBufferPointer(rebasing: chunk[written...])
                    )
                    guard writeCount > 0 else {
                        throw ManagedPackageMaterializationError.destinationWriteStalled(record.path)
                    }
                    written += writeCount
                }
            }
            fileBytes = nextFileBytes.partialValue
            installedBytes = nextInstalledBytes.partialValue
        }

        guard fileBytes == record.bytes else {
            throw PackageVerificationError.fileSizeMismatch(record.path)
        }
        let digest = hasher.finalize().map { String(format: "%02x", $0) }.joined()
        guard digest == record.sha256 else {
            throw PackageVerificationError.fileDigestMismatch(record.path)
        }
    }
}

#if os(iOS) && canImport(BackgroundAssets)
import BackgroundAssets

@available(iOS 26.4, *)
public struct AppleHostedAssetPackProvider: ManagedAssetPackProviding {
    public init() {}

    public func ensureLocalAvailability(
        of packageID: PackageID,
        requireLatestVersion: Bool
    ) async throws {
        let pack = try await AssetPackManager.shared.assetPack(withID: packageID.rawValue)
        try await AssetPackManager.shared.ensureLocalAvailability(
            of: pack,
            requireLatestVersion: requireLatestVersion
        )
    }

    public func descriptor(
        at assetPackRelativePath: String,
        in packageID: PackageID
    ) throws -> FileDescriptor {
        try AssetPackManager.shared.descriptor(
            for: FilePath(assetPackRelativePath),
            searchingInAssetPackWithID: packageID.rawValue,
        )
    }

    public func localStatus(
        of packageID: PackageID
    ) async throws -> ManagedAssetPackLocalStatus {
        let status = await AssetPackManager.shared.localStatus(
            ofAssetPackWithID: packageID.rawValue
        )
        if status.contains(.downloading) {
            return .indeterminate
        }
        if status.contains(.downloaded) {
            return .downloaded
        }
        return status.isEmpty ? .absent : .indeterminate
    }

    public func removeLocalAssetPack(_ packageID: PackageID) async throws {
        try await AssetPackManager.shared.remove(assetPackWithID: packageID.rawValue)
    }

    public func statusUpdates(for packageID: PackageID) -> AsyncStream<AssetPackTransferStatus> {
        let rawPackageID = packageID.rawValue
        return AsyncStream { continuation in
            let task = Task {
                for await update in AssetPackManager.shared.statusUpdates(
                    forAssetPackWithID: rawPackageID
                ) {
                    switch update {
                    case let .began(pack) where pack.id == rawPackageID:
                        continuation.yield(.began)
                    case let .paused(pack) where pack.id == rawPackageID:
                        continuation.yield(.paused)
                    case let .downloading(pack, progress) where pack.id == rawPackageID:
                        continuation.yield(.downloading(
                            completedUnitCount: progress.completedUnitCount,
                            totalUnitCount: progress.totalUnitCount
                        ))
                    case let .finished(pack) where pack.id == rawPackageID:
                        continuation.yield(.finished)
                    case let .failed(pack, error) where pack.id == rawPackageID:
                        let nsError = error as NSError
                        continuation.yield(.failed(domain: nsError.domain, code: nsError.code))
                    default:
                        continue
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
#endif
