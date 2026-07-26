import ContentKit
import ContentKitTestSupport
import XCTest

final class WorldReplayTests: XCTestCase {
    func testReplayStartsEveryChapterFromTheAuthoredSeedAndIsDeterministic() throws {
        let seed = replaySeed()
        let chapter = replayChapter()
        let first = try WorldReplayValidator.validate(seed: seed, chapters: [chapter])
        let second = try WorldReplayValidator.validate(seed: seed, chapters: [chapter])

        XCTAssertEqual(first, second)
        XCTAssertEqual(first.perChapter.map(\.chapterID), [chapter.id])
        XCTAssertTrue(first.cumulativeDigest.allSatisfy(\.isHexDigit))
        XCTAssertEqual(first.cumulativeDigest.count, 64)
        XCTAssertEqual(
            first.cumulativeDigest,
            "b4634fe480063e75098ded9ea2a5c0d7904217f6890425c9a97435a760811ea5"
        )
    }

    func testReplayRejectsAnEffectWhoseCausalObjectDoesNotExist() {
        let impossible = WorldEffect(
            id: "effect-impossible",
            mutation: .transformNode(
                nodeID: "absent-order",
                form: "A transformed order",
                attributes: []
            )
        )
        XCTAssertThrowsError(
            try WorldReplayValidator.validate(
                seed: replaySeed(),
                chapters: [replayChapter(beatEffect: impossible)]
            )
        ) { error in
            XCTAssertEqual(error as? WorldReplayError, .missingNode("absent-order"))
        }
    }

    func testSeedRejectsATraceWithoutBothEndpoints() {
        let invalid = WorldSeedSpec(
            nodes: [replayNode("aegean-settlement")],
            traces: [replayRoute()]
        )
        XCTAssertThrowsError(try invalid.validate()) { error in
            XCTAssertEqual(error as? WorldReplayError, .missingNode("western-anatolia"))
        }
    }
}

private func replaySeed() -> WorldSeedSpec {
    WorldSeedSpec(
        nodes: [replayNode("western-anatolia"), replayNode("aegean-settlement")],
        traces: [replayRoute()]
    )
}

private func replayNode(_ id: WorldNodeID) -> WorldNodeBlueprint {
    WorldNodeBlueprint(
        id: id,
        kind: .settlement,
        form: "Hidden world anchor \(id.rawValue)",
        position: id == "western-anatolia"
            ? NormalizedPoint(x: 0.72, y: 0.48)
            : NormalizedPoint(x: 0.51, y: 0.45)
    )
}

private func replayRoute() -> WorldTraceBlueprint {
    WorldTraceBlueprint(
        id: "aegean-farming-route",
        kind: .seaRoute,
        origin: "western-anatolia",
        destination: "aegean-settlement"
    )
}

private func replayChapter(beatEffect: WorldEffect? = nil) -> ChapterSpec {
    let crossing = beatEffect ?? WorldEffect(
        id: "effect-crossing",
        mutation: .establishTrace(replayRoute())
    )
    let settlement = WorldEffect(
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
    )
    return ChapterSpec(
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
                mechanism: "Seed, animals and learned routines move with people.",
                turn: "A harvest must outlast the season.",
                consequence: "Fields and permanent houses remake the landscape.",
                handoff: "Stored futures become an inheritance.",
                beats: [
                    BeatSpec(
                        id: "crossing",
                        sceneID: "crossing-scene",
                        narrative: NarrativeText(
                            heading: "The household crosses",
                            paragraphs: ["Seed and livestock move with the people who know how to use them."]
                        ),
                        completionEffects: [crossing],
                        checkpoint: .onExit
                    ),
                ]
            ),
        ],
        completionEffects: [settlement]
    )
}
