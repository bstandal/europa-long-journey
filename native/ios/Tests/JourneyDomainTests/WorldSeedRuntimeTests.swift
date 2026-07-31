import ContentKit
import ContentKitTestSupport
import JourneyDomain
import XCTest

final class WorldSeedRuntimeTests: XCTestCase {
    func testRuntimeActivatesSeededTraceAndRevealsSeededNode() throws {
        let seed = runtimeSeed()
        let chapter = runtimeChapter()
        let graph = try WorldGraph.replay(seed: seed, orderedCompletedChapters: [chapter])

        XCTAssertEqual(graph.trace("aegean-farming-route")?.state, .active)
        XCTAssertEqual(graph.node("aegean-settlement")?.visibility, .revealed)
        XCTAssertEqual(graph.appliedEffectIDs, ["effect-crossing", "effect-settlement"])
    }

    func testSeededTraceRemainsDormantBeforeItsHistoricalEstablishment() throws {
        let graph = try WorldGraph(seed: runtimeSeed())
        XCTAssertEqual(graph.trace("aegean-farming-route")?.state, .dormant)
        XCTAssertEqual(graph.node("aegean-settlement")?.visibility, .hidden)
        XCTAssertTrue(graph.appliedEffectIDs.isEmpty)
    }
}

private func runtimeSeed() -> WorldSeedSpec {
    WorldSeedSpec(
        nodes: [
            WorldNodeBlueprint(
                id: "western-anatolia",
                kind: .settlement,
                form: "Hidden western Anatolian shore",
                position: NormalizedPoint(x: 0.72, y: 0.48)
            ),
            WorldNodeBlueprint(
                id: "aegean-settlement",
                kind: .settlement,
                form: "Hidden Aegean shore",
                position: NormalizedPoint(x: 0.51, y: 0.45)
            ),
        ],
        traces: [
            WorldTraceBlueprint(
                id: "aegean-farming-route",
                kind: .seaRoute,
                origin: "western-anatolia",
                destination: "aegean-settlement"
            ),
        ]
    )
}

private func runtimeChapter() -> ChapterSpec {
    ChapterSpec(
        schemaVersion: SchemaVersion(major: 1),
        id: "first-farmers",
        title: "The First Farmers",
        period: "7000–3300 BC",
        arcs: [
            ArcSpec(
                id: "river-to-field",
                title: "River to Field",
                targetDurationMinutes: 10,
                situation: "Farming households reach the Aegean shore.",
                mechanism: "A complete way of life crosses the water.",
                turn: "The household commits to the crossing.",
                consequence: "The route becomes part of Europe's world.",
                handoff: "The household settles the shore.",
                beats: [
                    BeatSpec(
                        id: "crossing",
                        sceneID: "crossing-scene",
                        narrative: NarrativeText(
                            heading: "The household crosses",
                            paragraphs: ["Seed and livestock cross with the household."]
                        ),
                        completionEffects: [
                            WorldEffect(
                                id: "effect-crossing",
                                mutation: .establishTrace(
                                    WorldTraceBlueprint(
                                        id: "aegean-farming-route",
                                        kind: .seaRoute,
                                        origin: "western-anatolia",
                                        destination: "aegean-settlement"
                                    )
                                )
                            ),
                        ],
                        checkpoint: .onExit
                    ),
                ]
            ),
        ],
        completionEffects: [
            WorldEffect(
                id: "effect-settlement",
                mutation: .revealNode(
                    WorldNodeBlueprint(
                        id: "aegean-settlement",
                        kind: .settlement,
                        form: "Timber houses beside stored grain",
                        position: NormalizedPoint(x: 0.51, y: 0.45),
                        attributes: [NamedValue(key: "inhabited", value: .boolean(true))]
                    )
                )
            ),
        ]
    )
}
