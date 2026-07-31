import ContentKit
import Foundation

public enum ExperienceRuntimeStateError: Error, Equatable, Sendable {
    case unsupportedFormatVersion(Int)
    case emptyIdentifier(String)
    case duplicateMaterialChannel(String)
    case invalidMaterialChannel(String)
    case invalidCameraProgress
    case invalidTransitionProgress
    case invalidAssistanceState
    case negativeSampleCursor
}

/// A deterministic material input that can reproduce an authored material
/// state. Renderer-owned textures, shaders, particles and physics do not
/// belong in the durable snapshot.
public struct StableMaterialChannelState: Codable, Hashable, Sendable {
    public let channelID: String
    public var value: Double

    public init(channelID: String, value: Double) {
        self.channelID = channelID
        self.value = value
    }

    public var isStructurallyValid: Bool {
        !channelID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && value.isFinite
            && (0 ... 1).contains(value)
    }
}

public struct ExperienceCameraState: Codable, Hashable, Sendable {
    public let trackID: String
    public var progress: Double

    public init(trackID: String, progress: Double) {
        self.trackID = trackID
        self.progress = progress
    }

    public var isStructurallyValid: Bool {
        !trackID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && progress.isFinite
            && (0 ... 1).contains(progress)
    }
}

public struct ExperienceTransitionState: Codable, Hashable, Sendable {
    public let transitionID: String
    public let carrierID: String
    public var progress: Double

    public init(transitionID: String, carrierID: String, progress: Double) {
        self.transitionID = transitionID
        self.carrierID = carrierID
        self.progress = progress
    }

    public var isStructurallyValid: Bool {
        !transitionID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !carrierID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && progress.isFinite
            && (0 ... 1).contains(progress)
    }
}

/// Binds the 3D projection to the authoritative `InteractionRuntimeState`
/// stored by the Journey journal without copying reducer state into rendering
/// persistence.
public struct ExperienceInteractionStateReference: Codable, Hashable, Sendable {
    public let interactionID: InteractionID

    public init(interactionID: InteractionID) {
        self.interactionID = interactionID
    }

    public var isStructurallyValid: Bool {
        !interactionID.rawValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

/// Stable inputs from which an immersive scene can be reconstructed exactly.
///
/// RealityKit entities, transforms derived from authored tracks, particles and
/// raw physics are deliberately absent. They are projections of this state,
/// content data and the deterministic tick/seed pair.
public struct ExperienceRuntimeState: Codable, Hashable, Sendable {
    public static let currentFormatVersion = 1

    public let formatVersion: Int
    public var worldCellID: String
    public var sequenceID: String
    public var beatID: BeatID
    public var materialChannels: [StableMaterialChannelState]
    public var deterministicTick: UInt64
    public let deterministicSeed: UInt64
    public var camera: ExperienceCameraState
    public var transition: ExperienceTransitionState?
    public var assistance: AdaptiveAssistanceState
    public var interactionStateReference: ExperienceInteractionStateReference?
    public var sampleCursor: Int64

    public init(
        formatVersion: Int = Self.currentFormatVersion,
        worldCellID: String,
        sequenceID: String,
        beatID: BeatID,
        materialChannels: [StableMaterialChannelState] = [],
        deterministicTick: UInt64,
        deterministicSeed: UInt64,
        camera: ExperienceCameraState,
        transition: ExperienceTransitionState? = nil,
        assistance: AdaptiveAssistanceState = AdaptiveAssistanceState(),
        interactionStateReference: ExperienceInteractionStateReference? = nil,
        sampleCursor: Int64 = 0
    ) throws {
        self.formatVersion = formatVersion
        self.worldCellID = worldCellID
        self.sequenceID = sequenceID
        self.beatID = beatID
        self.materialChannels = materialChannels.sorted {
            $0.channelID < $1.channelID
        }
        self.deterministicTick = deterministicTick
        self.deterministicSeed = deterministicSeed
        self.camera = camera
        self.transition = transition
        self.assistance = assistance
        self.interactionStateReference = interactionStateReference
        self.sampleCursor = sampleCursor
        try validate()
    }

    public var isStructurallyValid: Bool {
        (try? validate()) != nil
    }

    public func materialValue(for channelID: String) -> Double? {
        materialChannels.first { $0.channelID == channelID }?.value
    }

    public func validate() throws {
        guard formatVersion == Self.currentFormatVersion else {
            throw ExperienceRuntimeStateError.unsupportedFormatVersion(formatVersion)
        }
        guard !worldCellID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ExperienceRuntimeStateError.emptyIdentifier("worldCellID")
        }
        guard !sequenceID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ExperienceRuntimeStateError.emptyIdentifier("sequenceID")
        }
        guard !beatID.rawValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ExperienceRuntimeStateError.emptyIdentifier("beatID")
        }
        guard materialChannels == materialChannels.sorted(by: {
            $0.channelID < $1.channelID
        }) else {
            throw ExperienceRuntimeStateError.invalidMaterialChannel(
                "materialChannels must use canonical identifier order"
            )
        }
        var channelIDs = Set<String>()
        for channel in materialChannels {
            guard channel.isStructurallyValid else {
                throw ExperienceRuntimeStateError.invalidMaterialChannel(channel.channelID)
            }
            guard channelIDs.insert(channel.channelID).inserted else {
                throw ExperienceRuntimeStateError.duplicateMaterialChannel(channel.channelID)
            }
        }
        guard camera.isStructurallyValid else {
            if camera.trackID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                throw ExperienceRuntimeStateError.emptyIdentifier("camera.trackID")
            }
            throw ExperienceRuntimeStateError.invalidCameraProgress
        }
        if let transition {
            guard transition.isStructurallyValid else {
                if transition.transitionID
                    .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    throw ExperienceRuntimeStateError.emptyIdentifier(
                        "transition.transitionID"
                    )
                }
                if transition.carrierID
                    .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    throw ExperienceRuntimeStateError.emptyIdentifier(
                        "transition.carrierID"
                    )
                }
                throw ExperienceRuntimeStateError.invalidTransitionProgress
            }
        }
        guard assistance.isStructurallyValid else {
            throw ExperienceRuntimeStateError.invalidAssistanceState
        }
        if let interactionStateReference,
           !interactionStateReference.isStructurallyValid {
            throw ExperienceRuntimeStateError.emptyIdentifier(
                "interactionStateReference.interactionID"
            )
        }
        guard sampleCursor >= 0 else {
            throw ExperienceRuntimeStateError.negativeSampleCursor
        }
    }

    private enum CodingKeys: String, CodingKey {
        case formatVersion
        case worldCellID
        case sequenceID
        case beatID
        case materialChannels
        case deterministicTick
        case deterministicSeed
        case camera
        case transition
        case assistance
        case interactionStateReference
        case sampleCursor
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedVersion = try container.decode(Int.self, forKey: .formatVersion)
        guard decodedVersion == Self.currentFormatVersion else {
            throw DecodingError.dataCorruptedError(
                forKey: .formatVersion,
                in: container,
                debugDescription: "Unsupported ExperienceRuntimeState format version"
            )
        }
        do {
            try self.init(
                formatVersion: decodedVersion,
                worldCellID: try container.decode(String.self, forKey: .worldCellID),
                sequenceID: try container.decode(String.self, forKey: .sequenceID),
                beatID: try container.decode(BeatID.self, forKey: .beatID),
                materialChannels: try container.decode(
                    [StableMaterialChannelState].self,
                    forKey: .materialChannels
                ),
                deterministicTick: try container.decode(
                    UInt64.self,
                    forKey: .deterministicTick
                ),
                deterministicSeed: try container.decode(
                    UInt64.self,
                    forKey: .deterministicSeed
                ),
                camera: try container.decode(
                    ExperienceCameraState.self,
                    forKey: .camera
                ),
                transition: try container.decodeIfPresent(
                    ExperienceTransitionState.self,
                    forKey: .transition
                ),
                assistance: try container.decode(
                    AdaptiveAssistanceState.self,
                    forKey: .assistance
                ),
                interactionStateReference: try container.decodeIfPresent(
                    ExperienceInteractionStateReference.self,
                    forKey: .interactionStateReference
                ),
                sampleCursor: try container.decode(Int64.self, forKey: .sampleCursor)
            )
        } catch let error as DecodingError {
            throw error
        } catch {
            throw DecodingError.dataCorruptedError(
                forKey: .formatVersion,
                in: container,
                debugDescription: "ExperienceRuntimeState failed structural validation: \(error)"
            )
        }
    }
}
