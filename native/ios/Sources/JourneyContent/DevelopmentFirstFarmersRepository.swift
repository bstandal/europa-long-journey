#if DEBUG
import ContentKit
import CryptoKit
import Foundation
import JourneyDomain

public enum DevelopmentFirstFarmersRepositoryError: Error, Equatable, Sendable,
    CustomStringConvertible {
    case invalidPayload(String)
    case wrongPackage(PackageID)
    case wrongSchemaVersion(SchemaVersion)
    case wrongChapterSet([ChapterID])

    public var description: String {
        switch self {
        case let .invalidPayload(reason):
            "The development payload failed canonical validation: \(reason)"
        case let .wrongPackage(packageID):
            "The development payload has the wrong package identity: \(packageID)"
        case let .wrongSchemaVersion(version):
            "The development payload has an unsupported schema version: \(version)"
        case let .wrongChapterSet(chapterIDs):
            "The development payload contains the wrong chapter set: \(chapterIDs)"
        }
    }
}

/// One exact, isolated index for the generated Chapter 01 projection. It has
/// no CollectionManifest initializer and cannot satisfy launch-essential
/// assembly. The type does not exist in non-DEBUG binaries.
public struct DevelopmentFirstFarmersRepository: ChapterContentRepository {
    public static let packageID = PackageID("first-farmers-development-v1")
    public static let chapterID = ChapterID("first-farmers")
    public static let supportedSchemaVersion = SchemaVersion(major: 1)

    public let worldSeed: WorldSeedSpec
    public let contentVersion: SchemaVersion

    private let chapterByID: [ChapterID: ChapterSpec]
    private let arcByID: [ArcID: ArcSpec]
    private let beatByID: [BeatID: BeatSpec]
    private let sceneByID: [SceneID: SceneSpec]
    private let interactionByID: [InteractionID: InteractionSpec]
    private let accessibilityByID: [AccessibilityID: AccessibilitySpec]
    private let timelineByID: [AudioTimelineID: AudioTimeline]
    private let timelineIDByCueID: [AudioCueID: AudioTimelineID]
    private let responsiveProgramByInteractionID: [InteractionID: ResponsiveAudioProgramSpec]
    private let arcLocationByID: [ArcID: ArcContentLocation]
    private let beatLocationByID: [BeatID: BeatContentLocation]

    public init(payload: ContentPackagePayload) throws {
        do {
            try payload.validate()
        } catch {
            throw DevelopmentFirstFarmersRepositoryError.invalidPayload(
                String(describing: error)
            )
        }
        guard payload.packageID == Self.packageID else {
            throw DevelopmentFirstFarmersRepositoryError.wrongPackage(payload.packageID)
        }
        guard payload.schemaVersion == Self.supportedSchemaVersion else {
            throw DevelopmentFirstFarmersRepositoryError.wrongSchemaVersion(
                payload.schemaVersion
            )
        }
        let chapterIDs = payload.chapters.map(\.id)
        guard chapterIDs == [Self.chapterID] else {
            throw DevelopmentFirstFarmersRepositoryError.wrongChapterSet(chapterIDs)
        }

        worldSeed = payload.worldSeed
        contentVersion = payload.schemaVersion
        chapterByID = Dictionary(uniqueKeysWithValues: payload.chapters.map { ($0.id, $0) })
        sceneByID = Dictionary(uniqueKeysWithValues: payload.scenes.map { ($0.id, $0) })
        accessibilityByID = Dictionary(
            uniqueKeysWithValues: payload.accessibility.map { ($0.id, $0) }
        )
        timelineByID = Dictionary(
            uniqueKeysWithValues: payload.audioTimelines.map { ($0.id, $0) }
        )

        var arcs: [ArcID: ArcSpec] = [:]
        var beats: [BeatID: BeatSpec] = [:]
        var arcLocations: [ArcID: ArcContentLocation] = [:]
        var beatLocations: [BeatID: BeatContentLocation] = [:]
        for chapter in payload.chapters {
            for (arcIndex, arc) in chapter.arcs.enumerated() {
                arcs[arc.id] = arc
                arcLocations[arc.id] = ArcContentLocation(
                    chapterID: chapter.id,
                    arcIndex: arcIndex
                )
                for (beatIndex, beat) in arc.beats.enumerated() {
                    beats[beat.id] = beat
                    beatLocations[beat.id] = BeatContentLocation(
                        chapterID: chapter.id,
                        arcID: arc.id,
                        arcIndex: arcIndex,
                        beatIndex: beatIndex
                    )
                }
            }
        }
        arcByID = arcs
        beatByID = beats
        interactionByID = Dictionary(
            uniqueKeysWithValues: beats.values.compactMap { beat in
                beat.interaction.map { ($0.id, $0) }
            }
        )
        arcLocationByID = arcLocations
        beatLocationByID = beatLocations

        timelineIDByCueID = Dictionary(
            uniqueKeysWithValues: payload.audioTimelines.flatMap { timeline in
                timeline.events.map { ($0.cueID, timeline.id) }
            }
        )
        responsiveProgramByInteractionID = Dictionary(
            uniqueKeysWithValues: payload.responsiveAudioPrograms.map {
                ($0.scope.interactionID, $0)
            }
        )
    }

    public func chapter(_ id: ChapterID) -> ChapterSpec? { chapterByID[id] }
    public func arc(_ id: ArcID) -> ArcSpec? { arcByID[id] }
    public func beat(_ id: BeatID) -> BeatSpec? { beatByID[id] }
    public func scene(_ id: SceneID) -> SceneSpec? { sceneByID[id] }
    public func interaction(_ id: InteractionID) -> InteractionSpec? { interactionByID[id] }
    public func accessibility(_ id: AccessibilityID) -> AccessibilitySpec? {
        accessibilityByID[id]
    }

    public func packageID(for chapterID: ChapterID) -> PackageID? {
        chapterByID[chapterID] == nil ? nil : Self.packageID
    }

    public func contentVersion(for chapterID: ChapterID) -> SchemaVersion? {
        chapterByID[chapterID] == nil ? nil : contentVersion
    }

    public func location(of arcID: ArcID) -> ArcContentLocation? {
        arcLocationByID[arcID]
    }

    public func location(of beatID: BeatID) -> BeatContentLocation? {
        beatLocationByID[beatID]
    }

    public func audioTimelineIDs(for beatID: BeatID) -> [AudioTimelineID]? {
        guard let beat = beatByID[beatID] else { return nil }
        var seen: Set<AudioTimelineID> = []
        var result: [AudioTimelineID] = []
        for cueID in beat.narrationCueIDs {
            guard let timelineID = timelineIDByCueID[cueID] else { return nil }
            if seen.insert(timelineID).inserted { result.append(timelineID) }
        }
        return result
    }

    public func responsiveAudioProgram(
        for interactionID: InteractionID
    ) -> ResponsiveAudioProgramSpec? {
        responsiveProgramByInteractionID[interactionID]
    }

    public func responsiveAudioTimelines(
        for interactionID: InteractionID
    ) -> [AudioTimeline]? {
        guard let program = responsiveProgramByInteractionID[interactionID] else {
            return nil
        }
        let timelineIDs = [program.approachTimelineID]
            + program.interactionBeds.map(\.timelineID)
            + [program.consequenceTimelineID]
        let timelines = timelineIDs.compactMap { timelineByID[$0] }
        return timelines.count == timelineIDs.count ? timelines : nil
    }
}

public enum DevelopmentFirstFarmersEnvelopeError: Error, Equatable, Sendable,
    CustomStringConvertible {
    case missingPayload
    case missingReceipt
    case malformedReceipt
    case nonShippingBoundaryMismatch
    case payloadDigestMismatch
    case payloadIdentityMismatch

    public var description: String {
        switch self {
        case .missingPayload:
            "The DEBUG First Farmers payload is missing"
        case .missingReceipt:
            "The DEBUG First Farmers receipt is missing"
        case .malformedReceipt:
            "The DEBUG First Farmers receipt is malformed"
        case .nonShippingBoundaryMismatch:
            "The DEBUG First Farmers receipt does not prohibit shipping"
        case .payloadDigestMismatch:
            "The DEBUG First Farmers payload no longer matches its receipt"
        case .payloadIdentityMismatch:
            "The DEBUG First Farmers payload identity no longer matches its receipt"
        }
    }
}

public struct DevelopmentFirstFarmersEnvelope: Sendable {
    public let repository: DevelopmentFirstFarmersRepository
    public let resourceRootURL: URL
    public let payloadSHA256: String

    public init(
        repository: DevelopmentFirstFarmersRepository,
        resourceRootURL: URL,
        payloadSHA256: String
    ) {
        self.repository = repository
        self.resourceRootURL = resourceRootURL
        self.payloadSHA256 = payloadSHA256
    }

    public func initialJourneyState() throws -> JourneyState {
        JourneyState(world: try WorldGraph(seed: repository.worldSeed))
    }
}

public enum DevelopmentFirstFarmersEnvelopeLoader {
    private struct Receipt: Decodable {
        let status: String
        let shippingState: String
        let schemaVersion: Int
        let packageID: PackageID
        let payloadSHA256: String
        let claimsExcluded: [String]
    }

    public static func load(
        payloadData: Data?,
        receiptData: Data?,
        resourceRootURL: URL
    ) throws -> DevelopmentFirstFarmersEnvelope {
        guard let payloadData else {
            throw DevelopmentFirstFarmersEnvelopeError.missingPayload
        }
        guard let receiptData else {
            throw DevelopmentFirstFarmersEnvelopeError.missingReceipt
        }
        let receipt: Receipt
        do {
            receipt = try JSONDecoder().decode(Receipt.self, from: receiptData)
        } catch {
            throw DevelopmentFirstFarmersEnvelopeError.malformedReceipt
        }
        let requiredExclusions = Set([
            "shipping approval",
            "content-package activation",
            "finished visual assets",
            "physical-device proof",
        ])
        guard receipt.status == "NON_SHIPPING_DEVELOPMENT_PAYLOAD_PROJECTION",
              receipt.shippingState == "PROHIBITED",
              requiredExclusions.isSubset(of: Set(receipt.claimsExcluded)) else {
            throw DevelopmentFirstFarmersEnvelopeError.nonShippingBoundaryMismatch
        }
        let digest = SHA256.hash(data: payloadData)
            .map { String(format: "%02x", $0) }
            .joined()
        guard digest == receipt.payloadSHA256 else {
            throw DevelopmentFirstFarmersEnvelopeError.payloadDigestMismatch
        }

        let payload: ContentPackagePayload
        do {
            payload = try ContentDocumentDecoder.decodePackage(payloadData)
        } catch {
            throw DevelopmentFirstFarmersRepositoryError.invalidPayload(
                String(describing: error)
            )
        }
        guard receipt.packageID == payload.packageID,
              receipt.packageID == DevelopmentFirstFarmersRepository.packageID,
              receipt.schemaVersion == payload.schemaVersion.major,
              payload.schemaVersion.minor == 0,
              payload.schemaVersion.patch == 0 else {
            throw DevelopmentFirstFarmersEnvelopeError.payloadIdentityMismatch
        }
        return try DevelopmentFirstFarmersEnvelope(
            repository: DevelopmentFirstFarmersRepository(payload: payload),
            resourceRootURL: resourceRootURL.resolvingSymlinksInPath().standardizedFileURL,
            payloadSHA256: digest
        )
    }
}
#endif
