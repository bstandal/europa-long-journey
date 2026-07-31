import ContentKit

enum FoundationCatalog {
    static let manifest = LaunchContent.collectionManifest
    static let chapters = manifest.chapters

    /// Stable launch bindings between the cumulative world and its three
    /// included chapters. Keep these IDs beside the prologue mutations so the
    /// visible node, its hit target and the chapter route cannot drift apart.
    static let livingWorldChapters: [LivingWorldChapterPresentationSpec] = [
        LivingWorldChapterPresentationSpec(
            chapterID: "first-farmers",
            worldNodeID: "chapter-first-farmers",
            position: NormalizedPoint(x: 0.22, y: 0.80),
            historicalInvitation: LocalizedStringSpec(
                id: "world-invitation-first-farmers",
                launchEnglish: "Follow the farming frontier"
            )
        ),
        LivingWorldChapterPresentationSpec(
            chapterID: "europe-holds-the-line",
            worldNodeID: "chapter-frontiers-hold",
            position: NormalizedPoint(x: 0.57, y: 0.48),
            historicalInvitation: LocalizedStringSpec(
                id: "world-invitation-frontiers-hold",
                launchEnglish: "Enter the defended frontier"
            )
        ),
        LivingWorldChapterPresentationSpec(
            chapterID: "european-world",
            worldNodeID: "chapter-european-world",
            position: NormalizedPoint(x: 0.77, y: 0.20),
            historicalInvitation: LocalizedStringSpec(
                id: "world-invitation-european-world",
                launchEnglish: "Open the European world"
            )
        ),
    ]

    static let prologueWorldEffects: [WorldEffect] = [
        WorldEffect(
            id: "prologue-reveal-first-farmers",
            mutation: .revealNode(
                WorldNodeBlueprint(
                    id: "chapter-first-farmers",
                    kind: .landscape,
                    form: "farming-frontier",
                    position: NormalizedPoint(x: 0.22, y: 0.80)
                )
            )
        ),
        WorldEffect(
            id: "prologue-reveal-frontiers-hold",
            mutation: .revealNode(
                WorldNodeBlueprint(
                    id: "chapter-frontiers-hold",
                    kind: .frontier,
                    form: "defended-frontier",
                    position: NormalizedPoint(x: 0.57, y: 0.48)
                )
            )
        ),
        WorldEffect(
            id: "prologue-reveal-european-world",
            mutation: .revealNode(
                WorldNodeBlueprint(
                    id: "chapter-european-world",
                    kind: .institution,
                    form: "world-switchboard",
                    position: NormalizedPoint(x: 0.77, y: 0.20)
                )
            )
        ),
        WorldEffect(
            id: "prologue-establish-long-road-a",
            mutation: .establishTrace(
                WorldTraceBlueprint(
                    id: "long-road-a",
                    kind: .transmission,
                    origin: "chapter-first-farmers",
                    destination: "chapter-frontiers-hold"
                )
            )
        ),
        WorldEffect(
            id: "prologue-establish-long-road-b",
            mutation: .establishTrace(
                WorldTraceBlueprint(
                    id: "long-road-b",
                    kind: .transmission,
                    origin: "chapter-frontiers-hold",
                    destination: "chapter-european-world"
                )
            )
        ),
    ]
}
