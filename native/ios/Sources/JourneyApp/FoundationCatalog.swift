import ContentKit

enum FoundationCatalog {
    static let manifest = LaunchContent.collectionManifest
    static let chapters = manifest.chapters

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
