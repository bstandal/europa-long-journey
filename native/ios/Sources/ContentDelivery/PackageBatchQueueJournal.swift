import ContentKit
import CryptoKit
import Foundation

public enum PackageBatchQueueIntent: String, Codable, Equatable, Sendable {
    case running
    case paused
    case failed
    case completed
}

public struct PackageBatchQueueJournal: Codable, Equatable, Sendable {
    public static let currentFormatVersion = 1

    public let formatVersion: Int
    public let intent: PackageBatchQueueIntent
    public let packages: [ContentPackageSpec]
    public let completedPackageIDs: [PackageID]
    public let failedPackageID: PackageID?
    public let failure: PackageBatchFailure?

    public init(
        formatVersion: Int = currentFormatVersion,
        intent: PackageBatchQueueIntent,
        packages: [ContentPackageSpec],
        completedPackageIDs: [PackageID],
        failedPackageID: PackageID? = nil,
        failure: PackageBatchFailure? = nil
    ) {
        self.formatVersion = formatVersion
        self.intent = intent
        self.packages = packages
        self.completedPackageIDs = completedPackageIDs
        self.failedPackageID = failedPackageID
        self.failure = failure
    }

    func validate() throws {
        guard formatVersion == Self.currentFormatVersion else {
            throw PackageBatchQueueJournalError.unsupportedFormat(formatVersion)
        }
        let packageIDs = packages.map(\.id)
        guard Set(packageIDs).count == packageIDs.count else {
            throw PackageBatchQueueJournalError.duplicatePackageID
        }
        guard Set(completedPackageIDs).count == completedPackageIDs.count,
              completedPackageIDs == Array(packageIDs.prefix(completedPackageIDs.count)) else {
            throw PackageBatchQueueJournalError.invalidCompletedPackages
        }

        switch intent {
        case .failed:
            guard let failedPackageID,
                  let failure,
                  completedPackageIDs.count < packageIDs.count,
                  failedPackageID == packageIDs[completedPackageIDs.count] else {
                throw PackageBatchQueueJournalError.invalidFailure
            }
            _ = failure
        case .completed:
            guard completedPackageIDs == packageIDs,
                  failedPackageID == nil,
                  failure == nil else {
                throw PackageBatchQueueJournalError.invalidCompletion
            }
        case .running, .paused:
            guard completedPackageIDs.count < packageIDs.count else {
                throw PackageBatchQueueJournalError.invalidCompletion
            }
            guard failedPackageID == nil,
                  failure == nil else {
                throw PackageBatchQueueJournalError.invalidFailure
            }
        }
    }
}

public enum PackageBatchQueueJournalError: Error, Equatable, Sendable {
    case unsupportedFormat(Int)
    case requiresNewerApp(Int)
    case duplicatePackageID
    case invalidCompletedPackages
    case invalidFailure
    case invalidCompletion
    case corruptJournal
}

/// A digest-checked two-slot journal. Each save is an atomic replacement of one
/// complete slot; the other slot remains a recoverable prior generation.
public final class PackageBatchQueueJournalStore: @unchecked Sendable {
    private static let envelopeFormatVersion = 1

    public let directoryURL: URL
    public let retiredQueuesDirectoryURL: URL
    private let lock = NSLock()

    private var slotAURL: URL { directoryURL.appending(path: "package-queue-a.json") }
    private var slotBURL: URL { directoryURL.appending(path: "package-queue-b.json") }

    public init(directoryURL: URL) throws {
        self.directoryURL = directoryURL.standardizedFileURL
        retiredQueuesDirectoryURL = self.directoryURL.appending(
            path: "RetiredPackageQueues",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(
            at: self.directoryURL,
            withIntermediateDirectories: true
        )
    }

    public func load() throws -> PackageBatchQueueJournal? {
        try lock.withLock { try loadEnvelope()?.journal }
    }

    @discardableResult
    public func save(_ journal: PackageBatchQueueJournal) throws -> UInt64 {
        try lock.withLock {
            try saveUnlocked(journal)
        }
    }

    /// Preserves both durable slots byte-for-byte, then advances the journal
    /// authority to an empty completed tombstone. This retires pending queue
    /// intent without deleting installed content or relying on two-file
    /// deletion being atomic.
    @discardableResult
    public func retireCurrentQueue() throws -> URL {
        try lock.withLock {
            let unreadable: Bool
            do {
                _ = try loadEnvelope()
                unreadable = false
            } catch PackageBatchQueueJournalError.corruptJournal {
                unreadable = true
            }
            let retiredURL = retiredQueuesDirectoryURL.appending(
                path: "retired-\(UUID().uuidString.lowercased())",
                directoryHint: .isDirectory
            )
            try FileManager.default.createDirectory(
                at: retiredURL,
                withIntermediateDirectories: true
            )
            do {
                for source in [slotAURL, slotBURL]
                    where FileManager.default.fileExists(atPath: source.path)
                {
                    try FileManager.default.copyItem(
                        at: source,
                        to: retiredURL.appending(path: source.lastPathComponent)
                    )
                }
                let tombstone = PackageBatchQueueJournal(
                    intent: .completed,
                    packages: [],
                    completedPackageIDs: []
                )
                if unreadable {
                    try writeRecoveryTombstoneUnlocked(tombstone)
                } else {
                    _ = try saveUnlocked(tombstone)
                }
                return retiredURL
            } catch {
                try? FileManager.default.removeItem(at: retiredURL)
                throw error
            }
        }
    }

    /// Establishes a new valid authority when every prior slot is unreadable.
    /// The caller has already copied both original slots to RetiredPackageQueues.
    private func writeRecoveryTombstoneUnlocked(
        _ journal: PackageBatchQueueJournal
    ) throws {
        try journal.validate()
        let generation: UInt64 = 1
        let material = QueueJournalDigestMaterial(
            envelopeFormatVersion: Self.envelopeFormatVersion,
            generation: generation,
            journal: journal
        )
        let envelope = PackageBatchQueueJournalEnvelope(
            envelopeFormatVersion: Self.envelopeFormatVersion,
            generation: generation,
            journal: journal,
            digest: try Self.digest(material)
        )
        try Self.encode(envelope).write(to: slotAURL, options: [.atomic])
    }

    private func saveUnlocked(_ journal: PackageBatchQueueJournal) throws -> UInt64 {
        try journal.validate()
        let prior = try loadEnvelope()
        let generation = (prior?.generation ?? 0) + 1
        let material = QueueJournalDigestMaterial(
            envelopeFormatVersion: Self.envelopeFormatVersion,
            generation: generation,
            journal: journal
        )
        let envelope = PackageBatchQueueJournalEnvelope(
            envelopeFormatVersion: Self.envelopeFormatVersion,
            generation: generation,
            journal: journal,
            digest: try Self.digest(material)
        )
        let target = generation.isMultiple(of: 2) ? slotBURL : slotAURL
        try Self.encode(envelope).write(to: target, options: [.atomic])
        return generation
    }

    private func loadEnvelope() throws -> PackageBatchQueueJournalEnvelope? {
        let candidates = [slotAURL, slotBURL]
        let existing = candidates.filter { FileManager.default.fileExists(atPath: $0.path) }
        guard !existing.isEmpty else { return nil }

        let slotData = existing.compactMap { try? Data(contentsOf: $0) }
        let newestFuture = slotData.compactMap {
            TwoSlotFutureAuthority.inspect(
                data: $0,
                payloadKey: "journal",
                currentEnvelopeFormatVersion: Self.envelopeFormatVersion,
                currentPayloadFormatVersion: PackageBatchQueueJournal.currentFormatVersion
            )
        }.max(by: { $0.generation < $1.generation })
        let valid = slotData.compactMap { data -> PackageBatchQueueJournalEnvelope? in
            guard
                  let envelope = try? JSONDecoder().decode(
                      PackageBatchQueueJournalEnvelope.self,
                      from: data
                  ),
                  envelope.envelopeFormatVersion == Self.envelopeFormatVersion,
                  (try? envelope.journal.validate()) != nil else {
                return nil
            }
            let material = QueueJournalDigestMaterial(
                envelopeFormatVersion: envelope.envelopeFormatVersion,
                generation: envelope.generation,
                journal: envelope.journal
            )
            guard (try? Self.digest(material)) == envelope.digest else { return nil }
            return envelope
        }
        let newest = valid.max(by: { $0.generation < $1.generation })
        if let newestFuture,
           newestFuture.generation >= (newest?.generation ?? 0) {
            throw PackageBatchQueueJournalError.requiresNewerApp(
                newestFuture.requiredFormatVersion
            )
        }
        guard let newest else {
            throw PackageBatchQueueJournalError.corruptJournal
        }
        return newest
    }

    private static func digest<T: Encodable>(_ value: T) throws -> String {
        SHA256.hash(data: try encode(value))
            .map { String(format: "%02x", $0) }
            .joined()
    }

    private static func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(value)
    }
}

private struct PackageBatchQueueJournalEnvelope: Codable, Sendable {
    let envelopeFormatVersion: Int
    let generation: UInt64
    let journal: PackageBatchQueueJournal
    let digest: String
}

private struct QueueJournalDigestMaterial: Codable, Sendable {
    let envelopeFormatVersion: Int
    let generation: UInt64
    let journal: PackageBatchQueueJournal
}
