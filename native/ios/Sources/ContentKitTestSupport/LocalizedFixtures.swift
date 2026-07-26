import ContentKit
import CryptoKit
import Foundation

private func fixtureCopy(_ role: String, _ launchEnglish: String) -> LocalizedStringSpec {
    let digest = SHA256.hash(data: Data("\(role)\u{0}\(launchEnglish)".utf8))
        .map { String(format: "%02x", $0) }
        .joined()
    return LocalizedStringSpec(
        id: LocalizedStringID("test-copy-\(digest.prefix(20))"),
        launchEnglish: launchEnglish
    )
}

public extension ChapterIndexEntry {
    init(
        id: ChapterID,
        sequence: Int,
        title: String,
        period: String,
        packageID: PackageID,
        access: AccessRule
    ) {
        self.init(
            id: id,
            sequence: sequence,
            title: fixtureCopy("\(id)-title", title),
            period: fixtureCopy("\(id)-period", period),
            packageID: packageID,
            access: access
        )
    }
}

public extension ChapterSpec {
    init(
        schemaVersion: SchemaVersion,
        id: ChapterID,
        title: String,
        period: String,
        arcs: [ArcSpec],
        completionEffects: [WorldEffect]
    ) {
        self.init(
            schemaVersion: schemaVersion,
            id: id,
            title: fixtureCopy("\(id)-title", title),
            period: fixtureCopy("\(id)-period", period),
            arcs: arcs,
            completionEffects: completionEffects
        )
    }
}

public extension ArcSpec {
    init(
        id: ArcID,
        title: String,
        targetDurationMinutes: Int,
        situation: String,
        mechanism: String,
        turn: String,
        consequence: String,
        handoff: String,
        beats: [BeatSpec]
    ) {
        self.init(
            id: id,
            title: fixtureCopy("\(id)-title", title),
            targetDurationMinutes: targetDurationMinutes,
            situation: fixtureCopy("\(id)-situation", situation),
            mechanism: fixtureCopy("\(id)-mechanism", mechanism),
            turn: fixtureCopy("\(id)-turn", turn),
            consequence: fixtureCopy("\(id)-consequence", consequence),
            handoff: fixtureCopy("\(id)-handoff", handoff),
            beats: beats
        )
    }
}

public extension NarrativeText {
    init(
        eyebrow: String? = nil,
        heading: String,
        paragraphs: [String],
        actionPrompt: String? = nil
    ) {
        self.init(
            eyebrow: eyebrow.map { fixtureCopy("narrative-eyebrow", $0) },
            heading: fixtureCopy("narrative-heading", heading),
            paragraphs: paragraphs.enumerated().map {
                fixtureCopy("narrative-paragraph-\($0.offset)", $0.element)
            },
            actionPrompt: actionPrompt.map { fixtureCopy("narrative-action-prompt", $0) }
        )
    }
}

public extension AllocateInteractionSpec {
    init(resourceName: String, totalUnits: Int, destinations: [AllocationDestination]) {
        self.init(
            resourceName: fixtureCopy("allocate-resource-name", resourceName),
            totalUnits: totalUnits,
            destinations: destinations
        )
    }
}

public extension InteractionSpec {
    init(
        id: InteractionID,
        prompt: String,
        grammar: Grammar,
        completionEffects: [WorldEffect],
        accessibilityID: AccessibilityID
    ) {
        self.init(
            id: id,
            prompt: fixtureCopy("\(id)-prompt", prompt),
            grammar: grammar,
            completionEffects: completionEffects,
            accessibilityID: accessibilityID
        )
    }
}

public extension SceneSpec {
    init(
        id: SceneID,
        sceneCanvas: SceneCanvasSpec,
        layers: [SceneLayerSpec],
        cameraRail: CameraRail,
        atmosphere: [AtmosphereSpec],
        interactionTargets: [SceneInteractionTargetBinding],
        interactionVisualBinding: SceneInteractionVisualBinding? = nil,
        reduceMotionComposition: ReduceMotionComposition,
        mechanismFocus: String,
        accessibilityID: AccessibilityID
    ) {
        self.init(
            id: id,
            sceneCanvas: sceneCanvas,
            layers: layers,
            cameraRail: cameraRail,
            atmosphere: atmosphere,
            interactionTargets: interactionTargets,
            interactionVisualBinding: interactionVisualBinding,
            reduceMotionComposition: reduceMotionComposition,
            mechanismFocus: fixtureCopy("\(id)-mechanism-focus", mechanismFocus),
            accessibilityID: accessibilityID
        )
    }
}

public extension AccessibilityActionSpec {
    init(kind: AccessibilityActionKind, label: String, token: AccessibilityActionToken) {
        self.init(
            kind: kind,
            label: fixtureCopy("accessibility-action-\(kind.rawValue)-\(token)", label),
            token: token
        )
    }
}

public extension AccessibilityElementSpec {
    init(
        id: String,
        role: AccessibilityRole,
        label: String,
        value: String? = nil,
        hint: String? = nil,
        actions: [AccessibilityActionSpec] = []
    ) {
        self.init(
            id: id,
            role: role,
            label: fixtureCopy("\(id)-label", label),
            value: value.map { fixtureCopy("\(id)-value", $0) },
            hint: hint.map { fixtureCopy("\(id)-hint", $0) },
            actions: actions
        )
    }
}

public extension AccessibilitySpec {
    init(id: AccessibilityID, sceneSummary: String, elements: [AccessibilityElementSpec]) {
        self.init(
            id: id,
            sceneSummary: fixtureCopy("\(id)-scene-summary", sceneSummary),
            elements: elements
        )
    }
}
