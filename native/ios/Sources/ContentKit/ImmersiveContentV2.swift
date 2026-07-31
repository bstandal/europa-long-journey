import Foundation

// MARK: - Stable immersive identifiers

public enum WorldCell3DIDDomain: Sendable {}
public enum ExperienceSequenceIDDomain: Sendable {}
public enum ExperienceBeatIDDomain: Sendable {}
public enum WorldEntity3DIDDomain: Sendable {}
public enum MaterialBinding3DIDDomain: Sendable {}
public enum MaterialState3DIDDomain: Sendable {}
public enum AnimationBinding3DIDDomain: Sendable {}
public enum AnimationState3DIDDomain: Sendable {}
public enum TransitionCarrier3DIDDomain: Sendable {}
public enum CameraTrack3DIDDomain: Sendable {}
public enum CameraAnchor3DIDDomain: Sendable {}
public enum AssetReference3DIDDomain: Sendable {}
public enum LODGroup3DIDDomain: Sendable {}
public enum SemanticAction3DIDDomain: Sendable {}
public enum AudioBinding3DIDDomain: Sendable {}
public enum CaptionBinding3DIDDomain: Sendable {}

public typealias WorldCell3DID = StableID<WorldCell3DIDDomain>
public typealias ExperienceSequenceID = StableID<ExperienceSequenceIDDomain>
public typealias ExperienceBeatID = StableID<ExperienceBeatIDDomain>
public typealias WorldEntity3DID = StableID<WorldEntity3DIDDomain>
public typealias MaterialBinding3DID = StableID<MaterialBinding3DIDDomain>
public typealias MaterialState3DID = StableID<MaterialState3DIDDomain>
public typealias AnimationBinding3DID = StableID<AnimationBinding3DIDDomain>
public typealias AnimationState3DID = StableID<AnimationState3DIDDomain>
public typealias TransitionCarrier3DID = StableID<TransitionCarrier3DIDDomain>
public typealias CameraTrack3DID = StableID<CameraTrack3DIDDomain>
public typealias CameraAnchor3DID = StableID<CameraAnchor3DIDDomain>
public typealias AssetReference3DID = StableID<AssetReference3DIDDomain>
public typealias LODGroup3DID = StableID<LODGroup3DIDDomain>
public typealias SemanticAction3DID = StableID<SemanticAction3DIDDomain>
public typealias AudioBinding3DID = StableID<AudioBinding3DIDDomain>
public typealias CaptionBinding3DID = StableID<CaptionBinding3DIDDomain>

// MARK: - Package assets

public enum ImmersiveAssetKind: String, Codable, Hashable, Sendable {
    case sceneGraph = "scene-graph"
    case mesh
    case material
    case animation
    case audio
}

public struct AssetReference3DSpec: Codable, Hashable, Sendable, Identifiable {
    public let id: AssetReference3DID
    public let kind: ImmersiveAssetKind
    public let path: String
    public let sha256: String
    public let byteCount: Int64

    public init(
        id: AssetReference3DID,
        kind: ImmersiveAssetKind,
        path: String,
        sha256: String,
        byteCount: Int64
    ) {
        self.id = id
        self.kind = kind
        self.path = path
        self.sha256 = sha256
        self.byteCount = byteCount
    }

    public func validate(field: String) throws {
        try requireNonempty(id, field: "\(field).id")
        try requireSafePackageAssetPath(path)
        guard byteCount > 0 else {
            throw ContentValidationError.invalidValue(
                field: "\(field).byteCount",
                reason: "must be positive"
            )
        }
        guard Self.isLowercaseSHA256(sha256) else {
            throw ContentValidationError.invalidValue(
                field: "\(field).sha256",
                reason: "must be 64 lowercase hexadecimal characters"
            )
        }
    }

    private static func isLowercaseSHA256(_ value: String) -> Bool {
        value.utf8.count == 64 && value.utf8.allSatisfy { byte in
            (byte >= 48 && byte <= 57) || (byte >= 97 && byte <= 102)
        }
    }
}

// MARK: - Camera authorship

public struct Vector3DSpec: Codable, Hashable, Sendable {
    public let x: Double
    public let y: Double
    public let z: Double

    public init(x: Double, y: Double, z: Double) {
        self.x = x
        self.y = y
        self.z = z
    }

    fileprivate var isFinite: Bool { x.isFinite && y.isFinite && z.isFinite }
}

public struct CameraPose3DSpec: Codable, Hashable, Sendable {
    public let position: Vector3DSpec
    public let pitchDegrees: Double
    public let yawDegrees: Double
    public let rollDegrees: Double
    public let verticalFieldOfViewDegrees: Double

    public init(
        position: Vector3DSpec,
        pitchDegrees: Double,
        yawDegrees: Double,
        rollDegrees: Double,
        verticalFieldOfViewDegrees: Double
    ) {
        self.position = position
        self.pitchDegrees = pitchDegrees
        self.yawDegrees = yawDegrees
        self.rollDegrees = rollDegrees
        self.verticalFieldOfViewDegrees = verticalFieldOfViewDegrees
    }

    fileprivate func validate(field: String) throws {
        guard position.isFinite,
              pitchDegrees.isFinite,
              yawDegrees.isFinite,
              rollDegrees.isFinite,
              verticalFieldOfViewDegrees.isFinite,
              (-90 ... 90).contains(pitchDegrees),
              (20 ... 90).contains(verticalFieldOfViewDegrees) else {
            throw ContentValidationError.invalidValue(
                field: field,
                reason: "requires finite transforms, a valid pitch and a 20–90 degree portrait field of view"
            )
        }
    }
}

public struct PortraitSafeRegion3DSpec: Codable, Hashable, Sendable {
    public let minimumX: Double
    public let minimumY: Double
    public let maximumX: Double
    public let maximumY: Double

    public init(minimumX: Double, minimumY: Double, maximumX: Double, maximumY: Double) {
        self.minimumX = minimumX
        self.minimumY = minimumY
        self.maximumX = maximumX
        self.maximumY = maximumY
    }

    fileprivate func validate(field: String) throws {
        guard minimumX.isFinite,
              minimumY.isFinite,
              maximumX.isFinite,
              maximumY.isFinite,
              (0 ... 1).contains(minimumX),
              (0 ... 1).contains(minimumY),
              (0 ... 1).contains(maximumX),
              (0 ... 1).contains(maximumY),
              minimumX < maximumX,
              minimumY < maximumY else {
            throw ContentValidationError.invalidValue(
                field: field,
                reason: "must be a non-empty normalized portrait rectangle"
            )
        }
    }
}

public struct CameraAnchor3DSpec: Codable, Hashable, Sendable, Identifiable {
    public let id: CameraAnchor3DID
    public let pose: CameraPose3DSpec
    public let portraitSafeRegion: PortraitSafeRegion3DSpec
    public let focusEntityID: WorldEntity3DID?

    public init(
        id: CameraAnchor3DID,
        pose: CameraPose3DSpec,
        portraitSafeRegion: PortraitSafeRegion3DSpec,
        focusEntityID: WorldEntity3DID? = nil
    ) {
        self.id = id
        self.pose = pose
        self.portraitSafeRegion = portraitSafeRegion
        self.focusEntityID = focusEntityID
    }

    fileprivate func validate(field: String) throws {
        try requireNonempty(id, field: "\(field).id")
        try pose.validate(field: "\(field).pose")
        try portraitSafeRegion.validate(field: "\(field).portraitSafeRegion")
        if let focusEntityID {
            try requireNonempty(focusEntityID, field: "\(field).focusEntityID")
        }
    }
}

public enum ReduceMotionCameraTransition: String, Codable, Hashable, Sendable {
    case cut
    case shortEase = "short-ease"
}

public struct ReduceMotionCameraTrackSpec: Codable, Hashable, Sendable {
    public let anchors: [CameraAnchor3DSpec]
    public let transition: ReduceMotionCameraTransition
    public let maximumTransitionSeconds: Double

    public init(
        anchors: [CameraAnchor3DSpec],
        transition: ReduceMotionCameraTransition,
        maximumTransitionSeconds: Double
    ) {
        self.anchors = anchors
        self.transition = transition
        self.maximumTransitionSeconds = maximumTransitionSeconds
    }

    fileprivate func validate(field: String) throws {
        guard !anchors.isEmpty,
              maximumTransitionSeconds.isFinite,
              (0 ... 0.35).contains(maximumTransitionSeconds) else {
            throw ContentValidationError.invalidValue(
                field: field,
                reason: "requires fixed anchors and a transition no longer than 0.35 seconds"
            )
        }
        try requireUnique(anchors.map(\.id))
        for (index, anchor) in anchors.enumerated() {
            try anchor.validate(field: "\(field).anchors[\(index)]")
        }
    }
}

public struct CameraTrackSpec: Codable, Hashable, Sendable, Identifiable {
    public let id: CameraTrack3DID
    public let anchors: [CameraAnchor3DSpec]
    public let authoredDurationSeconds: Double
    public let maximumUnbrokenTravelSeconds: Double
    public let reduceMotion: ReduceMotionCameraTrackSpec

    public init(
        id: CameraTrack3DID,
        anchors: [CameraAnchor3DSpec],
        authoredDurationSeconds: Double,
        maximumUnbrokenTravelSeconds: Double,
        reduceMotion: ReduceMotionCameraTrackSpec
    ) {
        self.id = id
        self.anchors = anchors
        self.authoredDurationSeconds = authoredDurationSeconds
        self.maximumUnbrokenTravelSeconds = maximumUnbrokenTravelSeconds
        self.reduceMotion = reduceMotion
    }

    fileprivate func validate(field: String) throws {
        try requireNonempty(id, field: "\(field).id")
        guard !anchors.isEmpty,
              authoredDurationSeconds.isFinite,
              authoredDurationSeconds > 0,
              maximumUnbrokenTravelSeconds.isFinite,
              maximumUnbrokenTravelSeconds > 0,
              maximumUnbrokenTravelSeconds <= 8 else {
            throw ContentValidationError.invalidValue(
                field: field,
                reason: "requires authored anchors, positive duration and no more than eight seconds of unbroken travel"
            )
        }
        try requireUnique(anchors.map(\.id))
        for (index, anchor) in anchors.enumerated() {
            try anchor.validate(field: "\(field).anchors[\(index)]")
        }
        try reduceMotion.validate(field: "\(field).reduceMotion")
    }
}

// MARK: - Entity, material and animation state

public enum WorldEntity3DRole: String, Codable, Hashable, Sendable {
    case terrain
    case architecture
    case person
    case animal
    case actionObject = "action-object"
    case persistentTrace = "persistent-trace"
    case atmosphere
}

public struct MaterialState3DSpec: Codable, Hashable, Sendable, Identifiable {
    public let id: MaterialState3DID
    public let assetID: AssetReference3DID

    public init(id: MaterialState3DID, assetID: AssetReference3DID) {
        self.id = id
        self.assetID = assetID
    }
}

public struct MaterialBinding3DSpec: Codable, Hashable, Sendable, Identifiable {
    public let id: MaterialBinding3DID
    public let entityID: WorldEntity3DID
    public let reducerStateKey: String
    public let initialStateID: MaterialState3DID
    public let states: [MaterialState3DSpec]

    public init(
        id: MaterialBinding3DID,
        entityID: WorldEntity3DID,
        reducerStateKey: String,
        initialStateID: MaterialState3DID,
        states: [MaterialState3DSpec]
    ) {
        self.id = id
        self.entityID = entityID
        self.reducerStateKey = reducerStateKey
        self.initialStateID = initialStateID
        self.states = states
    }

    fileprivate func validate(field: String) throws {
        try requireNonempty(id, field: "\(field).id")
        try requireNonempty(entityID, field: "\(field).entityID")
        try requireStableKey(reducerStateKey, field: "\(field).reducerStateKey")
        try requireNonempty(initialStateID, field: "\(field).initialStateID")
        guard !states.isEmpty else {
            throw ContentValidationError.invalidValue(
                field: "\(field).states",
                reason: "at least one deterministic material state is required"
            )
        }
        try requireUnique(states.map(\.id))
        guard states.contains(where: { $0.id == initialStateID }) else {
            throw ContentValidationError.missingReference(
                field: "\(field).initialStateID",
                identifier: initialStateID.rawValue
            )
        }
        for state in states {
            try requireNonempty(state.id, field: "\(field).states.id")
            try requireNonempty(state.assetID, field: "\(field).states.assetID")
        }
    }
}

public struct AnimationState3DSpec: Codable, Hashable, Sendable, Identifiable {
    public let id: AnimationState3DID
    public let assetID: AssetReference3DID
    public let loops: Bool

    public init(id: AnimationState3DID, assetID: AssetReference3DID, loops: Bool) {
        self.id = id
        self.assetID = assetID
        self.loops = loops
    }
}

public struct AnimationBinding3DSpec: Codable, Hashable, Sendable, Identifiable {
    public let id: AnimationBinding3DID
    public let entityID: WorldEntity3DID
    public let reducerStateKey: String
    public let initialStateID: AnimationState3DID
    public let states: [AnimationState3DSpec]

    public init(
        id: AnimationBinding3DID,
        entityID: WorldEntity3DID,
        reducerStateKey: String,
        initialStateID: AnimationState3DID,
        states: [AnimationState3DSpec]
    ) {
        self.id = id
        self.entityID = entityID
        self.reducerStateKey = reducerStateKey
        self.initialStateID = initialStateID
        self.states = states
    }

    fileprivate func validate(field: String) throws {
        try requireNonempty(id, field: "\(field).id")
        try requireNonempty(entityID, field: "\(field).entityID")
        try requireStableKey(reducerStateKey, field: "\(field).reducerStateKey")
        try requireNonempty(initialStateID, field: "\(field).initialStateID")
        guard !states.isEmpty else {
            throw ContentValidationError.invalidValue(
                field: "\(field).states",
                reason: "at least one deterministic animation state is required"
            )
        }
        try requireUnique(states.map(\.id))
        guard states.contains(where: { $0.id == initialStateID }) else {
            throw ContentValidationError.missingReference(
                field: "\(field).initialStateID",
                identifier: initialStateID.rawValue
            )
        }
        for state in states {
            try requireNonempty(state.id, field: "\(field).states.id")
            try requireNonempty(state.assetID, field: "\(field).states.assetID")
        }
    }
}

public struct WorldEntity3DBindingSpec: Codable, Hashable, Sendable, Identifiable {
    public let id: WorldEntity3DID
    public let scenePath: String
    public let role: WorldEntity3DRole
    public let reducerStateKey: String
    public let persistsAfterSequence: Bool
    public let materialBindingIDs: [MaterialBinding3DID]
    public let animationBindingIDs: [AnimationBinding3DID]
    public let semanticActionIDs: [SemanticAction3DID]

    public init(
        id: WorldEntity3DID,
        scenePath: String,
        role: WorldEntity3DRole,
        reducerStateKey: String,
        persistsAfterSequence: Bool,
        materialBindingIDs: [MaterialBinding3DID],
        animationBindingIDs: [AnimationBinding3DID],
        semanticActionIDs: [SemanticAction3DID]
    ) {
        self.id = id
        self.scenePath = scenePath
        self.role = role
        self.reducerStateKey = reducerStateKey
        self.persistsAfterSequence = persistsAfterSequence
        self.materialBindingIDs = materialBindingIDs
        self.animationBindingIDs = animationBindingIDs
        self.semanticActionIDs = semanticActionIDs
    }

    fileprivate func validate(field: String) throws {
        try requireNonempty(id, field: "\(field).id")
        try requireStableKey(reducerStateKey, field: "\(field).reducerStateKey")
        let parts = scenePath.split(separator: "/", omittingEmptySubsequences: false)
        guard !scenePath.isEmpty,
              !scenePath.hasPrefix("/"),
              !scenePath.contains("\\"),
              !scenePath.contains("://"),
              parts.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
            throw ContentValidationError.invalidValue(
                field: "\(field).scenePath",
                reason: "must be a safe scene-root-relative entity path"
            )
        }
        try requireUnique(materialBindingIDs)
        try requireUnique(animationBindingIDs)
        try requireUnique(semanticActionIDs)
    }
}

// MARK: - Direct touch and accessible action parity

public enum DirectManipulationGesture3D: String, Codable, Hashable, Sendable {
    case tap
    case grip
    case drag
    case hold
    case transfer
    case seal
    case step
}

public enum SemanticInputModality3D: String, Codable, Hashable, Sendable {
    case directTouch = "direct-touch"
    case voiceOver = "voice-over"
}

public struct AccessibleSemanticAction3DSpec: Codable, Hashable, Sendable, Identifiable {
    public let id: SemanticAction3DID
    public let interactionID: InteractionID
    public let targetEntityID: WorldEntity3DID
    public let domainActionKey: String
    public let accessibilityLabel: LocalizedStringSpec
    public let visibleFallbackCue: LocalizedStringSpec?
    public let directGesture: DirectManipulationGesture3D
    public let inputModalities: [SemanticInputModality3D]
    public let minimumTouchTargetPoints: Double
    public let reduceMotionUsesSameDomainAction: Bool

    public init(
        id: SemanticAction3DID,
        interactionID: InteractionID,
        targetEntityID: WorldEntity3DID,
        domainActionKey: String,
        accessibilityLabel: LocalizedStringSpec,
        visibleFallbackCue: LocalizedStringSpec? = nil,
        directGesture: DirectManipulationGesture3D,
        inputModalities: [SemanticInputModality3D],
        minimumTouchTargetPoints: Double,
        reduceMotionUsesSameDomainAction: Bool
    ) {
        self.id = id
        self.interactionID = interactionID
        self.targetEntityID = targetEntityID
        self.domainActionKey = domainActionKey
        self.accessibilityLabel = accessibilityLabel
        self.visibleFallbackCue = visibleFallbackCue
        self.directGesture = directGesture
        self.inputModalities = inputModalities
        self.minimumTouchTargetPoints = minimumTouchTargetPoints
        self.reduceMotionUsesSameDomainAction = reduceMotionUsesSameDomainAction
    }

    fileprivate func validate(field: String) throws {
        try requireNonempty(id, field: "\(field).id")
        try requireNonempty(interactionID, field: "\(field).interactionID")
        try requireNonempty(targetEntityID, field: "\(field).targetEntityID")
        try requireStableKey(domainActionKey, field: "\(field).domainActionKey")
        try accessibilityLabel.validate(field: "\(field).accessibilityLabel")
        if let visibleFallbackCue {
            try visibleFallbackCue.validate(field: "\(field).visibleFallbackCue")
            let words = visibleFallbackCue.launchEnglish.wordCount
            guard (1 ... 4).contains(words) else {
                throw ContentValidationError.invalidValue(
                    field: "\(field).visibleFallbackCue",
                    reason: "fallback action language must contain one to four words"
                )
            }
        }
        guard minimumTouchTargetPoints.isFinite,
              minimumTouchTargetPoints >= 44,
              Set(inputModalities) == [.directTouch, .voiceOver],
              inputModalities.count == 2,
              reduceMotionUsesSameDomainAction else {
            throw ContentValidationError.invalidValue(
                field: field,
                reason: "direct touch, VoiceOver, a 44-point target and the same Reduce Motion domain action are required"
            )
        }
    }
}

// MARK: - LOD and streaming

public struct LODLevel3DSpec: Codable, Hashable, Sendable {
    public let maximumDistanceMeters: Double
    public let assetID: AssetReference3DID

    public init(maximumDistanceMeters: Double, assetID: AssetReference3DID) {
        self.maximumDistanceMeters = maximumDistanceMeters
        self.assetID = assetID
    }
}

public struct LODGroup3DSpec: Codable, Hashable, Sendable, Identifiable {
    public let id: LODGroup3DID
    public let entityID: WorldEntity3DID
    public let levels: [LODLevel3DSpec]

    public init(id: LODGroup3DID, entityID: WorldEntity3DID, levels: [LODLevel3DSpec]) {
        self.id = id
        self.entityID = entityID
        self.levels = levels
    }

    fileprivate func validate(field: String) throws {
        try requireNonempty(id, field: "\(field).id")
        try requireNonempty(entityID, field: "\(field).entityID")
        guard !levels.isEmpty else {
            throw ContentValidationError.invalidValue(
                field: "\(field).levels",
                reason: "at least one authored LOD is required"
            )
        }
        var previous = 0.0
        for (index, level) in levels.enumerated() {
            guard level.maximumDistanceMeters.isFinite,
                  level.maximumDistanceMeters > previous else {
                throw ContentValidationError.invalidValue(
                    field: "\(field).levels[\(index)].maximumDistanceMeters",
                    reason: "LOD distances must be finite, positive and strictly increasing"
                )
            }
            try requireNonempty(level.assetID, field: "\(field).levels[\(index)].assetID")
            previous = level.maximumDistanceMeters
        }
    }
}

public enum StreamingUnloadRule3D: String, Codable, Hashable, Sendable {
    case afterTransitionCommit = "after-transition-commit"
}

public struct ImmersiveStreamingPolicySpec: Codable, Hashable, Sendable {
    public let maximumResidentCellCount: Int
    public let prefetchLeadSeconds: Double
    public let unloadRule: StreamingUnloadRule3D
    public let permitsPlaceholderUI: Bool

    public init(
        maximumResidentCellCount: Int,
        prefetchLeadSeconds: Double,
        unloadRule: StreamingUnloadRule3D,
        permitsPlaceholderUI: Bool
    ) {
        self.maximumResidentCellCount = maximumResidentCellCount
        self.prefetchLeadSeconds = prefetchLeadSeconds
        self.unloadRule = unloadRule
        self.permitsPlaceholderUI = permitsPlaceholderUI
    }

    fileprivate func validate() throws {
        guard maximumResidentCellCount == 2,
              prefetchLeadSeconds.isFinite,
              (0 ... 8).contains(prefetchLeadSeconds),
              unloadRule == .afterTransitionCommit,
              !permitsPlaceholderUI else {
            throw ContentValidationError.invalidValue(
                field: "contentPackageV2.streamingPolicy",
                reason: "only current-and-next streaming without placeholder UI is permitted"
            )
        }
    }
}

// MARK: - Audio, narration and captions

public enum ImmersiveAudioRole: String, Codable, Hashable, Sendable {
    case environment
    case material
    case mechanism
    case transition
    case score
    case narration
}

public struct ImmersiveAudioBindingSpec: Codable, Hashable, Sendable, Identifiable {
    public let id: AudioBinding3DID
    public let assetID: AssetReference3DID
    public let role: ImmersiveAudioRole
    public let cellID: WorldCell3DID?
    public let sequenceID: ExperienceSequenceID?
    public let interactionID: InteractionID?
    public let startSampleFrame: UInt64
    public let durationSampleFrames: UInt64
    public let sampleRate: Int
    public let loops: Bool

    public init(
        id: AudioBinding3DID,
        assetID: AssetReference3DID,
        role: ImmersiveAudioRole,
        cellID: WorldCell3DID? = nil,
        sequenceID: ExperienceSequenceID? = nil,
        interactionID: InteractionID? = nil,
        startSampleFrame: UInt64,
        durationSampleFrames: UInt64,
        sampleRate: Int,
        loops: Bool
    ) {
        self.id = id
        self.assetID = assetID
        self.role = role
        self.cellID = cellID
        self.sequenceID = sequenceID
        self.interactionID = interactionID
        self.startSampleFrame = startSampleFrame
        self.durationSampleFrames = durationSampleFrames
        self.sampleRate = sampleRate
        self.loops = loops
    }

    fileprivate var durationSeconds: Double {
        Double(durationSampleFrames) / Double(sampleRate)
    }

    fileprivate func validate(field: String) throws {
        try requireNonempty(id, field: "\(field).id")
        try requireNonempty(assetID, field: "\(field).assetID")
        if let cellID { try requireNonempty(cellID, field: "\(field).cellID") }
        if let sequenceID { try requireNonempty(sequenceID, field: "\(field).sequenceID") }
        if let interactionID { try requireNonempty(interactionID, field: "\(field).interactionID") }
        guard sampleRate == 48_000, durationSampleFrames > 0 else {
            throw ContentValidationError.invalidValue(
                field: field,
                reason: "48 kHz audio with positive sample duration is required"
            )
        }
        switch role {
        case .environment:
            guard cellID != nil, interactionID == nil else {
                throw ContentValidationError.invalidValue(
                    field: field,
                    reason: "environment audio must bind one world cell"
                )
            }
        case .mechanism:
            guard sequenceID != nil, interactionID != nil else {
                throw ContentValidationError.invalidValue(
                    field: field,
                    reason: "mechanism audio must bind one sequence and interaction"
                )
            }
        case .transition:
            guard sequenceID != nil else {
                throw ContentValidationError.invalidValue(
                    field: field,
                    reason: "transition audio must bind its destination sequence"
                )
            }
        case .narration:
            guard sequenceID != nil,
                  interactionID == nil,
                  !loops,
                  durationSeconds <= 15 else {
                throw ContentValidationError.invalidValue(
                    field: field,
                    reason: "narration must bind one sequence, never loop and last no more than 15 seconds"
                )
            }
        case .material, .score:
            guard cellID != nil || sequenceID != nil else {
                throw ContentValidationError.invalidValue(
                    field: field,
                    reason: "material and score audio require a cell or sequence scope"
                )
            }
        }
    }
}

public struct CaptionBinding3DSpec: Codable, Hashable, Sendable, Identifiable {
    public let id: CaptionBinding3DID
    public let narrationCueID: AudioCueID
    public let text: LocalizedStringSpec
    public let startSampleFrame: UInt64
    public let endSampleFrame: UInt64
    public let maximumLineCount: Int

    public init(
        id: CaptionBinding3DID,
        narrationCueID: AudioCueID,
        text: LocalizedStringSpec,
        startSampleFrame: UInt64,
        endSampleFrame: UInt64,
        maximumLineCount: Int
    ) {
        self.id = id
        self.narrationCueID = narrationCueID
        self.text = text
        self.startSampleFrame = startSampleFrame
        self.endSampleFrame = endSampleFrame
        self.maximumLineCount = maximumLineCount
    }

    fileprivate func validate(field: String) throws {
        try requireNonempty(id, field: "\(field).id")
        try requireNonempty(narrationCueID, field: "\(field).narrationCueID")
        try text.validate(field: "\(field).text")
        guard startSampleFrame < endSampleFrame,
              (1 ... 2).contains(maximumLineCount) else {
            throw ContentValidationError.invalidValue(
                field: field,
                reason: "caption timing must be positive and fit one or two authored lines"
            )
        }
    }
}

public struct NarrationBinding3DSpec: Codable, Hashable, Sendable, Identifiable {
    public let id: AudioCueID
    public let sequenceID: ExperienceSequenceID
    public let audioBindingID: AudioBinding3DID
    public let text: LocalizedStringSpec
    public let captionIDs: [CaptionBinding3DID]
    public let beginsAfterPreciseInputRelease: Bool

    public init(
        id: AudioCueID,
        sequenceID: ExperienceSequenceID,
        audioBindingID: AudioBinding3DID,
        text: LocalizedStringSpec,
        captionIDs: [CaptionBinding3DID],
        beginsAfterPreciseInputRelease: Bool
    ) {
        self.id = id
        self.sequenceID = sequenceID
        self.audioBindingID = audioBindingID
        self.text = text
        self.captionIDs = captionIDs
        self.beginsAfterPreciseInputRelease = beginsAfterPreciseInputRelease
    }

    fileprivate func validate(field: String) throws {
        try requireNonempty(id, field: "\(field).id")
        try requireNonempty(sequenceID, field: "\(field).sequenceID")
        try requireNonempty(audioBindingID, field: "\(field).audioBindingID")
        try text.validate(field: "\(field).text")
        guard !captionIDs.isEmpty else {
            throw ContentValidationError.invalidValue(
                field: "\(field).captionIDs",
                reason: "every narration cue requires timed captions"
            )
        }
        try requireUnique(captionIDs)
    }
}

// MARK: - Chapter flow

public enum ImmersiveInteractionGrammar: String, Codable, Hashable, Sendable {
    case trace
    case allocate
    case assemble
    case pressure
    case transform
}

public enum PersistentEffectAuthorityV2: String, Codable, Hashable, Sendable {
    case externalWorldEffects = "external-world-effects"
}

public struct PrincipalInteraction3DBindingSpec: Codable, Hashable, Sendable {
    public let interactionID: InteractionID
    public let grammar: ImmersiveInteractionGrammar
    public let effectAuthority: PersistentEffectAuthorityV2

    public init(
        interactionID: InteractionID,
        grammar: ImmersiveInteractionGrammar,
        effectAuthority: PersistentEffectAuthorityV2 = .externalWorldEffects
    ) {
        self.interactionID = interactionID
        self.grammar = grammar
        self.effectAuthority = effectAuthority
    }

    fileprivate func validate(field: String) throws {
        try requireNonempty(interactionID, field: "\(field).interactionID")
        guard effectAuthority == .externalWorldEffects else {
            throw ContentValidationError.invalidValue(
                field: "\(field).effectAuthority",
                reason: "persistent effects remain under the existing external world-effect authority"
            )
        }
    }
}

public struct ExperienceBeat3DSpec: Codable, Hashable, Sendable, Identifiable {
    public let id: ExperienceBeatID
    public let cellID: WorldCell3DID
    public let authoredDurationSeconds: Double
    public let maximumPassiveSeconds: Double
    public let cameraTrackID: CameraTrack3DID
    public let semanticActionIDs: [SemanticAction3DID]
    public let narrationCueIDs: [AudioCueID]
    public let endsAtStableRestorationState: Bool

    public init(
        id: ExperienceBeatID,
        cellID: WorldCell3DID,
        authoredDurationSeconds: Double,
        maximumPassiveSeconds: Double,
        cameraTrackID: CameraTrack3DID,
        semanticActionIDs: [SemanticAction3DID],
        narrationCueIDs: [AudioCueID],
        endsAtStableRestorationState: Bool
    ) {
        self.id = id
        self.cellID = cellID
        self.authoredDurationSeconds = authoredDurationSeconds
        self.maximumPassiveSeconds = maximumPassiveSeconds
        self.cameraTrackID = cameraTrackID
        self.semanticActionIDs = semanticActionIDs
        self.narrationCueIDs = narrationCueIDs
        self.endsAtStableRestorationState = endsAtStableRestorationState
    }

    fileprivate func validate(field: String) throws {
        try requireNonempty(id, field: "\(field).id")
        try requireNonempty(cellID, field: "\(field).cellID")
        try requireNonempty(cameraTrackID, field: "\(field).cameraTrackID")
        try requireUnique(semanticActionIDs)
        try requireUnique(narrationCueIDs)
        guard authoredDurationSeconds.isFinite,
              authoredDurationSeconds > 0,
              maximumPassiveSeconds.isFinite,
              maximumPassiveSeconds >= 0,
              maximumPassiveSeconds <= 8 else {
            throw ContentValidationError.invalidValue(
                field: field,
                reason: "beats require positive authored time and no more than eight passive seconds"
            )
        }
    }
}

public struct ExperienceSequenceSpec: Codable, Hashable, Sendable, Identifiable {
    public let id: ExperienceSequenceID
    public let locationCue: LocalizedStringSpec?
    public let worldCellIDs: [WorldCell3DID]
    public let authoredDurationSeconds: Double
    public let principalInteraction: PrincipalInteraction3DBindingSpec
    public let beats: [ExperienceBeat3DSpec]
    public let narrationCueIDs: [AudioCueID]

    public init(
        id: ExperienceSequenceID,
        locationCue: LocalizedStringSpec? = nil,
        worldCellIDs: [WorldCell3DID],
        authoredDurationSeconds: Double,
        principalInteraction: PrincipalInteraction3DBindingSpec,
        beats: [ExperienceBeat3DSpec],
        narrationCueIDs: [AudioCueID]
    ) {
        self.id = id
        self.locationCue = locationCue
        self.worldCellIDs = worldCellIDs
        self.authoredDurationSeconds = authoredDurationSeconds
        self.principalInteraction = principalInteraction
        self.beats = beats
        self.narrationCueIDs = narrationCueIDs
    }

    fileprivate func validate(field: String) throws {
        try requireNonempty(id, field: "\(field).id")
        if let locationCue { try locationCue.validate(field: "\(field).locationCue") }
        guard !worldCellIDs.isEmpty,
              !beats.isEmpty,
              authoredDurationSeconds.isFinite,
              authoredDurationSeconds > 0 else {
            throw ContentValidationError.invalidValue(
                field: field,
                reason: "world cells, beats and positive authored duration are required"
            )
        }
        try requireUnique(worldCellIDs)
        try requireUnique(beats.map(\.id))
        try requireUnique(narrationCueIDs)
        try principalInteraction.validate(field: "\(field).principalInteraction")
        for (index, beat) in beats.enumerated() {
            try beat.validate(field: "\(field).beats[\(index)]")
            guard worldCellIDs.contains(beat.cellID) else {
                throw ContentValidationError.missingReference(
                    field: "\(field).beats[\(index)].cellID",
                    identifier: beat.cellID.rawValue
                )
            }
        }
        guard abs(beats.reduce(0) { $0 + $1.authoredDurationSeconds } - authoredDurationSeconds) < 0.001 else {
            throw ContentValidationError.invalidValue(
                field: "\(field).authoredDurationSeconds",
                reason: "must equal the sum of its beat durations"
            )
        }
        guard beats.last?.endsAtStableRestorationState == true else {
            throw ContentValidationError.invalidValue(
                field: "\(field).beats",
                reason: "the sequence must end at an accepted stable restoration state"
            )
        }
    }
}

public struct WorldCell3DSpec: Codable, Hashable, Sendable, Identifiable {
    public let id: WorldCell3DID
    public let sceneGraphAssetID: AssetReference3DID
    public let entities: [WorldEntity3DBindingSpec]
    public let materialBindings: [MaterialBinding3DSpec]
    public let animationBindings: [AnimationBinding3DSpec]
    public let cameraTracks: [CameraTrackSpec]
    public let semanticActions: [AccessibleSemanticAction3DSpec]
    public let lodGroups: [LODGroup3DSpec]

    public init(
        id: WorldCell3DID,
        sceneGraphAssetID: AssetReference3DID,
        entities: [WorldEntity3DBindingSpec],
        materialBindings: [MaterialBinding3DSpec],
        animationBindings: [AnimationBinding3DSpec],
        cameraTracks: [CameraTrackSpec],
        semanticActions: [AccessibleSemanticAction3DSpec],
        lodGroups: [LODGroup3DSpec]
    ) {
        self.id = id
        self.sceneGraphAssetID = sceneGraphAssetID
        self.entities = entities
        self.materialBindings = materialBindings
        self.animationBindings = animationBindings
        self.cameraTracks = cameraTracks
        self.semanticActions = semanticActions
        self.lodGroups = lodGroups
    }

    fileprivate func validate(field: String) throws {
        try requireNonempty(id, field: "\(field).id")
        try requireNonempty(sceneGraphAssetID, field: "\(field).sceneGraphAssetID")
        guard !entities.isEmpty,
              !materialBindings.isEmpty,
              !animationBindings.isEmpty,
              !cameraTracks.isEmpty,
              !lodGroups.isEmpty,
              entities.contains(where: { $0.role == .actionObject }) else {
            throw ContentValidationError.invalidValue(
                field: field,
                reason: "geometry, material, animation, camera, LOD and an action-bearing entity are required"
            )
        }
        try requireUnique(entities.map(\.id))
        try requireUnique(materialBindings.map(\.id))
        try requireUnique(animationBindings.map(\.id))
        try requireUnique(cameraTracks.map(\.id))
        try requireUnique(semanticActions.map(\.id))
        try requireUnique(lodGroups.map(\.id))

        for (index, entity) in entities.enumerated() {
            try entity.validate(field: "\(field).entities[\(index)]")
        }
        for (index, binding) in materialBindings.enumerated() {
            try binding.validate(field: "\(field).materialBindings[\(index)]")
        }
        for (index, binding) in animationBindings.enumerated() {
            try binding.validate(field: "\(field).animationBindings[\(index)]")
        }
        for (index, track) in cameraTracks.enumerated() {
            try track.validate(field: "\(field).cameraTracks[\(index)]")
        }
        for (index, action) in semanticActions.enumerated() {
            try action.validate(field: "\(field).semanticActions[\(index)]")
        }
        for (index, group) in lodGroups.enumerated() {
            try group.validate(field: "\(field).lodGroups[\(index)]")
        }
    }
}

public enum TransitionCarrierKind3D: String, Codable, Hashable, Sendable {
    case person
    case object
    case load
    case route
    case surface
    case sound
    case practice
    case worldTrace = "world-trace"
}

public enum TransitionIdentityRule3D: String, Codable, Hashable, Sendable {
    case preserveIdentity = "preserve-identity"
    case visibleHandoff = "visible-handoff"
}

public struct TransitionCarrierSpec: Codable, Hashable, Sendable, Identifiable {
    public let id: TransitionCarrier3DID
    public let sourceSequenceID: ExperienceSequenceID
    public let destinationSequenceID: ExperienceSequenceID
    public let sourceCellID: WorldCell3DID
    public let destinationCellID: WorldCell3DID
    public let kind: TransitionCarrierKind3D
    public let sourceEntityID: WorldEntity3DID
    public let destinationEntityID: WorldEntity3DID
    public let identityRule: TransitionIdentityRule3D
    public let cameraTrackID: CameraTrack3DID
    public let audioBindingID: AudioBinding3DID
    public let prefetchesDestinationCell: Bool
    public let visibleCue: LocalizedStringSpec?

    public init(
        id: TransitionCarrier3DID,
        sourceSequenceID: ExperienceSequenceID,
        destinationSequenceID: ExperienceSequenceID,
        sourceCellID: WorldCell3DID,
        destinationCellID: WorldCell3DID,
        kind: TransitionCarrierKind3D,
        sourceEntityID: WorldEntity3DID,
        destinationEntityID: WorldEntity3DID,
        identityRule: TransitionIdentityRule3D,
        cameraTrackID: CameraTrack3DID,
        audioBindingID: AudioBinding3DID,
        prefetchesDestinationCell: Bool,
        visibleCue: LocalizedStringSpec? = nil
    ) {
        self.id = id
        self.sourceSequenceID = sourceSequenceID
        self.destinationSequenceID = destinationSequenceID
        self.sourceCellID = sourceCellID
        self.destinationCellID = destinationCellID
        self.kind = kind
        self.sourceEntityID = sourceEntityID
        self.destinationEntityID = destinationEntityID
        self.identityRule = identityRule
        self.cameraTrackID = cameraTrackID
        self.audioBindingID = audioBindingID
        self.prefetchesDestinationCell = prefetchesDestinationCell
        self.visibleCue = visibleCue
    }

    fileprivate func validate(field: String) throws {
        try requireNonempty(id, field: "\(field).id")
        try requireNonempty(sourceSequenceID, field: "\(field).sourceSequenceID")
        try requireNonempty(destinationSequenceID, field: "\(field).destinationSequenceID")
        try requireNonempty(sourceCellID, field: "\(field).sourceCellID")
        try requireNonempty(destinationCellID, field: "\(field).destinationCellID")
        try requireNonempty(sourceEntityID, field: "\(field).sourceEntityID")
        try requireNonempty(destinationEntityID, field: "\(field).destinationEntityID")
        try requireNonempty(cameraTrackID, field: "\(field).cameraTrackID")
        try requireNonempty(audioBindingID, field: "\(field).audioBindingID")
        if let visibleCue { try visibleCue.validate(field: "\(field).visibleCue") }
        switch identityRule {
        case .preserveIdentity:
            guard sourceEntityID == destinationEntityID else {
                throw ContentValidationError.invalidValue(
                    field: "\(field).identityRule",
                    reason: "a preserved carrier must keep its stable entity identity"
                )
            }
        case .visibleHandoff:
            guard sourceEntityID != destinationEntityID else {
                throw ContentValidationError.invalidValue(
                    field: "\(field).identityRule",
                    reason: "a visible handoff requires newly identified material or people"
                )
            }
        }
        guard prefetchesDestinationCell == (sourceCellID != destinationCellID) else {
            throw ContentValidationError.invalidValue(
                field: "\(field).prefetchesDestinationCell",
                reason: "cross-cell carriers must prefetch; in-cell carriers must not"
            )
        }
    }
}

public struct Chapter01PacingSpec: Codable, Hashable, Sendable {
    public let authoredCoreSeconds: Double
    public let expectedFirstPlayMinimumSeconds: Double
    public let expectedFirstPlayMaximumSeconds: Double
    public let firstMeaningfulContactSeconds: Double
    public let maximumPassiveCameraSeconds: Double
    public let maximumNarrationWords: Int
    public let maximumVisibleInterfaceWords: Int

    public init(
        authoredCoreSeconds: Double,
        expectedFirstPlayMinimumSeconds: Double,
        expectedFirstPlayMaximumSeconds: Double,
        firstMeaningfulContactSeconds: Double,
        maximumPassiveCameraSeconds: Double,
        maximumNarrationWords: Int,
        maximumVisibleInterfaceWords: Int
    ) {
        self.authoredCoreSeconds = authoredCoreSeconds
        self.expectedFirstPlayMinimumSeconds = expectedFirstPlayMinimumSeconds
        self.expectedFirstPlayMaximumSeconds = expectedFirstPlayMaximumSeconds
        self.firstMeaningfulContactSeconds = firstMeaningfulContactSeconds
        self.maximumPassiveCameraSeconds = maximumPassiveCameraSeconds
        self.maximumNarrationWords = maximumNarrationWords
        self.maximumVisibleInterfaceWords = maximumVisibleInterfaceWords
    }

    fileprivate func validate() throws {
        guard authoredCoreSeconds == 815,
              expectedFirstPlayMinimumSeconds == 960,
              expectedFirstPlayMaximumSeconds == 1_050,
              firstMeaningfulContactSeconds > 0,
              firstMeaningfulContactSeconds <= 2,
              maximumPassiveCameraSeconds > 0,
              maximumPassiveCameraSeconds <= 8,
              maximumNarrationWords == 280,
              maximumVisibleInterfaceWords == 70 else {
            throw ContentValidationError.invalidValue(
                field: "contentPackageV2.pacing",
                reason: "must preserve the approved 13:35 core, 16:00–17:30 first play and Chapter 01 language/attention ceilings"
            )
        }
    }
}

// MARK: - Chapter 01 authority and payload

public enum Chapter01ImmersiveV2Authority {
    public static let schemaVersion = SchemaVersion(major: 2)
    public static let packageID: PackageID = "first-farmers-3d-review-v1"
    public static let chapterID: ChapterID = "first-farmers"

    public static let worldCellIDs: [WorldCell3DID] = [
        "world-cell-first-farmers-aegean-passage",
        "world-cell-first-farmers-thessalian-household",
        "world-cell-first-farmers-iron-gates",
        "world-cell-first-farmers-longhouse-ground",
        "world-cell-first-farmers-expansion-landscape",
    ]

    public static let sequenceIDs: [ExperienceSequenceID] = [
        "sequence-first-farmers-keep-future-alive",
        "sequence-first-farmers-harvest-had-to-last",
        "sequence-first-farmers-river-knows-landing",
        "sequence-first-farmers-hold-house",
        "sequence-first-farmers-house-cannot-hold-everyone",
        "sequence-first-farmers-relay-becomes-continent",
    ]

    public static let interactionIDs: [InteractionID] = [
        "interaction-first-farmers-a-household-crosses",
        "interaction-first-farmers-the-harvest-had-to-last",
        "interaction-first-farmers-at-the-iron-gates",
        "interaction-first-farmers-the-house-outlives",
        "interaction-first-farmers-more-mouths-more-land",
        "interaction-first-farmers-a-continent-remade",
    ]

    public static let transitionIDs: [TransitionCarrier3DID] = [
        "transition-first-farmers-vessel-to-furrow",
        "transition-first-farmers-threshing-to-allocation",
        "transition-first-farmers-spring-seed-north",
        "transition-first-farmers-landing-to-longhouse",
        "transition-first-farmers-threshold-to-herd-lane",
        "transition-first-farmers-cold-hearth-to-barrier",
    ]

    fileprivate static let grammars: [ImmersiveInteractionGrammar] = [
        .trace, .allocate, .transform, .assemble, .transform, .transform,
    ]
    fileprivate static let sequenceDurations: [Double] = [150, 190, 100, 150, 130, 95]
    fileprivate static let sequenceCells: [[WorldCell3DID]] = [
        [worldCellIDs[0], worldCellIDs[1]],
        [worldCellIDs[1]],
        [worldCellIDs[2]],
        [worldCellIDs[3]],
        [worldCellIDs[4]],
        [worldCellIDs[4]],
    ]
}

public struct ContentPackagePayloadV2: Codable, Hashable, Sendable {
    public let schemaVersion: SchemaVersion
    public let packageID: PackageID
    public let chapterID: ChapterID
    public let pacing: Chapter01PacingSpec
    public let streamingPolicy: ImmersiveStreamingPolicySpec
    public let assets: [AssetReference3DSpec]
    public let worldCells: [WorldCell3DSpec]
    public let sequences: [ExperienceSequenceSpec]
    public let transitions: [TransitionCarrierSpec]
    public let audioBindings: [ImmersiveAudioBindingSpec]
    public let narrationBindings: [NarrationBinding3DSpec]
    public let captions: [CaptionBinding3DSpec]

    public init(
        schemaVersion: SchemaVersion,
        packageID: PackageID,
        chapterID: ChapterID,
        pacing: Chapter01PacingSpec,
        streamingPolicy: ImmersiveStreamingPolicySpec,
        assets: [AssetReference3DSpec],
        worldCells: [WorldCell3DSpec],
        sequences: [ExperienceSequenceSpec],
        transitions: [TransitionCarrierSpec],
        audioBindings: [ImmersiveAudioBindingSpec],
        narrationBindings: [NarrationBinding3DSpec],
        captions: [CaptionBinding3DSpec]
    ) {
        self.schemaVersion = schemaVersion
        self.packageID = packageID
        self.chapterID = chapterID
        self.pacing = pacing
        self.streamingPolicy = streamingPolicy
        self.assets = assets
        self.worldCells = worldCells
        self.sequences = sequences
        self.transitions = transitions
        self.audioBindings = audioBindings
        self.narrationBindings = narrationBindings
        self.captions = captions
    }

    public func validate() throws {
        try validateAuthorityAndCounts()
        try pacing.validate()
        try streamingPolicy.validate()

        try requireUnique(assets.map(\.id))
        try requireUnique(worldCells.map(\.id))
        try requireUnique(sequences.map(\.id))
        try requireUnique(transitions.map(\.id))
        try requireUnique(audioBindings.map(\.id))
        try requireUnique(narrationBindings.map(\.id))
        try requireUnique(captions.map(\.id))
        let paths = assets.map(\.path)
        guard Set(paths).count == paths.count else {
            throw ContentValidationError.invalidValue(
                field: "contentPackageV2.assets.path",
                reason: "asset paths must be unique"
            )
        }

        for (index, asset) in assets.enumerated() {
            try asset.validate(field: "contentPackageV2.assets[\(index)]")
        }
        for (index, cell) in worldCells.enumerated() {
            try cell.validate(field: "contentPackageV2.worldCells[\(index)]")
        }
        for (index, sequence) in sequences.enumerated() {
            try sequence.validate(field: "contentPackageV2.sequences[\(index)]")
        }
        for (index, transition) in transitions.enumerated() {
            try transition.validate(field: "contentPackageV2.transitions[\(index)]")
        }
        for (index, binding) in audioBindings.enumerated() {
            try binding.validate(field: "contentPackageV2.audioBindings[\(index)]")
        }
        for (index, binding) in narrationBindings.enumerated() {
            try binding.validate(field: "contentPackageV2.narrationBindings[\(index)]")
        }
        for (index, caption) in captions.enumerated() {
            try caption.validate(field: "contentPackageV2.captions[\(index)]")
        }

        try validateAssetsAndCells()
        try validateSequencesAndActions()
        try validateTransitions()
        try validateAudioNarrationAndCaptions()
        try validatePublicLanguageBudget()
    }

    private func validateAuthorityAndCounts() throws {
        guard schemaVersion == Chapter01ImmersiveV2Authority.schemaVersion,
              packageID == Chapter01ImmersiveV2Authority.packageID,
              chapterID == Chapter01ImmersiveV2Authority.chapterID else {
            throw ContentValidationError.invalidValue(
                field: "contentPackageV2.authority",
                reason: "this schema is restricted to the approved Chapter 01 3D review package"
            )
        }
        guard worldCells.map(\.id) == Chapter01ImmersiveV2Authority.worldCellIDs,
              sequences.map(\.id) == Chapter01ImmersiveV2Authority.sequenceIDs,
              transitions.map(\.id) == Chapter01ImmersiveV2Authority.transitionIDs else {
            throw ContentValidationError.invalidValue(
                field: "contentPackageV2.flow",
                reason: "the five cells, six sequences and six causal carriers must preserve their approved order"
            )
        }
        guard sequences.flatMap(\.beats).count == 34 else {
            throw ContentValidationError.invalidCount(
                field: "contentPackageV2.sequences.beats",
                expected: "34",
                actual: sequences.flatMap(\.beats).count
            )
        }
    }

    private func validateAssetsAndCells() throws {
        let assetByID = Dictionary(uniqueKeysWithValues: assets.map { ($0.id, $0) })
        var usedAssetIDs: Set<AssetReference3DID> = []

        for cell in worldCells {
            guard assetByID[cell.sceneGraphAssetID]?.kind == .sceneGraph else {
                throw ContentValidationError.missingReference(
                    field: "contentPackageV2.worldCells.sceneGraphAssetID",
                    identifier: cell.sceneGraphAssetID.rawValue
                )
            }
            usedAssetIDs.insert(cell.sceneGraphAssetID)

            let entityIDs = Set(cell.entities.map(\.id))
            let materialByID = Dictionary(uniqueKeysWithValues: cell.materialBindings.map { ($0.id, $0) })
            let animationByID = Dictionary(uniqueKeysWithValues: cell.animationBindings.map { ($0.id, $0) })
            let actionByID = Dictionary(uniqueKeysWithValues: cell.semanticActions.map { ($0.id, $0) })

            for entity in cell.entities {
                for bindingID in entity.materialBindingIDs {
                    guard materialByID[bindingID]?.entityID == entity.id else {
                        throw ContentValidationError.missingReference(
                            field: "contentPackageV2.worldCells.entities.materialBindingIDs",
                            identifier: bindingID.rawValue
                        )
                    }
                }
                for bindingID in entity.animationBindingIDs {
                    guard animationByID[bindingID]?.entityID == entity.id else {
                        throw ContentValidationError.missingReference(
                            field: "contentPackageV2.worldCells.entities.animationBindingIDs",
                            identifier: bindingID.rawValue
                        )
                    }
                }
                for actionID in entity.semanticActionIDs {
                    guard actionByID[actionID]?.targetEntityID == entity.id else {
                        throw ContentValidationError.missingReference(
                            field: "contentPackageV2.worldCells.entities.semanticActionIDs",
                            identifier: actionID.rawValue
                        )
                    }
                }
            }

            for binding in cell.materialBindings {
                guard entityIDs.contains(binding.entityID) else {
                    throw ContentValidationError.missingReference(
                        field: "contentPackageV2.worldCells.materialBindings.entityID",
                        identifier: binding.entityID.rawValue
                    )
                }
                for state in binding.states {
                    guard assetByID[state.assetID]?.kind == .material else {
                        throw ContentValidationError.missingReference(
                            field: "contentPackageV2.worldCells.materialBindings.states.assetID",
                            identifier: state.assetID.rawValue
                        )
                    }
                    usedAssetIDs.insert(state.assetID)
                }
            }
            for binding in cell.animationBindings {
                guard entityIDs.contains(binding.entityID) else {
                    throw ContentValidationError.missingReference(
                        field: "contentPackageV2.worldCells.animationBindings.entityID",
                        identifier: binding.entityID.rawValue
                    )
                }
                for state in binding.states {
                    guard assetByID[state.assetID]?.kind == .animation else {
                        throw ContentValidationError.missingReference(
                            field: "contentPackageV2.worldCells.animationBindings.states.assetID",
                            identifier: state.assetID.rawValue
                        )
                    }
                    usedAssetIDs.insert(state.assetID)
                }
            }
            for action in cell.semanticActions where !entityIDs.contains(action.targetEntityID) {
                throw ContentValidationError.missingReference(
                    field: "contentPackageV2.worldCells.semanticActions.targetEntityID",
                    identifier: action.targetEntityID.rawValue
                )
            }
            for track in cell.cameraTracks {
                for focusID in (track.anchors + track.reduceMotion.anchors).compactMap(\.focusEntityID)
                    where !entityIDs.contains(focusID) {
                    throw ContentValidationError.missingReference(
                        field: "contentPackageV2.worldCells.cameraTracks.focusEntityID",
                        identifier: focusID.rawValue
                    )
                }
            }
            for group in cell.lodGroups {
                guard entityIDs.contains(group.entityID) else {
                    throw ContentValidationError.missingReference(
                        field: "contentPackageV2.worldCells.lodGroups.entityID",
                        identifier: group.entityID.rawValue
                    )
                }
                for level in group.levels {
                    guard let asset = assetByID[level.assetID],
                          asset.kind == .mesh || asset.kind == .sceneGraph else {
                        throw ContentValidationError.missingReference(
                            field: "contentPackageV2.worldCells.lodGroups.levels.assetID",
                            identifier: level.assetID.rawValue
                        )
                    }
                    usedAssetIDs.insert(level.assetID)
                }
            }
        }

        for binding in audioBindings {
            guard assetByID[binding.assetID]?.kind == .audio else {
                throw ContentValidationError.missingReference(
                    field: "contentPackageV2.audioBindings.assetID",
                    identifier: binding.assetID.rawValue
                )
            }
            usedAssetIDs.insert(binding.assetID)
        }
        guard usedAssetIDs == Set(assetByID.keys) else {
            throw ContentValidationError.invalidValue(
                field: "contentPackageV2.assets",
                reason: "every packaged asset must be referenced by the immersive runtime model"
            )
        }
    }

    private func validateSequencesAndActions() throws {
        let cellByID = Dictionary(uniqueKeysWithValues: worldCells.map { ($0.id, $0) })
        let allBeatIDs = sequences.flatMap(\.beats).map(\.id)
        try requireUnique(allBeatIDs)

        let allActions = worldCells.flatMap(\.semanticActions)
        try requireUnique(allActions.map(\.id))
        let actionByID = Dictionary(uniqueKeysWithValues: allActions.map { ($0.id, $0) })
        let usedActionIDs = sequences.flatMap(\.beats).flatMap(\.semanticActionIDs)
        try requireUnique(usedActionIDs)
        guard Set(usedActionIDs) == Set(actionByID.keys) else {
            throw ContentValidationError.invalidValue(
                field: "contentPackageV2.sequences.beats.semanticActionIDs",
                reason: "every authored semantic action must be used exactly once"
            )
        }

        for index in sequences.indices {
            let sequence = sequences[index]
            let interactionID = Chapter01ImmersiveV2Authority.interactionIDs[index]
            guard sequence.worldCellIDs == Chapter01ImmersiveV2Authority.sequenceCells[index],
                  sequence.authoredDurationSeconds == Chapter01ImmersiveV2Authority.sequenceDurations[index],
                  sequence.principalInteraction.interactionID == interactionID,
                  sequence.principalInteraction.grammar == Chapter01ImmersiveV2Authority.grammars[index] else {
                throw ContentValidationError.invalidValue(
                    field: "contentPackageV2.sequences[\(index)]",
                    reason: "cell scope, duration, stable interaction ID and grammar are approved Chapter 01 authority"
                )
            }
            let sequenceActionIDs = sequence.beats.flatMap(\.semanticActionIDs)
            guard !sequenceActionIDs.isEmpty,
                  sequenceActionIDs.allSatisfy({ actionByID[$0]?.interactionID == interactionID }) else {
                throw ContentValidationError.invalidValue(
                    field: "contentPackageV2.sequences[\(index)].beats.semanticActionIDs",
                    reason: "each sequence must act through its one approved principal interaction"
                )
            }
            for beat in sequence.beats {
                guard let cell = cellByID[beat.cellID],
                      cell.cameraTracks.contains(where: { $0.id == beat.cameraTrackID }) else {
                    throw ContentValidationError.missingReference(
                        field: "contentPackageV2.sequences.beats.cameraTrackID",
                        identifier: beat.cameraTrackID.rawValue
                    )
                }
                let cellActionIDs = Set(cell.semanticActions.map(\.id))
                guard beat.semanticActionIDs.allSatisfy(cellActionIDs.contains) else {
                    throw ContentValidationError.invalidValue(
                        field: "contentPackageV2.sequences.beats.semanticActionIDs",
                        reason: "actions must belong to the beat's resident world cell"
                    )
                }
            }
        }
        guard abs(sequences.reduce(0) { $0 + $1.authoredDurationSeconds } - pacing.authoredCoreSeconds) < 0.001 else {
            throw ContentValidationError.invalidValue(
                field: "contentPackageV2.sequences.authoredDurationSeconds",
                reason: "the six sequence durations must total the approved 13:35 core"
            )
        }
    }

    private func validateTransitions() throws {
        struct ExpectedTransition {
            let sourceSequence: Int
            let destinationSequence: Int
            let sourceCell: Int
            let destinationCell: Int
        }
        let expected: [ExpectedTransition] = [
            .init(sourceSequence: 0, destinationSequence: 0, sourceCell: 0, destinationCell: 1),
            .init(sourceSequence: 0, destinationSequence: 1, sourceCell: 1, destinationCell: 1),
            .init(sourceSequence: 1, destinationSequence: 2, sourceCell: 1, destinationCell: 2),
            .init(sourceSequence: 2, destinationSequence: 3, sourceCell: 2, destinationCell: 3),
            .init(sourceSequence: 3, destinationSequence: 4, sourceCell: 3, destinationCell: 4),
            .init(sourceSequence: 4, destinationSequence: 5, sourceCell: 4, destinationCell: 4),
        ]
        let cellByID = Dictionary(uniqueKeysWithValues: worldCells.map { ($0.id, $0) })
        let audioByID = Dictionary(uniqueKeysWithValues: audioBindings.map { ($0.id, $0) })

        for index in transitions.indices {
            let transition = transitions[index]
            let authority = expected[index]
            guard transition.sourceSequenceID == sequences[authority.sourceSequence].id,
                  transition.destinationSequenceID == sequences[authority.destinationSequence].id,
                  transition.sourceCellID == worldCells[authority.sourceCell].id,
                  transition.destinationCellID == worldCells[authority.destinationCell].id else {
                throw ContentValidationError.invalidValue(
                    field: "contentPackageV2.transitions[\(index)]",
                    reason: "the carrier must join the approved sequence and cell boundary"
                )
            }
            guard let sourceCell = cellByID[transition.sourceCellID],
                  let destinationCell = cellByID[transition.destinationCellID],
                  sourceCell.entities.contains(where: { $0.id == transition.sourceEntityID }),
                  destinationCell.entities.contains(where: { $0.id == transition.destinationEntityID }) else {
                throw ContentValidationError.invalidValue(
                    field: "contentPackageV2.transitions[\(index)].entityID",
                    reason: "carrier entities must exist on both sides of the handoff"
                )
            }
            let cameraExists = sourceCell.cameraTracks.contains(where: { $0.id == transition.cameraTrackID })
                || destinationCell.cameraTracks.contains(where: { $0.id == transition.cameraTrackID })
            guard cameraExists else {
                throw ContentValidationError.missingReference(
                    field: "contentPackageV2.transitions[\(index)].cameraTrackID",
                    identifier: transition.cameraTrackID.rawValue
                )
            }
            guard let audio = audioByID[transition.audioBindingID],
                  audio.role == .transition,
                  audio.sequenceID == transition.destinationSequenceID else {
                throw ContentValidationError.missingReference(
                    field: "contentPackageV2.transitions[\(index)].audioBindingID",
                    identifier: transition.audioBindingID.rawValue
                )
            }
        }
    }

    private func validateAudioNarrationAndCaptions() throws {
        let cellIDs = Set(worldCells.map(\.id))
        let sequenceIDs = Set(sequences.map(\.id))
        let interactionIDs = Set(Chapter01ImmersiveV2Authority.interactionIDs)
        let audioByID = Dictionary(uniqueKeysWithValues: audioBindings.map { ($0.id, $0) })

        for binding in audioBindings {
            if let cellID = binding.cellID, !cellIDs.contains(cellID) {
                throw ContentValidationError.missingReference(
                    field: "contentPackageV2.audioBindings.cellID",
                    identifier: cellID.rawValue
                )
            }
            if let sequenceID = binding.sequenceID, !sequenceIDs.contains(sequenceID) {
                throw ContentValidationError.missingReference(
                    field: "contentPackageV2.audioBindings.sequenceID",
                    identifier: sequenceID.rawValue
                )
            }
            if let interactionID = binding.interactionID, !interactionIDs.contains(interactionID) {
                throw ContentValidationError.missingReference(
                    field: "contentPackageV2.audioBindings.interactionID",
                    identifier: interactionID.rawValue
                )
            }
        }
        for cellID in cellIDs {
            guard audioBindings.contains(where: { $0.role == .environment && $0.cellID == cellID }) else {
                throw ContentValidationError.missingReference(
                    field: "contentPackageV2.audioBindings.environment.cellID",
                    identifier: cellID.rawValue
                )
            }
        }
        for interactionID in interactionIDs {
            guard audioBindings.contains(where: {
                $0.role == .mechanism && $0.interactionID == interactionID
            }) else {
                throw ContentValidationError.missingReference(
                    field: "contentPackageV2.audioBindings.mechanism.interactionID",
                    identifier: interactionID.rawValue
                )
            }
        }

        guard narrationBindings.count == 10 else {
            throw ContentValidationError.invalidCount(
                field: "contentPackageV2.narrationBindings",
                expected: "10",
                actual: narrationBindings.count
            )
        }
        let captionByID = Dictionary(uniqueKeysWithValues: captions.map { ($0.id, $0) })
        var usedCaptionIDs: Set<CaptionBinding3DID> = []
        var narrationWords = 0
        var narrationSeconds = 0.0

        for narration in narrationBindings {
            guard sequenceIDs.contains(narration.sequenceID),
                  let audio = audioByID[narration.audioBindingID],
                  audio.role == .narration,
                  audio.sequenceID == narration.sequenceID else {
                throw ContentValidationError.missingReference(
                    field: "contentPackageV2.narrationBindings.audioBindingID",
                    identifier: narration.audioBindingID.rawValue
                )
            }
            let scopedCaptions = try narration.captionIDs.map { id in
                guard let caption = captionByID[id], caption.narrationCueID == narration.id else {
                    throw ContentValidationError.missingReference(
                        field: "contentPackageV2.narrationBindings.captionIDs",
                        identifier: id.rawValue
                    )
                }
                return caption
            }
            guard scopedCaptions.map(\.startSampleFrame) == scopedCaptions.map(\.startSampleFrame).sorted(),
                  scopedCaptions.allSatisfy({ $0.endSampleFrame <= audio.durationSampleFrames }) else {
                throw ContentValidationError.invalidValue(
                    field: "contentPackageV2.captions",
                    reason: "caption phrases must be ordered within their narration audio"
                )
            }
            for pair in zip(scopedCaptions, scopedCaptions.dropFirst()) where pair.0.endSampleFrame > pair.1.startSampleFrame {
                throw ContentValidationError.invalidValue(
                    field: "contentPackageV2.captions",
                    reason: "caption phrases may not overlap"
                )
            }
            let transcript = scopedCaptions.map(\.text.launchEnglish).joined(separator: " ").normalizedWhitespace
            guard transcript == narration.text.launchEnglish.normalizedWhitespace else {
                throw ContentValidationError.invalidValue(
                    field: "contentPackageV2.narrationBindings.text",
                    reason: "the timed caption transcript must be word-exact with narration"
                )
            }
            usedCaptionIDs.formUnion(narration.captionIDs)
            narrationWords += narration.text.launchEnglish.wordCount
            narrationSeconds += audio.durationSeconds
        }
        guard usedCaptionIDs == Set(captionByID.keys),
              narrationWords <= pacing.maximumNarrationWords,
              narrationSeconds < 120 else {
            throw ContentValidationError.invalidValue(
                field: "contentPackageV2.narrationBindings",
                reason: "all captions must be bound and narration must remain under 280 words and two minutes"
            )
        }

        let narrationIDs = Set(narrationBindings.map(\.id))
        let sequenceNarrationIDs = sequences.flatMap(\.narrationCueIDs)
        let beatNarrationIDs = sequences.flatMap(\.beats).flatMap(\.narrationCueIDs)
        try requireUnique(sequenceNarrationIDs)
        try requireUnique(beatNarrationIDs)
        guard Set(sequenceNarrationIDs) == narrationIDs,
              Set(beatNarrationIDs) == narrationIDs else {
            throw ContentValidationError.invalidValue(
                field: "contentPackageV2.sequences.narrationCueIDs",
                reason: "every narration cue must bind exactly once to its sequence and beat"
            )
        }
        for sequence in sequences {
            let validIDs = Set(narrationBindings.filter { $0.sequenceID == sequence.id }.map(\.id))
            guard Set(sequence.narrationCueIDs) == validIDs else {
                throw ContentValidationError.invalidValue(
                    field: "contentPackageV2.sequences.narrationCueIDs",
                    reason: "narration scope must match the authored sequence"
                )
            }
        }
    }

    private func validatePublicLanguageBudget() throws {
        let visibleStrings = sequences.compactMap(\.locationCue)
            + transitions.compactMap(\.visibleCue)
            + worldCells.flatMap(\.semanticActions).compactMap(\.visibleFallbackCue)
        try requireConsistentLocalizedStrings(visibleStrings, field: "contentPackageV2.visibleLanguage")
        let visibleWords = visibleStrings.reduce(0) { $0 + $1.launchEnglish.wordCount }
        guard visibleWords <= pacing.maximumVisibleInterfaceWords else {
            throw ContentValidationError.invalidValue(
                field: "contentPackageV2.visibleLanguage",
                reason: "location, transition and fallback language exceeds the 70-word first-play ceiling"
            )
        }
    }
}

// MARK: - Fail-closed public document boundary

public enum ImmersiveContentDocumentV2 {
    private static let forbiddenBackstageKeys: Set<String> = [
        "sources", "evidence", "researchnotes", "claimregister", "confidence",
        "historiography", "counterarguments", "methodology", "scholarnotes",
        "verifierfindings", "factcheck", "sourcebasis",
    ]

    public static func decode(_ data: Data) throws -> ContentPackagePayloadV2 {
        let inputObject: Any
        do {
            inputObject = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw ContentValidationError.invalidValue(
                field: "contentPackageV2",
                reason: "valid JSON is required"
            )
        }
        guard !containsForbiddenBackstageKey(inputObject) else {
            throw ContentValidationError.invalidValue(
                field: "contentPackageV2",
                reason: "backstage research fields are physically excluded from public content"
            )
        }

        let payload: ContentPackagePayloadV2
        do {
            payload = try JSONDecoder().decode(ContentPackagePayloadV2.self, from: data)
        } catch {
            throw ContentValidationError.invalidValue(
                field: "contentPackageV2",
                reason: "field types do not match the immersive v2 wire contract"
            )
        }
        try payload.validate()

        let canonicalData = try encode(payload)
        let canonicalObject = try JSONSerialization.jsonObject(with: canonicalData)
        guard objectsAreEqual(inputObject, canonicalObject) else {
            throw ContentValidationError.invalidValue(
                field: "contentPackageV2",
                reason: "the exact public immersive v2 wire fields are required"
            )
        }
        return payload
    }

    public static func encode(_ payload: ContentPackagePayloadV2) throws -> Data {
        try payload.validate()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(payload)
    }

    private static func containsForbiddenBackstageKey(_ value: Any) -> Bool {
        if let dictionary = value as? [String: Any] {
            for (key, child) in dictionary {
                let normalized = key.lowercased().filter { $0.isLetter || $0.isNumber }
                if forbiddenBackstageKeys.contains(normalized) || containsForbiddenBackstageKey(child) {
                    return true
                }
            }
        } else if let array = value as? [Any] {
            return array.contains(where: containsForbiddenBackstageKey)
        }
        return false
    }

    private static func objectsAreEqual(_ lhs: Any, _ rhs: Any) -> Bool {
        guard let left = lhs as? NSObject, let right = rhs as? NSObject else { return false }
        return left.isEqual(right)
    }
}

private func requireStableKey(_ value: String, field: String) throws {
    guard isStableStringIdentifier(value) else {
        throw ContentValidationError.invalidValue(
            field: field,
            reason: "must be a stable kebab-case key"
        )
    }
}

private extension String {
    var normalizedWhitespace: String {
        split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    var wordCount: Int {
        split(whereSeparator: \.isWhitespace).count
    }
}
