import ContentKit
import CryptoKit
import Foundation

public protocol EntitlementIntegrityKeyProviding: Sendable {
    func loadOrCreateKey() throws -> Data
}

public protocol EntitlementSnapshotAtomicWriting: Sendable {
    func writeAtomically(_ data: Data, to url: URL) throws
}

public struct FoundationEntitlementSnapshotWriter: EntitlementSnapshotAtomicWriting {
    public init() {}

    public func writeAtomically(_ data: Data, to url: URL) throws {
        try data.write(to: url, options: .atomic)
    }
}

public enum EntitlementSnapshotStoreError: Error, Equatable, Sendable {
    case invalidIntegrityKey
    case unsupportedSnapshotFormat(Int)
    case productIdentifierMismatch
    case invalidSnapshot
    case corruptStorage
    case denialSealingIncomplete
}

/// HMAC-authenticated, crash-safe two-slot persistence for the last verified
/// ownership state. The older valid slot is retained while the next generation
/// is atomically replaced, so an interrupted write rolls back to a complete
/// authenticated snapshot rather than silently becoming "not purchased".
public struct EntitlementSnapshotStore: Sendable {
    private static let envelopeFormatVersion = 1

    public let directoryURL: URL
    private let keyProvider: any EntitlementIntegrityKeyProviding
    private let writer: any EntitlementSnapshotAtomicWriting

    private var slotAURL: URL {
        directoryURL.appendingPathComponent("entitlement-snapshot-a.json", isDirectory: false)
    }

    private var slotBURL: URL {
        directoryURL.appendingPathComponent("entitlement-snapshot-b.json", isDirectory: false)
    }

    public init(
        directoryURL: URL,
        keyProvider: any EntitlementIntegrityKeyProviding,
        writer: any EntitlementSnapshotAtomicWriting = FoundationEntitlementSnapshotWriter()
    ) throws {
        self.directoryURL = directoryURL
        self.keyProvider = keyProvider
        self.writer = writer
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
    }

    public func load() throws -> EntitlementSnapshot? {
        try loadEnvelope()?.snapshot
    }

    @discardableResult
    public func save(_ snapshot: EntitlementSnapshot) throws -> UInt64 {
        try Self.validate(snapshot)
        let previous = try loadEnvelope()
        let generation = (previous?.generation ?? 0) + 1
        try write(snapshot, generation: generation)

        // A completed denial transition must not leave an older owned slot as
        // the only fallback. Seal the denial into the second generation before
        // the caller can finish the StoreKit transaction. If this second write
        // is interrupted, the first denial is already the newest valid slot and
        // StoreKit will redeliver because the caller has not finished it yet.
        if previous?.snapshot.state == .owned, snapshot.state != .owned {
            let sealingGeneration = generation + 1
            do {
                try write(snapshot, generation: sealingGeneration)
            } catch {
                throw EntitlementSnapshotStoreError.denialSealingIncomplete
            }
            return sealingGeneration
        }
        return generation
    }

    private func write(_ snapshot: EntitlementSnapshot, generation: UInt64) throws {
        let material = EntitlementEnvelopeMaterial(
            envelopeFormatVersion: Self.envelopeFormatVersion,
            generation: generation,
            snapshot: snapshot
        )
        let key = try integrityKey()
        let envelope = EntitlementEnvelope(
            envelopeFormatVersion: Self.envelopeFormatVersion,
            generation: generation,
            snapshot: snapshot,
            authenticationCode: try Self.authenticationCode(for: material, key: key)
        )
        let target = generation.isMultiple(of: 2) ? slotBURL : slotAURL
        try writer.writeAtomically(Self.encoder.encode(envelope), to: target)
    }

    private func loadEnvelope() throws -> EntitlementEnvelope? {
        let candidates = [slotAURL, slotBURL]
        let existing = candidates.filter { FileManager.default.fileExists(atPath: $0.path) }
        guard !existing.isEmpty else { return nil }

        let key = try integrityKey()
        let valid = existing.compactMap { url -> EntitlementEnvelope? in
            guard let data = try? Data(contentsOf: url),
                  let envelope = try? Self.decoder.decode(EntitlementEnvelope.self, from: data),
                  envelope.envelopeFormatVersion == Self.envelopeFormatVersion,
                  (try? Self.validate(envelope.snapshot)) != nil else {
                return nil
            }
            let material = EntitlementEnvelopeMaterial(
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
            throw EntitlementSnapshotStoreError.corruptStorage
        }
        return newest
    }

    private func integrityKey() throws -> SymmetricKey {
        let data = try keyProvider.loadOrCreateKey()
        guard data.count >= 32 else {
            throw EntitlementSnapshotStoreError.invalidIntegrityKey
        }
        return SymmetricKey(data: data)
    }

    private static func validate(_ snapshot: EntitlementSnapshot) throws {
        guard snapshot.formatVersion == EntitlementSnapshot.currentFormatVersion else {
            throw EntitlementSnapshotStoreError.unsupportedSnapshotFormat(snapshot.formatVersion)
        }
        guard snapshot.productID == LaunchContent.fullWorkStoreProductID else {
            throw EntitlementSnapshotStoreError.productIdentifierMismatch
        }

        switch snapshot.state {
        case .notPurchased:
            guard snapshot.transactionID == nil,
                  snapshot.originalTransactionID == nil,
                  snapshot.purchaseDate == nil,
                  snapshot.expirationDate == nil,
                  snapshot.revocationDate == nil,
                  snapshot.revocationReason == nil,
                  snapshot.revocationType == nil else {
                throw EntitlementSnapshotStoreError.invalidSnapshot
            }
        case .owned:
            guard snapshot.transactionID != nil,
                  snapshot.originalTransactionID != nil,
                  snapshot.purchaseDate != nil,
                  snapshot.revocationDate == nil,
                  snapshot.revocationReason == nil,
                  snapshot.revocationType == nil else {
                throw EntitlementSnapshotStoreError.invalidSnapshot
            }
        case .revoked:
            guard snapshot.transactionID != nil,
                  snapshot.originalTransactionID != nil,
                  snapshot.purchaseDate != nil,
                  snapshot.revocationDate != nil else {
                throw EntitlementSnapshotStoreError.invalidSnapshot
            }
        case .expired:
            guard snapshot.transactionID != nil,
                  snapshot.originalTransactionID != nil,
                  snapshot.purchaseDate != nil,
                  snapshot.expirationDate != nil,
                  snapshot.revocationDate == nil else {
                throw EntitlementSnapshotStoreError.invalidSnapshot
            }
        }
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
        guard let codeData = Data(hexadecimalString: authenticationCode) else { return false }
        return HMAC<SHA256>.isValidAuthenticationCode(
            codeData,
            authenticating: try encoder.encode(material),
            using: key
        )
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .millisecondsSince1970
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return decoder
    }()
}

private struct EntitlementEnvelope: Codable, Sendable {
    let envelopeFormatVersion: Int
    let generation: UInt64
    let snapshot: EntitlementSnapshot
    let authenticationCode: String
}

private struct EntitlementEnvelopeMaterial: Codable, Sendable {
    let envelopeFormatVersion: Int
    let generation: UInt64
    let snapshot: EntitlementSnapshot
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
