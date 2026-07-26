import ContentKit
import CryptoKit
import Foundation

/// Authenticated release contracts retained independently from the live
/// CloudKit query. Once delivery is authorised, an installed deep dive must
/// remain verifiable and playable offline even if its catalog record is later
/// withdrawn from discovery.
public struct ReleaseInstallationContractSnapshot: Codable, Equatable, Sendable {
    public static let currentFormatVersion = 1

    public let formatVersion: Int
    public let entries: [ReleaseCatalogEntry]

    public init(
        formatVersion: Int = currentFormatVersion,
        entries: [ReleaseCatalogEntry] = []
    ) {
        self.formatVersion = formatVersion
        self.entries = entries
    }

    public static let empty = ReleaseInstallationContractSnapshot()

    public func validate() throws {
        guard formatVersion == Self.currentFormatVersion else {
            throw ReleaseInstallationContractStoreError.unsupportedFormat(
                formatVersion
            )
        }
        let canonical = try entries.validatedCanonicalReleaseCatalog()
        guard canonical == entries else {
            throw ReleaseInstallationContractStoreError.noncanonicalSnapshot
        }
    }
}

public enum ReleaseInstallationContractStoreError: Error, Equatable, Sendable {
    case invalidIntegrityKey
    case unsupportedFormat(Int)
    case noncanonicalSnapshot
    case corruptStorage
    case unavailable
}

/// Crash-safe two-slot ledger for exact, immutable package-verification
/// contracts. Pinning and retirement are each written into both fallback
/// generations. Delivery may begin only after `pin` succeeds.
public struct ReleaseInstallationContractStore: Sendable {
    private static let envelopeFormatVersion = 1

    public let directoryURL: URL
    private let keyProvider: any ReleaseCacheIntegrityKeyProviding
    private let writer: any ReleaseCacheAtomicWriting

    var slotAURL: URL {
        directoryURL.appendingPathComponent(
            "release-install-contracts-a.json",
            isDirectory: false
        )
    }

    var slotBURL: URL {
        directoryURL.appendingPathComponent(
            "release-install-contracts-b.json",
            isDirectory: false
        )
    }

    public init(
        directoryURL: URL,
        keyProvider: any ReleaseCacheIntegrityKeyProviding,
        writer: any ReleaseCacheAtomicWriting = FoundationReleaseCacheWriter()
    ) throws {
        self.directoryURL = directoryURL
        self.keyProvider = keyProvider
        self.writer = writer
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
    }

    public func load() throws -> ReleaseInstallationContractSnapshot {
        try loadEnvelope()?.snapshot ?? .empty
    }

    public func entry(for releaseID: ReleaseID) throws -> ReleaseCatalogEntry? {
        try load().entries.first { $0.id == releaseID }
    }

    /// Pins only a complete catalog entry which has already crossed the
    /// authenticated discovery boundary. An immutable release ID or package
    /// binding can never be repointed to different bytes.
    @discardableResult
    public func pin(_ entry: ReleaseCatalogEntry) throws -> UInt64 {
        try entry.validate()
        let previous = try loadEnvelope()
        let priorEntries = previous?.snapshot.entries ?? []

        if let prior = priorEntries.first(where: { $0.id == entry.id }),
           prior != entry {
            throw ReleaseCatalogError.immutableReleaseChanged(entry.id)
        }
        let binding = Self.packageBinding(for: entry)
        if let prior = priorEntries.first(where: {
            Self.packageBinding(for: $0) == binding
        }), prior.id != entry.id {
            throw ReleaseCatalogError.duplicatePackageBinding(
                packageID: entry.release.packageID,
                version: entry.release.version
            )
        }

        let snapshot = ReleaseInstallationContractSnapshot(
            entries: try (priorEntries + (priorEntries.contains(entry) ? [] : [entry]))
                .validatedCanonicalReleaseCatalog()
        )
        return try writeAndSeal(
            snapshot,
            afterGeneration: previous?.generation ?? 0
        )
    }

    /// Called only after the exact installed generation and its retained
    /// predecessor have been removed. Sealing the removal prevents a corrupt
    /// newest slot from resurrecting stale verification authority.
    @discardableResult
    public func retire(_ releaseID: ReleaseID) throws -> UInt64 {
        let previous = try loadEnvelope()
        let remaining = (previous?.snapshot.entries ?? []).filter {
            $0.id != releaseID
        }
        let snapshot = ReleaseInstallationContractSnapshot(
            entries: try remaining.validatedCanonicalReleaseCatalog()
        )
        return try writeAndSeal(
            snapshot,
            afterGeneration: previous?.generation ?? 0
        )
    }

    private func writeAndSeal(
        _ snapshot: ReleaseInstallationContractSnapshot,
        afterGeneration generation: UInt64
    ) throws -> UInt64 {
        try snapshot.validate()
        let first = generation &+ 1
        let second = first &+ 1
        guard first > generation, second > first else {
            throw ReleaseInstallationContractStoreError.corruptStorage
        }
        try write(snapshot, generation: first)
        try write(snapshot, generation: second)
        guard try loadEnvelope()?.snapshot == snapshot else {
            throw ReleaseInstallationContractStoreError.corruptStorage
        }
        return second
    }

    private func write(
        _ snapshot: ReleaseInstallationContractSnapshot,
        generation: UInt64
    ) throws {
        let material = ReleaseInstallationContractEnvelopeMaterial(
            envelopeFormatVersion: Self.envelopeFormatVersion,
            generation: generation,
            snapshot: snapshot
        )
        let envelope = ReleaseInstallationContractEnvelope(
            envelopeFormatVersion: Self.envelopeFormatVersion,
            generation: generation,
            snapshot: snapshot,
            authenticationCode: try Self.authenticationCode(
                for: material,
                key: integrityKey()
            )
        )
        let target = generation.isMultiple(of: 2) ? slotBURL : slotAURL
        try writer.writeAtomically(Self.encoder.encode(envelope), to: target)
    }

    private func loadEnvelope() throws -> ReleaseInstallationContractEnvelope? {
        let candidates = [slotAURL, slotBURL]
        let existing = candidates.filter {
            FileManager.default.fileExists(atPath: $0.path)
        }
        guard !existing.isEmpty else { return nil }

        let key = try integrityKey()
        let valid = existing.compactMap {
            url -> ReleaseInstallationContractEnvelope? in
            guard let data = try? Data(contentsOf: url),
                  let envelope = try? Self.decoder.decode(
                      ReleaseInstallationContractEnvelope.self,
                      from: data
                  ),
                  envelope.envelopeFormatVersion == Self.envelopeFormatVersion,
                  envelope.generation > 0,
                  (try? envelope.snapshot.validate()) != nil else {
                return nil
            }
            let material = ReleaseInstallationContractEnvelopeMaterial(
                envelopeFormatVersion: envelope.envelopeFormatVersion,
                generation: envelope.generation,
                snapshot: envelope.snapshot
            )
            guard (try? Self.isAuthenticated(
                envelope.authenticationCode,
                material: material,
                key: key
            )) == true else {
                return nil
            }
            return envelope
        }
        guard let newest = valid.max(by: { $0.generation < $1.generation }) else {
            throw ReleaseInstallationContractStoreError.corruptStorage
        }
        return newest
    }

    private func integrityKey() throws -> SymmetricKey {
        let data = try keyProvider.loadOrCreateKey()
        guard data.count >= 32 else {
            throw ReleaseInstallationContractStoreError.invalidIntegrityKey
        }
        return SymmetricKey(data: data)
    }

    private static func packageBinding(for entry: ReleaseCatalogEntry) -> String {
        "\(entry.release.packageID.rawValue)@\(entry.release.version)"
    }

    private static func authenticationCode<T: Encodable>(
        for value: T,
        key: SymmetricKey
    ) throws -> String {
        let code = HMAC<SHA256>.authenticationCode(
            for: try encoder.encode(value),
            using: key
        )
        return Data(code).map { String(format: "%02x", $0) }.joined()
    }

    private static func isAuthenticated<T: Encodable>(
        _ authenticationCode: String,
        material: T,
        key: SymmetricKey
    ) throws -> Bool {
        guard let code = hexadecimalData(authenticationCode) else { return false }
        return HMAC<SHA256>.isValidAuthenticationCode(
            code,
            authenticating: try encoder.encode(material),
            using: key
        )
    }

    private static func hexadecimalData(_ value: String) -> Data? {
        guard value.count.isMultiple(of: 2) else { return nil }
        var output = Data(capacity: value.count / 2)
        var index = value.startIndex
        while index < value.endIndex {
            let next = value.index(index, offsetBy: 2)
            guard let byte = UInt8(value[index ..< next], radix: 16) else {
                return nil
            }
            output.append(byte)
            index = next
        }
        return output
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }()

    private static let decoder = JSONDecoder()
}

private struct ReleaseInstallationContractEnvelope: Codable, Sendable {
    let envelopeFormatVersion: Int
    let generation: UInt64
    let snapshot: ReleaseInstallationContractSnapshot
    let authenticationCode: String
}

private struct ReleaseInstallationContractEnvelopeMaterial: Codable, Sendable {
    let envelopeFormatVersion: Int
    let generation: UInt64
    let snapshot: ReleaseInstallationContractSnapshot
}
