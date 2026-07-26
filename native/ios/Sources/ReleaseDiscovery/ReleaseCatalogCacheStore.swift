import ContentKit
import CryptoKit
import Foundation

public protocol ReleaseCacheIntegrityKeyProviding: Sendable {
    func loadOrCreateKey() throws -> Data
}

public protocol ReleaseCacheAtomicWriting: Sendable {
    func writeAtomically(_ data: Data, to url: URL) throws
}

public struct FoundationReleaseCacheWriter: ReleaseCacheAtomicWriting {
    public init() {}

    public func writeAtomically(_ data: Data, to url: URL) throws {
        try data.write(to: url, options: .atomic)
    }
}

public struct ReleaseCatalogCacheSnapshot: Codable, Equatable, Sendable {
    public static let currentFormatVersion = 1

    public let formatVersion: Int
    public let entries: [ReleaseCatalogEntry]
    public let notificationClaimedReleaseIDs: [ReleaseID]
    /// A bounded, authenticated acknowledgement marker for the latest tapped
    /// release. Only the stable ID is stored; the complete route is always
    /// resolved again from the authenticated catalog entry.
    public let pendingDeepLinkReleaseID: ReleaseID?
    public let baselineEstablished: Bool
    public let lastSuccessfulRefreshUnixMillis: Int64?

    public init(
        formatVersion: Int = currentFormatVersion,
        entries: [ReleaseCatalogEntry] = [],
        notificationClaimedReleaseIDs: [ReleaseID] = [],
        pendingDeepLinkReleaseID: ReleaseID? = nil,
        baselineEstablished: Bool = false,
        lastSuccessfulRefreshUnixMillis: Int64? = nil
    ) {
        self.formatVersion = formatVersion
        self.entries = entries
        self.notificationClaimedReleaseIDs = notificationClaimedReleaseIDs.sorted()
        self.pendingDeepLinkReleaseID = pendingDeepLinkReleaseID
        self.baselineEstablished = baselineEstablished
        self.lastSuccessfulRefreshUnixMillis = lastSuccessfulRefreshUnixMillis
    }

    public static let empty = ReleaseCatalogCacheSnapshot()

    public func validate() throws {
        guard formatVersion == Self.currentFormatVersion else {
            throw ReleaseCatalogCacheError.unsupportedFormat(formatVersion)
        }
        let canonical = try entries.validatedCanonicalReleaseCatalog()
        guard canonical == entries else {
            throw ReleaseCatalogCacheError.noncanonicalSnapshot
        }
        guard Set(notificationClaimedReleaseIDs).count == notificationClaimedReleaseIDs.count,
              notificationClaimedReleaseIDs == notificationClaimedReleaseIDs.sorted(),
              notificationClaimedReleaseIDs.allSatisfy({ Self.isStableID($0.rawValue) }),
              pendingDeepLinkReleaseID.map({ pendingID in
                  Self.isStableID(pendingID.rawValue)
                      && entries.contains(where: { $0.id == pendingID })
              }) ?? true,
              lastSuccessfulRefreshUnixMillis.map({ $0 >= 0 }) ?? true else {
            throw ReleaseCatalogCacheError.invalidSnapshot
        }
    }

    private enum CodingKeys: String, CodingKey {
        case formatVersion
        case entries
        case notificationClaimedReleaseIDs
        case pendingDeepLinkReleaseID
        case baselineEstablished
        case lastSuccessfulRefreshUnixMillis
    }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            formatVersion: try values.decode(Int.self, forKey: .formatVersion),
            entries: try values.decode([ReleaseCatalogEntry].self, forKey: .entries),
            notificationClaimedReleaseIDs: try values.decode(
                [ReleaseID].self,
                forKey: .notificationClaimedReleaseIDs
            ),
            pendingDeepLinkReleaseID: try values.decodeIfPresent(
                ReleaseID.self,
                forKey: .pendingDeepLinkReleaseID
            ),
            baselineEstablished: try values.decode(
                Bool.self,
                forKey: .baselineEstablished
            ),
            lastSuccessfulRefreshUnixMillis: try values.decodeIfPresent(
                Int64.self,
                forKey: .lastSuccessfulRefreshUnixMillis
            )
        )
    }

    public func encode(to encoder: any Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(formatVersion, forKey: .formatVersion)
        try values.encode(entries, forKey: .entries)
        try values.encode(
            notificationClaimedReleaseIDs,
            forKey: .notificationClaimedReleaseIDs
        )
        // Omitting nil preserves authentication of format-v1 snapshots that
        // predate the bounded pending marker.
        try values.encodeIfPresent(
            pendingDeepLinkReleaseID,
            forKey: .pendingDeepLinkReleaseID
        )
        try values.encode(baselineEstablished, forKey: .baselineEstablished)
        try values.encodeIfPresent(
            lastSuccessfulRefreshUnixMillis,
            forKey: .lastSuccessfulRefreshUnixMillis
        )
    }

    private static func isStableID(_ value: String) -> Bool {
        !value.isEmpty && !value.hasPrefix("-") && !value.hasSuffix("-")
            && value.utf8.allSatisfy {
                ($0 >= 97 && $0 <= 122) || ($0 >= 48 && $0 <= 57) || $0 == 45
            }
    }
}

public enum ReleaseCatalogCacheError: Error, Equatable, Sendable {
    case invalidIntegrityKey
    case unsupportedFormat(Int)
    case noncanonicalSnapshot
    case invalidSnapshot
    case corruptStorage
}

/// HMAC-authenticated, crash-safe two-slot cache. A corrupt newest slot falls
/// back to the older complete generation. If both slots are corrupt, a fully
/// validated remote catalog can explicitly rebuild both slots.
public struct ReleaseCatalogCacheStore: Sendable {
    private static let envelopeFormatVersion = 1

    public let directoryURL: URL
    private let keyProvider: any ReleaseCacheIntegrityKeyProviding
    private let writer: any ReleaseCacheAtomicWriting

    var slotAURL: URL {
        directoryURL.appendingPathComponent("release-catalog-a.json", isDirectory: false)
    }

    var slotBURL: URL {
        directoryURL.appendingPathComponent("release-catalog-b.json", isDirectory: false)
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

    public func load() throws -> ReleaseCatalogCacheSnapshot? {
        try loadEnvelope()?.snapshot
    }

    @discardableResult
    public func save(_ snapshot: ReleaseCatalogCacheSnapshot) throws -> UInt64 {
        try snapshot.validate()
        let previous = try loadEnvelope()
        let generation = (previous?.generation ?? 0) + 1
        try write(snapshot, generation: generation)

        // This cache is the durable notification and tap authority. Seal every
        // changed claim or bounded pending marker into both fallback
        // generations; corruption of the newest slot must neither duplicate a
        // notification nor lose or resurrect a release tap.
        if previous?.snapshot.notificationClaimedReleaseIDs
            != snapshot.notificationClaimedReleaseIDs
            || previous?.snapshot.pendingDeepLinkReleaseID
            != snapshot.pendingDeepLinkReleaseID {
            let sealingGeneration = generation + 1
            try write(snapshot, generation: sealingGeneration)
            return sealingGeneration
        }
        return generation
    }

    /// Use only after `load()` established that no authenticated slot remains.
    /// The first write already restores a valid fallback; the second seals the
    /// normal two-slot state for the next interrupted update.
    public func rebuildAfterCorruption(_ snapshot: ReleaseCatalogCacheSnapshot) throws {
        try snapshot.validate()
        try write(snapshot, generation: 1)
        try write(snapshot, generation: 2)
    }

    private func write(_ snapshot: ReleaseCatalogCacheSnapshot, generation: UInt64) throws {
        let material = ReleaseCacheEnvelopeMaterial(
            envelopeFormatVersion: Self.envelopeFormatVersion,
            generation: generation,
            snapshot: snapshot
        )
        let key = try integrityKey()
        let envelope = ReleaseCacheEnvelope(
            envelopeFormatVersion: Self.envelopeFormatVersion,
            generation: generation,
            snapshot: snapshot,
            authenticationCode: try Self.authenticationCode(for: material, key: key)
        )
        let target = generation.isMultiple(of: 2) ? slotBURL : slotAURL
        try writer.writeAtomically(Self.encoder.encode(envelope), to: target)
    }

    private func loadEnvelope() throws -> ReleaseCacheEnvelope? {
        let candidates = [slotAURL, slotBURL]
        let existing = candidates.filter { FileManager.default.fileExists(atPath: $0.path) }
        guard !existing.isEmpty else { return nil }

        let key = try integrityKey()
        let valid = existing.compactMap { url -> ReleaseCacheEnvelope? in
            guard let data = try? Data(contentsOf: url),
                  let envelope = try? Self.decoder.decode(ReleaseCacheEnvelope.self, from: data),
                  envelope.envelopeFormatVersion == Self.envelopeFormatVersion,
                  (try? envelope.snapshot.validate()) != nil else {
                return nil
            }
            let material = ReleaseCacheEnvelopeMaterial(
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
            throw ReleaseCatalogCacheError.corruptStorage
        }
        return newest
    }

    private func integrityKey() throws -> SymmetricKey {
        let data = try keyProvider.loadOrCreateKey()
        guard data.count >= 32 else {
            throw ReleaseCatalogCacheError.invalidIntegrityKey
        }
        return SymmetricKey(data: data)
    }

    private static func authenticationCode<T: Encodable>(
        for value: T,
        key: SymmetricKey
    ) throws -> String {
        let code = HMAC<SHA256>.authenticationCode(for: try encoder.encode(value), using: key)
        return Data(code).map { String(format: "%02x", $0) }.joined()
    }

    private static func isAuthenticated<T: Encodable>(
        _ authenticationCode: String,
        material: T,
        key: SymmetricKey
    ) throws -> Bool {
        guard let code = Data(hexadecimalString: authenticationCode) else { return false }
        return HMAC<SHA256>.isValidAuthenticationCode(
            code,
            authenticating: try encoder.encode(material),
            using: key
        )
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }()

    private static let decoder = JSONDecoder()
}

private struct ReleaseCacheEnvelope: Codable, Sendable {
    let envelopeFormatVersion: Int
    let generation: UInt64
    let snapshot: ReleaseCatalogCacheSnapshot
    let authenticationCode: String
}

private struct ReleaseCacheEnvelopeMaterial: Codable, Sendable {
    let envelopeFormatVersion: Int
    let generation: UInt64
    let snapshot: ReleaseCatalogCacheSnapshot
}

private extension Data {
    init?(hexadecimalString: String) {
        guard hexadecimalString.count.isMultiple(of: 2) else { return nil }
        var result = Data(capacity: hexadecimalString.count / 2)
        var index = hexadecimalString.startIndex
        while index < hexadecimalString.endIndex {
            let next = hexadecimalString.index(index, offsetBy: 2)
            guard let byte = UInt8(hexadecimalString[index ..< next], radix: 16) else {
                return nil
            }
            result.append(byte)
            index = next
        }
        self = result
    }
}
