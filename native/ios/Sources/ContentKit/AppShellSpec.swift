import Foundation

/// The first playable historical action. It is deliberately a causal beat,
/// not onboarding copy or a tutorial overlay.
public struct PrologueSpec: Codable, Equatable, Sendable {
    public let id: PrologueID
    public let sceneID: SceneID
    public let narrative: NarrativeText
    public let interaction: InteractionSpec
    public let checkpoint: CheckpointPolicy

    public init(
        id: PrologueID,
        sceneID: SceneID,
        narrative: NarrativeText,
        interaction: InteractionSpec,
        checkpoint: CheckpointPolicy
    ) {
        self.id = id
        self.sceneID = sceneID
        self.narrative = narrative
        self.interaction = interaction
        self.checkpoint = checkpoint
    }

    public func validate() throws {
        try requireNonempty(id, field: "prologue.id")
        try requireNonempty(sceneID, field: "prologue.sceneID")
        try narrative.validate(field: "prologue.narrative")
        try interaction.validate()
        guard case .trace = interaction.grammar,
              checkpoint == .afterInteraction else {
            throw ContentValidationError.invalidValue(
                field: "prologue",
                reason: "the launch road must wake through one checkpointed trace interaction"
            )
        }
    }
}

public struct LivingWorldChapterPresentationSpec: Codable, Equatable, Sendable {
    public let chapterID: ChapterID
    public let worldNodeID: WorldNodeID
    public let position: NormalizedPoint
    public let historicalInvitation: LocalizedStringSpec

    public init(
        chapterID: ChapterID,
        worldNodeID: WorldNodeID,
        position: NormalizedPoint,
        historicalInvitation: LocalizedStringSpec
    ) {
        self.chapterID = chapterID
        self.worldNodeID = worldNodeID
        self.position = position
        self.historicalInvitation = historicalInvitation
    }
}

public struct LivingWorldTracePresentationSpec: Codable, Equatable, Sendable {
    public let worldTraceID: WorldTraceID
    public let layerID: SceneLayerID

    public init(worldTraceID: WorldTraceID, layerID: SceneLayerID) {
        self.worldTraceID = worldTraceID
        self.layerID = layerID
    }
}

/// The one cumulative return surface. These bindings project deterministic
/// world state into authored scene layers; they do not define a card library.
public struct LivingWorldPresentationSpec: Codable, Equatable, Sendable {
    public let id: LivingWorldPresentationID
    public let sceneID: SceneID
    public let accessibilityID: AccessibilityID
    public let currentPlaceLayerID: SceneLayerID
    public let nextPressureLayerID: SceneLayerID
    public let chapters: [LivingWorldChapterPresentationSpec]
    public let traces: [LivingWorldTracePresentationSpec]

    public init(
        id: LivingWorldPresentationID,
        sceneID: SceneID,
        accessibilityID: AccessibilityID,
        currentPlaceLayerID: SceneLayerID,
        nextPressureLayerID: SceneLayerID,
        chapters: [LivingWorldChapterPresentationSpec],
        traces: [LivingWorldTracePresentationSpec]
    ) {
        self.id = id
        self.sceneID = sceneID
        self.accessibilityID = accessibilityID
        self.currentPlaceLayerID = currentPlaceLayerID
        self.nextPressureLayerID = nextPressureLayerID
        self.chapters = chapters
        self.traces = traces
    }

    public func validate() throws {
        try requireNonempty(id, field: "livingWorld.id")
        try requireNonempty(sceneID, field: "livingWorld.sceneID")
        try requireNonempty(accessibilityID, field: "livingWorld.accessibilityID")
        try requireNonempty(currentPlaceLayerID, field: "livingWorld.currentPlaceLayerID")
        try requireNonempty(nextPressureLayerID, field: "livingWorld.nextPressureLayerID")
        guard currentPlaceLayerID != nextPressureLayerID,
              !chapters.isEmpty,
              !traces.isEmpty else {
            throw ContentValidationError.invalidValue(
                field: "livingWorld",
                reason: "requires distinct present/pressure layers, chapter anchors and world traces"
            )
        }
        try requireUnique(chapters.map(\.chapterID))
        try requireUnique(chapters.map(\.worldNodeID))
        try requireUnique(traces.map(\.worldTraceID))
        try requireUnique(traces.map(\.layerID))
        for chapter in chapters {
            try requireNonempty(chapter.chapterID, field: "livingWorld.chapters.chapterID")
            try requireNonempty(chapter.worldNodeID, field: "livingWorld.chapters.worldNodeID")
            guard chapter.position.isUnitPoint else {
                throw ContentValidationError.invalidValue(
                    field: "livingWorld.chapters.position",
                    reason: "must be a normalized position in the authored world"
                )
            }
            try chapter.historicalInvitation.validate(
                field: "livingWorld.chapters.\(chapter.chapterID).historicalInvitation"
            )
        }
        for trace in traces {
            try requireNonempty(trace.worldTraceID, field: "livingWorld.traces.worldTraceID")
            try requireNonempty(trace.layerID, field: "livingWorld.traces.layerID")
        }
        try requireConsistentLocalizedStrings(
            chapters.map(\.historicalInvitation),
            field: "livingWorld.localizedStrings"
        )
    }
}

public struct AppShellSpec: Codable, Equatable, Sendable {
    public let schemaVersion: SchemaVersion
    public let id: AppShellID
    public let locale: LocaleDescriptor
    public let prologue: PrologueSpec
    public let livingWorld: LivingWorldPresentationSpec

    public init(
        schemaVersion: SchemaVersion,
        id: AppShellID,
        locale: LocaleDescriptor,
        prologue: PrologueSpec,
        livingWorld: LivingWorldPresentationSpec
    ) {
        self.schemaVersion = schemaVersion
        self.id = id
        self.locale = locale
        self.prologue = prologue
        self.livingWorld = livingWorld
    }

    public func validate() throws {
        guard schemaVersion.isValid else {
            throw ContentValidationError.invalidValue(
                field: "appShell.schemaVersion",
                reason: "components must be non-negative"
            )
        }
        try requireNonempty(id, field: "appShell.id")
        try locale.validate(field: "appShell.locale")
        try prologue.validate()
        try livingWorld.validate()
        try requireConsistentLocalizedStrings(
            prologue.narrative.allLocalizedStrings
                + [prologue.interaction.prompt]
                + livingWorld.chapters.map(\.historicalInvitation),
            field: "appShell.localizedStrings"
        )
    }

    public func validateLaunch() throws {
        try validate()
        guard locale == .launchEnglish,
              livingWorld.chapters.count == LaunchContent.chapterOrder.count,
              livingWorld.chapters.map(\.chapterID) == LaunchContent.chapterOrder else {
            throw ContentValidationError.invalidValue(
                field: "appShell.launch",
                reason: "must use launch English and bind the complete chronological road"
            )
        }
    }
}
