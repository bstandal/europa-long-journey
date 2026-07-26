import CryptoKit
import Foundation

/// Canonical shipping payload. The package compiler and the iOS runtime consume this exact shape.
public struct ContentPackagePayload: Codable, Equatable, Sendable {
    public let schemaVersion: SchemaVersion
    public let packageID: PackageID
    public let worldSeed: WorldSeedSpec
    public let chapters: [ChapterSpec]
    public let scenes: [SceneSpec]
    public let audioTimelines: [AudioTimeline]
    public let responsiveAudioPrograms: [ResponsiveAudioProgramSpec]
    public let accessibility: [AccessibilitySpec]

    public init(
        schemaVersion: SchemaVersion,
        packageID: PackageID,
        worldSeed: WorldSeedSpec,
        chapters: [ChapterSpec],
        scenes: [SceneSpec],
        audioTimelines: [AudioTimeline],
        responsiveAudioPrograms: [ResponsiveAudioProgramSpec] = [],
        accessibility: [AccessibilitySpec]
    ) {
        self.schemaVersion = schemaVersion
        self.packageID = packageID
        self.worldSeed = worldSeed
        self.chapters = chapters
        self.scenes = scenes
        self.audioTimelines = audioTimelines
        self.responsiveAudioPrograms = responsiveAudioPrograms
        self.accessibility = accessibility
    }

    public func validate() throws {
        try requireNonempty(packageID, field: "contentPackage.packageID")
        try worldSeed.validate()
        guard schemaVersion.isValid else {
            throw ContentValidationError.invalidValue(
                field: "contentPackage.schemaVersion",
                reason: "components must be non-negative"
            )
        }
        guard !chapters.isEmpty, !scenes.isEmpty, !audioTimelines.isEmpty,
              !accessibility.isEmpty else {
            throw ContentValidationError.invalidValue(
                field: "contentPackage",
                reason: "chapters, scenes, audio timelines and accessibility are required"
            )
        }

        try requireUnique(chapters.map(\.id))
        try requireUnique(scenes.map(\.id))
        try requireUnique(audioTimelines.map(\.id))
        try requireUnique(responsiveAudioPrograms.map(\.id))
        try requireUnique(accessibility.map(\.id))

        let arcs = chapters.flatMap(\.arcs)
        let beats = arcs.flatMap(\.beats)
        let interactions = beats.compactMap(\.interaction)
        try requireUnique(arcs.map(\.id))
        try requireUnique(beats.map(\.id))
        try requireUnique(interactions.map(\.id))
        try requireUnique(interactions.map(\.accessibilityID))

        let scopedInteractionBindings = chapters.flatMap { chapter in
            chapter.arcs.flatMap { arc in
                arc.beats.compactMap { beat in
                    beat.interaction.map {
                        (
                            scope: ResponsiveAudioProgramScope(
                                chapterID: chapter.id,
                                arcID: arc.id,
                                beatID: beat.id,
                                interactionID: $0.id
                            ),
                            interaction: $0
                        )
                    }
                }
            }
        }
        let scopedInteractions = scopedInteractionBindings.map(\.scope)
        let programScopes = responsiveAudioPrograms.map(\.scope)
        guard Set(programScopes) == Set(scopedInteractions),
              programScopes.count == scopedInteractions.count else {
            throw ContentValidationError.invalidValue(
                field: "contentPackage.responsiveAudioPrograms.scope",
                reason: "every interaction requires exactly one program in its exact chapter/arc/beat scope"
            )
        }

        let allEffects = chapters.flatMap(\.completionEffects)
            + beats.flatMap(\.completionEffects)
            + interactions.flatMap(\.completionEffects)
        try requireUnique(allEffects.map(\.id))

        for chapter in chapters {
            try chapter.validate()
            guard chapter.schemaVersion == schemaVersion else {
                throw ContentValidationError.invalidValue(
                    field: "contentPackage.chapters.schemaVersion",
                    reason: "every chapter must use the package schema version"
                )
            }
        }
        for scene in scenes { try scene.validate() }
        for timeline in audioTimelines { try timeline.validate() }
        for program in responsiveAudioPrograms {
            try program.validate(timelines: audioTimelines)
            if program.causalMix != nil {
                guard let binding = scopedInteractionBindings.first(where: {
                    $0.scope == program.scope
                }) else {
                    throw ContentValidationError.invalidValue(
                        field: "contentPackage.responsiveAudioPrograms.causalMix",
                        reason: "could not resolve the scoped interaction"
                    )
                }
                try program.validateCausalMixBinding(to: binding.interaction)
            }
        }
        for specification in accessibility { try specification.validate() }
        try requireConsistentLocalizedStrings(
            localizedStrings,
            field: "contentPackage.localizedStrings"
        )

        let sceneIDs = Set(scenes.map(\.id))
        let sceneByID = Dictionary(uniqueKeysWithValues: scenes.map { ($0.id, $0) })
        let accessibilityIDs = Set(accessibility.map(\.id))
        let accessibilityByID = Dictionary(uniqueKeysWithValues: accessibility.map { ($0.id, $0) })
        let interactionAccessibilityIDs = Set(interactions.map(\.accessibilityID))
        let allCueIDs = audioTimelines.flatMap(\.events).map(\.cueID)
        try requireUnique(allCueIDs)
        let narrationEvents = audioTimelines.flatMap(\.events)
            .filter { $0.role == .narration }
        let narrationEventByCueID = Dictionary(
            uniqueKeysWithValues: narrationEvents.map { ($0.cueID, $0) }
        )

        let scopedBeats = chapters.flatMap { chapter in
            chapter.arcs.flatMap { arc in
                arc.beats.map { beat in
                    (chapterID: chapter.id, arcID: arc.id, beat: beat)
                }
            }
        }
        var referencedNarrationCueIDs: [AudioCueID] = []
        for scopedBeat in scopedBeats {
            let beat = scopedBeat.beat
            guard sceneIDs.contains(beat.sceneID) else {
                throw ContentValidationError.missingReference(
                    field: "contentPackage.beats.sceneID",
                    identifier: beat.sceneID.rawValue
                )
            }
            for cueID in beat.narrationCueIDs {
                guard let event = narrationEventByCueID[cueID] else {
                    throw ContentValidationError.missingReference(
                        field: "contentPackage.beats.narrationCueIDs",
                        identifier: cueID.rawValue
                    )
                }
                try validateNarrationBinding(
                    event,
                    chapterID: scopedBeat.chapterID,
                    arcID: scopedBeat.arcID,
                    beat: beat
                )
                referencedNarrationCueIDs.append(cueID)
            }
            if let interaction = beat.interaction {
                guard let scene = sceneByID[beat.sceneID], !scene.interactionTargets.isEmpty else {
                    throw ContentValidationError.invalidValue(
                        field: "contentPackage.scenes.interactionTargets",
                        reason: "an interactive beat requires at least one real scene target"
                    )
                }
                guard scene.accessibilityID == interaction.accessibilityID else {
                    throw ContentValidationError.invalidValue(
                        field: "contentPackage.scenes.accessibilityID",
                        reason: "must equal the bound interaction accessibilityID"
                    )
                }
                try validateRuntimeVisualBinding(scene: scene, interaction: interaction)
                guard let accessibilitySpec = accessibilityByID[interaction.accessibilityID] else {
                    throw ContentValidationError.missingReference(
                        field: "contentPackage.interactions.accessibilityID",
                        identifier: interaction.accessibilityID.rawValue
                    )
                }
                try accessibilitySpec.validateBinding(to: interaction)
            }
        }
        try requireUnique(referencedNarrationCueIDs)
        guard Set(referencedNarrationCueIDs) == Set(narrationEventByCueID.keys) else {
            throw ContentValidationError.invalidValue(
                field: "contentPackage.audioTimelines.events.narrationBinding",
                reason: "every narration cue must be referenced exactly once by its scoped beat"
            )
        }

        for scene in scenes {
            guard accessibilityIDs.contains(scene.accessibilityID),
                  let accessibilitySpec = accessibilityByID[scene.accessibilityID] else {
                throw ContentValidationError.missingReference(
                    field: "contentPackage.scenes.accessibilityID",
                    identifier: scene.accessibilityID.rawValue
                )
            }
            let elementByID = Dictionary(
                uniqueKeysWithValues: accessibilitySpec.elements.map { ($0.id, $0) }
            )
            for target in scene.interactionTargets {
                guard let element = elementByID[target.accessibilityElementID] else {
                    throw ContentValidationError.missingReference(
                        field: "contentPackage.scenes.interactionTargets.accessibilityElementID",
                        identifier: target.accessibilityElementID
                    )
                }
                guard (element.role == .action || element.role == .adjustable),
                      !element.actions.isEmpty else {
                    throw ContentValidationError.invalidValue(
                        field: "contentPackage.scenes.interactionTargets.accessibilityElementID",
                        reason: "must bind to an operable action or adjustable element with authored actions"
                    )
                }
            }
        }

        for specification in accessibility
            where specification.elements.contains(where: { !$0.actions.isEmpty })
                && !interactionAccessibilityIDs.contains(specification.id) {
            throw ContentValidationError.invalidValue(
                field: "contentPackage.accessibility",
                reason: "operable accessibility spec '\(specification.id)' is not bound to an interaction"
            )
        }

        _ = try WorldReplayValidator.validate(seed: worldSeed, chapters: chapters)
    }

    private var localizedStrings: [LocalizedStringSpec] {
        var output: [LocalizedStringSpec] = []
        for chapter in chapters {
            output.append(contentsOf: [chapter.title, chapter.period])
            for arc in chapter.arcs {
                output.append(contentsOf: [
                    arc.title,
                    arc.situation,
                    arc.mechanism,
                    arc.turn,
                    arc.consequence,
                    arc.handoff,
                ])
                for beat in arc.beats {
                    output.append(contentsOf: beat.narrative.allLocalizedStrings)
                    if let interaction = beat.interaction {
                        output.append(interaction.prompt)
                        if case let .allocate(configuration) = interaction.grammar {
                            output.append(configuration.resourceName)
                        }
                    }
                }
            }
        }
        output.append(contentsOf: scenes.map(\.mechanismFocus))
        for specification in accessibility {
            output.append(specification.sceneSummary)
            for element in specification.elements {
                output.append(element.label)
                output.append(contentsOf: [element.value, element.hint].compactMap { $0 })
                output.append(contentsOf: element.actions.map(\.label))
            }
        }
        return output
    }

    private func validateNarrationBinding(
        _ event: AudioEvent,
        chapterID: ChapterID,
        arcID: ArcID,
        beat: BeatSpec
    ) throws {
        guard let binding = event.narrationBinding else {
            throw ContentValidationError.invalidValue(
                field: "contentPackage.audioTimelines.events.narrationBinding",
                reason: "narration cue '\(event.cueID)' has no manuscript binding"
            )
        }
        let expectedScope = NarrationCueScope(
            chapterID: chapterID,
            arcID: arcID,
            beatID: beat.id
        )
        guard binding.scope == expectedScope,
              let segment = beat.narrative.manuscriptSegments.first(where: {
                  $0.id == binding.manuscriptSegmentID
              }) else {
            throw ContentValidationError.invalidValue(
                field: "contentPackage.audioTimelines.events.narrationBinding",
                reason: "cue '\(event.cueID)' must bind a manuscript segment inside its exact chapter/arc/beat scope"
            )
        }
        let digest = SHA256.hash(data: Data(segment.launchEnglish.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        guard digest == binding.manuscriptSegmentSHA256 else {
            throw ContentValidationError.invalidValue(
                field: "contentPackage.audioTimelines.events.narrationBinding.manuscriptSegmentSHA256",
                reason: "cue '\(event.cueID)' does not match the editor-approved English manuscript bytes"
            )
        }
    }

    /// Shipping packages require an exact visual binding whose stateful layers can be resolved by the
    /// five production SceneRuntime adapters. Standalone SceneSpec validation remains intentionally
    /// more permissive so the experience laboratory can author bindings before package assembly.
    private func validateRuntimeVisualBinding(
        scene: SceneSpec,
        interaction: InteractionSpec
    ) throws {
        guard let binding = scene.interactionVisualBinding else {
            throw ContentValidationError.invalidValue(
                field: "contentPackage.scenes.interactionVisualBinding",
                reason: "an interactive shipping beat requires an authored visual binding supported by the current runtime"
            )
        }
        try scene.validateInteractionVisualBinding(to: interaction)

        let statefulLayerIDs = Set(
            scene.layers.filter { !$0.stateVariants.isEmpty }.map(\.id)
        )
        let runtimeLayerIDs: Set<SceneLayerID>
        switch binding {
        case let .trace(configuration):
            runtimeLayerIDs = [configuration.layerID]
        case let .allocate(configuration):
            runtimeLayerIDs = Set(
                [configuration.resource.layerID]
                    + configuration.destinations.map(\.layerID)
            )
        case let .assemble(configuration):
            let componentLayerIDs = configuration.components.map(\.layerID)
            guard Set(componentLayerIDs).count == componentLayerIDs.count else {
                throw ContentValidationError.invalidValue(
                    field: "contentPackage.scenes.interactionVisualBinding.assemble.components",
                    reason: "each assembly component requires its own stateful runtime layer"
                )
            }
            runtimeLayerIDs = Set(componentLayerIDs)
        case let .pressure(configuration):
            runtimeLayerIDs = [configuration.systemLayerID]
        case let .transform(configuration):
            runtimeLayerIDs = Set(configuration.stages.map(\.layerID))
        }
        guard runtimeLayerIDs == statefulLayerIDs else {
            throw ContentValidationError.invalidValue(
                field: "contentPackage.scenes.interactionVisualBinding",
                reason: "must bind every and only stateful scene layer resolved by its runtime adapter"
            )
        }
    }
}

public enum ContentDocumentDecoder {
    public static func decodePackage(_ data: Data) throws -> ContentPackagePayload {
        let payload = try JSONDecoder().decode(ContentPackagePayload.self, from: data)
        try payload.validate()
        return payload
    }

    public static func encodePackage(_ payload: ContentPackagePayload) throws -> Data {
        try payload.validate()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(payload)
    }
}
