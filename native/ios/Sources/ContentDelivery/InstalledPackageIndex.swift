import ContentKit
import CryptoKit
import Foundation

public struct InstalledPackageGeneration: Codable, Equatable, Sendable {
    public let generationID: String
    public let packageID: PackageID
    public let packageVersion: SchemaVersion
    public let manifestDigest: String
    public let relativePath: String
    public let activationSequence: UInt64

    public init(
        generationID: String,
        packageID: PackageID,
        packageVersion: SchemaVersion,
        manifestDigest: String,
        relativePath: String,
        activationSequence: UInt64
    ) {
        self.generationID = generationID
        self.packageID = packageID
        self.packageVersion = packageVersion
        self.manifestDigest = manifestDigest
        self.relativePath = relativePath
        self.activationSequence = activationSequence
    }
}

public struct InstalledPackageIndex: Codable, Equatable, Sendable {
    public static let currentFormatVersion = 1

    public let formatVersion: Int
    public var nextActivationSequence: UInt64
    public var generations: [InstalledPackageGeneration]
    public var activeGenerationByPackage: [PackageID: String]

    public init(
        formatVersion: Int = currentFormatVersion,
        nextActivationSequence: UInt64 = 1,
        generations: [InstalledPackageGeneration] = [],
        activeGenerationByPackage: [PackageID: String] = [:]
    ) {
        self.formatVersion = formatVersion
        self.nextActivationSequence = nextActivationSequence
        self.generations = generations
        self.activeGenerationByPackage = activeGenerationByPackage
    }

    public static let empty = InstalledPackageIndex()

    private enum CodingKeys: String, CodingKey {
        case formatVersion
        case nextActivationSequence
        case generations
        case activeGenerationByPackage
    }

    /// StableID dictionary keys would otherwise be encoded by JSONEncoder as
    /// an alternating unkeyed array whose iteration order is not canonical.
    /// The index digest is computed in a separate encode pass, so two active
    /// packages could make a valid envelope fail its own digest check. Persist
    /// raw package IDs as ordinary string keys; `.sortedKeys` can then
    /// canonicalise both digest material and the envelope byte-for-byte.
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(formatVersion, forKey: .formatVersion)
        try container.encode(nextActivationSequence, forKey: .nextActivationSequence)
        try container.encode(generations, forKey: .generations)
        let stablePointers = Dictionary(uniqueKeysWithValues:
            activeGenerationByPackage.map { ($0.key.rawValue, $0.value) }
        )
        try container.encode(stablePointers, forKey: .activeGenerationByPackage)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        formatVersion = try container.decode(Int.self, forKey: .formatVersion)
        nextActivationSequence = try container.decode(
            UInt64.self,
            forKey: .nextActivationSequence
        )
        generations = try container.decode(
            [InstalledPackageGeneration].self,
            forKey: .generations
        )
        if let stablePointers = try? container.decode(
            [String: String].self,
            forKey: .activeGenerationByPackage
        ) {
            activeGenerationByPackage = Dictionary(uniqueKeysWithValues:
                stablePointers.map { (PackageID($0.key), $0.value) }
            )
        } else {
            // Keep the value decoder compatible with the earlier development
            // shape. The enclosing two-slot digest remains the authority over
            // whether any persisted envelope is accepted.
            activeGenerationByPackage = try container.decode(
                [PackageID: String].self,
                forKey: .activeGenerationByPackage
            )
        }
    }

    public func activeGeneration(for packageID: PackageID) -> InstalledPackageGeneration? {
        guard let generationID = activeGenerationByPackage[packageID] else { return nil }
        return generations.first { $0.generationID == generationID }
    }

    public func retainedGenerations(for packageID: PackageID) -> [InstalledPackageGeneration] {
        generations
            .filter { $0.packageID == packageID }
            .sorted { $0.activationSequence > $1.activationSequence }
    }

    @discardableResult
    mutating func recordActivation(
        _ generation: InstalledPackageGeneration
    ) throws -> [InstalledPackageGeneration] {
        guard generation.activationSequence == nextActivationSequence else {
            throw InstalledPackageIndexError.invalidActivationSequence
        }
        let nextSequence = nextActivationSequence.addingReportingOverflow(1)
        guard !nextSequence.overflow else {
            throw InstalledPackageIndexError.invalidActivationSequence
        }
        let previouslyActiveID = activeGenerationByPackage[generation.packageID]
        var retainedIDs = Set([generation.generationID])
        if let previouslyActiveID {
            retainedIDs.insert(previouslyActiveID)
        }
        let removed = generations.filter {
            $0.packageID == generation.packageID && !retainedIDs.contains($0.generationID)
        }
        generations.removeAll {
            $0.packageID == generation.packageID && !retainedIDs.contains($0.generationID)
        }
        generations.append(generation)
        generations.sort {
            if $0.packageID != $1.packageID { return $0.packageID < $1.packageID }
            return $0.activationSequence < $1.activationSequence
        }
        activeGenerationByPackage[generation.packageID] = generation.generationID
        nextActivationSequence = nextSequence.partialValue
        try validate()
        return removed
    }

    mutating func activateRetainedGeneration(_ generationID: String, packageID: PackageID) throws {
        guard generations.contains(where: {
            $0.generationID == generationID && $0.packageID == packageID
        }) else {
            throw InstalledPackageIndexError.unknownGeneration(generationID)
        }
        activeGenerationByPackage[packageID] = generationID
        try validate()
    }

    /// Removes only the active pointer when it still names the exact
    /// generation which reported an integrity failure. The immutable
    /// generation record stays in the index so reconciliation preserves its
    /// bytes for diagnosis and a controlled recovery decision.
    @discardableResult
    mutating func deactivateActiveGeneration(
        packageID: PackageID,
        expectedGenerationID: String
    ) throws -> InstalledPackageGeneration? {
        guard activeGenerationByPackage[packageID] == expectedGenerationID,
              let generation = generations.first(where: {
                  $0.packageID == packageID
                      && $0.generationID == expectedGenerationID
              }) else {
            return nil
        }
        activeGenerationByPackage.removeValue(forKey: packageID)
        try validate()
        return generation
    }

    func validate() throws {
        guard formatVersion == Self.currentFormatVersion, nextActivationSequence > 0 else {
            throw InstalledPackageIndexError.unsupportedFormat(formatVersion)
        }
        let generationIDs = generations.map(\.generationID)
        guard Set(generationIDs).count == generationIDs.count else {
            throw InstalledPackageIndexError.duplicateGeneration
        }
        guard generations.allSatisfy({ generation in
            Self.isStablePathComponent(generation.generationID)
                && Self.isSafeRelativePath(generation.relativePath)
                && Self.isSHA256(generation.manifestDigest)
                && generation.activationSequence > 0
                && generation.activationSequence < nextActivationSequence
        }) else {
            throw InstalledPackageIndexError.invalidGeneration
        }
        guard Set(generations.map(\.activationSequence)).count == generations.count else {
            throw InstalledPackageIndexError.invalidActivationSequence
        }
        for (packageID, generationID) in activeGenerationByPackage {
            guard generations.contains(where: {
                $0.packageID == packageID && $0.generationID == generationID
            }) else {
                throw InstalledPackageIndexError.activeGenerationMissing(packageID.rawValue)
            }
        }
    }

    private static func isSHA256(_ value: String) -> Bool {
        value.utf8.count == 64 && value.utf8.allSatisfy {
            ($0 >= 48 && $0 <= 57) || ($0 >= 97 && $0 <= 102)
        }
    }

    private static func isStablePathComponent(_ value: String) -> Bool {
        !value.isEmpty && !value.hasPrefix("-") && !value.hasSuffix("-")
            && value.utf8.allSatisfy {
                ($0 >= 97 && $0 <= 122) || ($0 >= 48 && $0 <= 57) || $0 == 45
            }
    }

    private static func isSafeRelativePath(_ value: String) -> Bool {
        let components = value.split(separator: "/", omittingEmptySubsequences: false)
        return !value.isEmpty && !value.hasPrefix("/") && !value.contains("\\")
            && !value.contains("://")
            && components.allSatisfy { !$0.isEmpty && $0 != "." && $0 != ".." }
    }
}

public enum InstalledPackageIndexError: Error, Equatable, Sendable {
    case unsupportedFormat(Int)
    case requiresNewerApp(Int)
    case invalidActivationSequence
    case duplicateGeneration
    case invalidGeneration
    case activeGenerationMissing(String)
    case unknownGeneration(String)
    case corruptIndex
    case missingActiveDirectory(String)
}

struct InstalledPackageIndexStore: Sendable {
    private static let envelopeFormatVersion = 1

    let directoryURL: URL

    private var slotAURL: URL { directoryURL.appending(path: "installed-index-a.json") }
    private var slotBURL: URL { directoryURL.appending(path: "installed-index-b.json") }

    init(directoryURL: URL) throws {
        self.directoryURL = directoryURL
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    }

    func load() throws -> InstalledPackageIndex {
        try loadEnvelope()?.index ?? .empty
    }

    /// Maintenance is allowed only when both durable slots independently
    /// validate under this runtime and carry the same compact index state.
    func agreedCurrentIndex() -> InstalledPackageIndex? {
        guard let slotAData = try? Data(contentsOf: slotAURL),
              let slotBData = try? Data(contentsOf: slotBURL),
              let slotA = validCurrentEnvelope(from: slotAData),
              let slotB = validCurrentEnvelope(from: slotBData),
              slotA.index == slotB.index else {
            return nil
        }
        return slotA.index
    }

    @discardableResult
    func save(_ index: InstalledPackageIndex) throws -> UInt64 {
        try index.validate()
        let prior = try loadEnvelope()
        let generation = (prior?.generation ?? 0) + 1
        let material = IndexDigestMaterial(
            envelopeFormatVersion: Self.envelopeFormatVersion,
            generation: generation,
            index: index
        )
        let envelope = InstalledIndexEnvelope(
            envelopeFormatVersion: Self.envelopeFormatVersion,
            generation: generation,
            index: index,
            digest: try Self.digest(material)
        )
        let target = generation.isMultiple(of: 2) ? slotBURL : slotAURL
        try Self.encoder.encode(envelope).write(to: target, options: [.atomic])
        return generation
    }

    /// The caller has already committed `index` with one atomic `save`. This
    /// advances the alternate slot to the same state and verifies that both
    /// slots agree before destructive maintenance can begin.
    func mirrorCommittedState(_ index: InstalledPackageIndex) throws {
        _ = try save(index)
        guard agreedCurrentIndex() == index else {
            throw InstalledPackageIndexError.corruptIndex
        }
    }

    private func loadEnvelope() throws -> InstalledIndexEnvelope? {
        let candidates = [slotAURL, slotBURL]
        let existing = candidates.filter { FileManager.default.fileExists(atPath: $0.path) }
        guard !existing.isEmpty else { return nil }
        let slotData = existing.compactMap { try? Data(contentsOf: $0) }
        let newestFuture = slotData.compactMap {
            TwoSlotFutureAuthority.inspect(
                data: $0,
                payloadKey: "index",
                currentEnvelopeFormatVersion: Self.envelopeFormatVersion,
                currentPayloadFormatVersion: InstalledPackageIndex.currentFormatVersion
            )
        }.max(by: { $0.generation < $1.generation })
        let valid = slotData.compactMap(validCurrentEnvelope(from:))
        let newest = valid.max(by: { $0.generation < $1.generation })
        if let newestFuture,
           newestFuture.generation >= (newest?.generation ?? 0) {
            throw InstalledPackageIndexError.requiresNewerApp(
                newestFuture.requiredFormatVersion
            )
        }
        guard let newest else {
            throw InstalledPackageIndexError.corruptIndex
        }
        return newest
    }

    private func validCurrentEnvelope(from data: Data) -> InstalledIndexEnvelope? {
        guard let envelope = try? Self.decoder.decode(InstalledIndexEnvelope.self, from: data),
              envelope.envelopeFormatVersion == Self.envelopeFormatVersion,
              envelope.generation > 0,
              (try? envelope.index.validate()) != nil else {
            return nil
        }
        let material = IndexDigestMaterial(
            envelopeFormatVersion: envelope.envelopeFormatVersion,
            generation: envelope.generation,
            index: envelope.index
        )
        guard (try? Self.digest(material)) == envelope.digest else { return nil }
        return envelope
    }

    private static func digest<T: Encodable>(_ value: T) throws -> String {
        SHA256.hash(data: try encoder.encode(value)).map { String(format: "%02x", $0) }.joined()
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }()

    private static let decoder = JSONDecoder()
}

private struct InstalledIndexEnvelope: Codable, Sendable {
    let envelopeFormatVersion: Int
    let generation: UInt64
    let index: InstalledPackageIndex
    let digest: String
}

private struct IndexDigestMaterial: Codable, Sendable {
    let envelopeFormatVersion: Int
    let generation: UInt64
    let index: InstalledPackageIndex
}
