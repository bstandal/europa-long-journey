import ContentKit
import Foundation
@_spi(JourneyContent) @testable import JourneyDomain
import XCTest

final class ChapterReviewStateTests: XCTestCase {
    func testSealedReviewArchiveInventoryAcceptsExactCanonicalArchive() {
        let records = [
            documentaryReviewRecord(beatID: "first", absoluteBeatIndex: 0),
            documentaryReviewRecord(
                beatID: "second",
                beatIndex: 1,
                absoluteBeatIndex: 1
            ),
        ]
        let session = ChapterSession(
            chapterID: "review-chapter",
            packageID: "review-package",
            contentVersion: SchemaVersion(major: 1),
            completedBeatIDs: ["first", "second"],
            completedBeatReviewRecords: records
        )

        XCTAssertTrue(session.hasSealedReviewArchiveForCompletedBeats)
    }

    func testSealedReviewArchiveInventoryRejectsEmptyAndPartialArchives() {
        XCTAssertFalse(
            ChapterSession(
                chapterID: "review-chapter",
                packageID: "review-package",
                contentVersion: SchemaVersion(major: 1)
            ).hasSealedReviewArchiveForCompletedBeats
        )

        let partial = ChapterSession(
            chapterID: "review-chapter",
            packageID: "review-package",
            contentVersion: SchemaVersion(major: 1),
            completedBeatIDs: ["first", "second"],
            completedBeatReviewRecords: [
                documentaryReviewRecord(beatID: "first", absoluteBeatIndex: 0)
            ]
        )
        XCTAssertFalse(partial.hasSealedReviewArchiveForCompletedBeats)
    }

    func testSealedReviewArchiveInventoryRejectsDuplicateAndMismatchedIdentities() {
        let record = documentaryReviewRecord(beatID: "first", absoluteBeatIndex: 0)
        var duplicate = ChapterSession(
            chapterID: "review-chapter",
            packageID: "review-package",
            contentVersion: SchemaVersion(major: 1),
            completedBeatIDs: ["first"],
            completedBeatReviewRecords: [record]
        )
        duplicate.completedBeatReviewRecords = [record, record]
        XCTAssertFalse(duplicate.hasSealedReviewArchiveForCompletedBeats)

        let wrongChapter = ChapterSession(
            chapterID: "review-chapter",
            packageID: "review-package",
            contentVersion: SchemaVersion(major: 1),
            completedBeatIDs: ["first"],
            completedBeatReviewRecords: [
                documentaryReviewRecord(
                    beatID: "first",
                    absoluteBeatIndex: 0,
                    chapterID: "another-chapter"
                )
            ]
        )
        XCTAssertFalse(wrongChapter.hasSealedReviewArchiveForCompletedBeats)
    }

    func testSealedReviewArchiveInventoryRejectsInvalidFormatAndSeal() throws {
        let valid = documentaryReviewRecord(beatID: "first", absoluteBeatIndex: 0)
        let wrongFormat = CompletedBeatReviewRecord(
            completionContract: valid.completionContract,
            sceneVisualSnapshot: valid.sceneVisualSnapshot,
            interaction: nil,
            cameraAnchor: valid.cameraAnchor,
            readingAnchor: valid.readingAnchor,
            formatVersion: CompletedBeatReviewRecord.currentFormatVersion + 1
        )
        XCTAssertFalse(
            reviewSession(record: wrongFormat)
                .hasSealedReviewArchiveForCompletedBeats
        )

        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(valid))
                as? [String: Any]
        )
        var contract = try XCTUnwrap(
            object["completionContract"] as? [String: Any]
        )
        contract["authoritySeal"] = Data([0]).base64EncodedString()
        object["completionContract"] = contract
        let invalidSeal = try JSONDecoder().decode(
            CompletedBeatReviewRecord.self,
            from: JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        )
        XCTAssertFalse(
            reviewSession(record: invalidSeal)
                .hasSealedReviewArchiveForCompletedBeats
        )
    }

    func testSealedReviewArchiveInventoryRejectsNoncontiguousAbsoluteIndices() {
        let session = ChapterSession(
            chapterID: "review-chapter",
            packageID: "review-package",
            contentVersion: SchemaVersion(major: 1),
            completedBeatIDs: ["first", "third"],
            completedBeatReviewRecords: [
                documentaryReviewRecord(beatID: "first", absoluteBeatIndex: 0),
                documentaryReviewRecord(
                    beatID: "third",
                    beatIndex: 2,
                    absoluteBeatIndex: 2
                ),
            ]
        )

        XCTAssertFalse(session.hasSealedReviewArchiveForCompletedBeats)
    }

    func testReviewTerminalPredicateRejectsNoncanonicalRenderState() {
        var assembleProgress = AssembleProgress(
            placements: [
                AssemblyPlacement(
                    componentID: "charter",
                    slotID: "law"
                ),
                AssemblyPlacement(
                    componentID: "council",
                    slotID: "office"
                ),
            ]
        )
        assembleProgress.placements.reverse()
        var assemble = InteractionRuntimeState(spec: Fixtures.assemble)
        assemble.phase = .complete
        assemble.progress = .assemble(assembleProgress)
        XCTAssertFalse(
            InteractionReducer.terminalState(
                assemble,
                matches: Fixtures.assemble
            )
        )

        var unsortedPressure = PressureProgress(
            values: [
                PressureValue(forceID: "attack", magnitude: 0.5),
                PressureValue(forceID: "defence", magnitude: 0.5),
            ],
            stableMillis: 500
        )
        unsortedPressure.values.reverse()
        XCTAssertFalse(
            unsortedPressure.values.map(\.forceID)
                == unsortedPressure.values.map(\.forceID).sorted()
        )

        for progress in [
            unsortedPressure,
            PressureProgress(
                values: [
                    PressureValue(forceID: "attack", magnitude: 0.5),
                    PressureValue(forceID: "defence", magnitude: 0)
                ],
                stableMillis: 500
            ),
            PressureProgress(
                values: [
                    PressureValue(forceID: "attack", magnitude: 0.5),
                    PressureValue(forceID: "defence", magnitude: 0.5)
                ],
                stableMillis: 1_500
            ),
        ] {
            var pressure = InteractionRuntimeState(spec: Fixtures.pressure)
            pressure.phase = .complete
            pressure.progress = .pressure(progress)
            XCTAssertFalse(
                InteractionReducer.terminalState(
                    pressure,
                    matches: Fixtures.pressure
                )
            )
        }
    }

    func testEveryInteractionGrammarArchivesItsExactTerminalReviewState() throws {
        let cases: [(InteractionSpec, [InteractionAction])] = [
            (
                Fixtures.trace,
                [
                    .trace(NormalizedPoint(x: 0, y: 0)),
                    .trace(NormalizedPoint(x: 1, y: 1)),
                ]
            ),
            (
                Fixtures.allocate,
                [
                    .allocate(destinationID: "field", units: 3),
                    .allocate(destinationID: "reserve", units: 1),
                    .commitAllocation,
                ]
            ),
            (
                Fixtures.assemble,
                [
                    .place(componentID: "charter", slotID: "law"),
                    .place(componentID: "council", slotID: "office"),
                ]
            ),
            (
                Fixtures.pressure,
                [
                    .setPressure(forceID: "defence", magnitude: 0.5),
                    .advancePressure(elapsedMillis: 500),
                ]
            ),
            (
                Fixtures.transform,
                [
                    .transform(controlID: "heat", amount: 0.75),
                    .transform(controlID: "shape", amount: 1),
                ]
            ),
        ]

        for (spec, actions) in cases {
            let contract = interactionContract(spec)
            let snapshot = SceneVisualSnapshot(
                sceneID: SceneID("scene-\(spec.id.rawValue)"),
                deterministicTick: 9_000
            )
            var state = JourneyState(
                route: .chapter("review-chapter"),
                activeChapter: ChapterSession(
                    chapterID: "review-chapter",
                    packageID: "review-package",
                    contentVersion: SchemaVersion(major: 1),
                    arcID: "review-arc",
                    beatID: BeatID("beat-\(spec.id.rawValue)"),
                    beatCompletionContract: contract,
                    sceneVisualSnapshot: snapshot,
                    interaction: InteractionRuntimeState(spec: spec),
                    cameraAnchor: 0.625,
                    readingAnchor: "paragraph-two"
                )
            )
            let reducer = JourneyReducer()
            for action in actions {
                let effects = reducer.reduce(
                    state: &state,
                    action: .interact(spec: spec, action: action)
                )
                XCTAssertFalse(effects.containsRejection, "\(spec.id)")
            }
            let terminal = try XCTUnwrap(state.activeChapter?.interaction)
            XCTAssertEqual(terminal.phase, .complete, "\(spec.id)")

            let effects = reducer.reduce(
                state: &state,
                action: .completeBeat(
                    arcID: contract.arcID,
                    beatID: contract.beatID
                )
            )

            XCTAssertFalse(effects.containsRejection, "\(spec.id)")
            let record = try XCTUnwrap(
                state.activeChapter?.reviewRecord(for: contract.beatID)
            )
            XCTAssertEqual(record.completionContract, contract, "\(spec.id)")
            XCTAssertEqual(record.sceneVisualSnapshot, snapshot, "\(spec.id)")
            XCTAssertEqual(record.interaction, terminal, "\(spec.id)")
            XCTAssertEqual(record.cameraAnchor, 0.625, "\(spec.id)")
            XCTAssertEqual(record.readingAnchor, "paragraph-two", "\(spec.id)")
        }
    }

    func testDocumentaryArchiveAndReviewNeverMoveTheCausalRouteOrWorld() throws {
        let first = documentaryContract(beatID: "first", absoluteBeatIndex: 0)
        let second = documentaryContract(beatID: "second", beatIndex: 1, absoluteBeatIndex: 1)
        let snapshot = SceneVisualSnapshot(sceneID: "scene-first", deterministicTick: 17)
        var state = JourneyState(
            route: .chapter("review-chapter"),
            activeChapter: ChapterSession(
                chapterID: "review-chapter",
                packageID: "review-package",
                contentVersion: SchemaVersion(major: 1),
                arcID: "review-arc",
                beatID: "first",
                beatCompletionContract: first,
                sceneVisualSnapshot: snapshot,
                cameraAnchor: 0.4,
                readingAnchor: "first-paragraph",
                narration: NarrationCursor(
                    cueID: "first-narration",
                    sampleOffset: 48_000,
                    isEnabled: true,
                    isPlaying: true
                )
            )
        )
        let reducer = JourneyReducer()

        XCTAssertFalse(
            reducer.reduce(state: &state, action: .completeDocumentaryBeat(first))
                .containsRejection
        )
        XCTAssertEqual(
            state.activeChapter?.reviewRecord(for: "first")?.sceneVisualSnapshot,
            snapshot
        )
        XCTAssertFalse(
            reducer.reduce(state: &state, action: .enterAuthoredBeat(second))
                .containsRejection
        )
        XCTAssertNil(state.activeChapter?.readingAnchor)
        XCTAssertEqual(state.activeChapter?.completedBeatReviewRecords.count, 1)

        let routeBeforeReview = state.route
        let worldBeforeReview = state.world
        let causalBeatBeforeReview = state.activeChapter?.beatID
        let effects = reducer.reduce(
            state: &state,
            action: .openBeatReview(chapterID: "review-chapter", beatID: "first")
        )
        XCTAssertEqual(effects, [.checkpoint(.reviewChanged)])
        XCTAssertEqual(state.route, routeBeforeReview)
        XCTAssertEqual(state.world, worldBeforeReview)
        XCTAssertEqual(state.activeChapter?.beatID, causalBeatBeforeReview)
        XCTAssertFalse(state.activeChapter?.narration.isPlaying ?? true)

        let duringReview = state
        XCTAssertEqual(
            reducer.reduce(
                state: &state,
                action: .completeDocumentaryBeat(second)
            ),
            [.rejected("Close review before changing the causal chapter state")]
        )
        XCTAssertEqual(state, duringReview)

        XCTAssertEqual(
            reducer.reduce(
                state: &state,
                action: .setReviewReadingAnchor("review-paragraph")
            ),
            [.checkpoint(.reviewChanged)]
        )
        XCTAssertEqual(state.chapterReview?.readingAnchor, "review-paragraph")
        XCTAssertNil(state.activeChapter?.readingAnchor)
        XCTAssertEqual(
            reducer.reduce(state: &state, action: .closeBeatReview),
            [.checkpoint(.reviewChanged)]
        )
        XCTAssertNil(state.chapterReview)
        XCTAssertEqual(state.route, routeBeforeReview)
        XCTAssertEqual(state.world, worldBeforeReview)
    }

    func testReviewRequiresAnArchivedRecordAndCompletedChapterForWorldEntry() {
        let session = ChapterSession(
            chapterID: "review-chapter",
            packageID: "review-package",
            contentVersion: SchemaVersion(major: 1),
            arcID: "review-arc",
            beatID: "first",
            completedBeatIDs: ["first"]
        )
        let reducer = JourneyReducer()
        var chapterState = JourneyState(
            route: .chapter("review-chapter"),
            activeChapter: session
        )
        let before = chapterState
        XCTAssertEqual(
            reducer.reduce(
                state: &chapterState,
                action: .openBeatReview(chapterID: "review-chapter", beatID: "first")
            ),
            [.rejected("Review requires an exact completed scene record")]
        )
        XCTAssertEqual(chapterState, before)

        var worldState = JourneyState(route: .world, chapterSessions: [session])
        XCTAssertEqual(
            reducer.reduce(
                state: &worldState,
                action: .openBeatReview(chapterID: "review-chapter", beatID: "first")
            ),
            [.rejected("Review requires an exact completed scene record")]
        )
    }

    func testSchemaThreeDecodesIntoSchemaFourWithoutInventingReviewRecords() throws {
        let current = JourneyState(
            route: .world,
            activeChapter: ChapterSession(
                chapterID: "review-chapter",
                packageID: "review-package",
                contentVersion: SchemaVersion(major: 1),
                arcID: "review-arc",
                beatID: "legacy-beat",
                completedBeatIDs: ["legacy-beat"]
            ),
            completedChapterIDs: ["review-chapter"]
        )
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(current))
                as? [String: Any]
        )
        object["stateSchemaVersion"] = 3
        object.removeValue(forKey: "chapterReview")
        var sessions = try XCTUnwrap(object["chapterSessions"] as? [[String: Any]])
        sessions[0].removeValue(forKey: "completedBeatReviewRecords")
        object["chapterSessions"] = sessions

        let decoded = try JSONDecoder().decode(
            JourneyState.self,
            from: JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        )

        XCTAssertEqual(decoded.stateSchemaVersion, 4)
        XCTAssertNil(decoded.chapterReview)
        XCTAssertEqual(decoded.route, .world)
        XCTAssertEqual(decoded.completedChapterIDs, ["review-chapter"])
        XCTAssertEqual(decoded.chapterSession("review-chapter")?.completedBeatIDs, ["legacy-beat"])
        XCTAssertTrue(
            decoded.chapterSession("review-chapter")?.completedBeatReviewRecords.isEmpty == true
        )
    }

    func testReviewReturnAudioAuthorizationIsProcessLocalAndSingleUse() throws {
        let reviewed = documentaryContract(
            beatID: "reviewed",
            absoluteBeatIndex: 0
        )
        let record = CompletedBeatReviewRecord(
            completionContract: reviewed,
            sceneVisualSnapshot: SceneVisualSnapshot(
                sceneID: "scene-reviewed",
                deterministicTick: 41
            ),
            interaction: nil,
            cameraAnchor: 0.5,
            readingAnchor: "reviewed-paragraph"
        )
        let openReview = JourneyState(
            route: .chapter("review-chapter"),
            chapterReview: ChapterReviewState(
                chapterID: "review-chapter",
                packageID: "review-package",
                contentVersion: SchemaVersion(major: 1),
                beatID: "reviewed"
            ),
            activeChapter: ChapterSession(
                chapterID: "review-chapter",
                packageID: "review-package",
                contentVersion: SchemaVersion(major: 1),
                arcID: "review-arc",
                beatID: "current",
                completedBeatIDs: ["reviewed"],
                completedBeatReviewRecords: [record]
            )
        )

        var sameProcessAuthorization =
            ChapterReviewReturnAudioAuthorization()
        XCTAssertTrue(
            sameProcessAuthorization.authorizeReturnFromReview(
                in: openReview
            )
        )
        var closedReview = openReview
        XCTAssertEqual(
            JourneyReducer().reduce(
                state: &closedReview,
                action: .closeBeatReview
            ),
            [.checkpoint(.reviewChanged)]
        )
        XCTAssertEqual(
            sameProcessAuthorization.consumeReturnGrant(in: closedReview),
            "review-chapter"
        )
        XCTAssertNil(
            sameProcessAuthorization.consumeReturnGrant(in: closedReview)
        )

        let restoredOpenReview = try JSONDecoder().decode(
            JourneyState.self,
            from: JSONEncoder().encode(openReview)
        )
        var restoredClosedReview = restoredOpenReview
        _ = JourneyReducer().reduce(
            state: &restoredClosedReview,
            action: .closeBeatReview
        )
        var restoredProcessAuthorization =
            ChapterReviewReturnAudioAuthorization()
        XCTAssertNil(
            restoredProcessAuthorization.consumeReturnGrant(
                in: restoredClosedReview
            )
        )
    }

    func testWorldReviewCannotAuthorizeAnActiveSceneAudioReturn() {
        var authorization = ChapterReviewReturnAudioAuthorization()
        let state = JourneyState(
            route: .world,
            chapterReview: ChapterReviewState(
                chapterID: "review-chapter",
                packageID: "review-package",
                contentVersion: SchemaVersion(major: 1),
                beatID: "reviewed"
            )
        )

        XCTAssertFalse(
            authorization.authorizeReturnFromReview(in: state)
        )
    }

    func testNonFinitePrologueProgressIsRejectedWithoutMutation() {
        let reducer = JourneyReducer()
        for value in [Double.nan, Double.infinity, -Double.infinity] {
            var state = JourneyState.initial
            let before = state
            XCTAssertEqual(
                reducer.reduce(state: &state, action: .updatePrologueTrace(value)),
                [.rejected("Prologue trace progress must be finite")]
            )
            XCTAssertEqual(state, before)
        }
    }

    private func interactionContract(_ interaction: InteractionSpec) -> BeatCompletionContract {
        BeatCompletionContract(
            packageID: "review-package",
            contentVersion: SchemaVersion(major: 1),
            chapterID: "review-chapter",
            arcID: "review-arc",
            beatID: BeatID("beat-\(interaction.id.rawValue)"),
            arcIndex: 0,
            beatIndex: 0,
            absoluteBeatIndex: 0,
            mode: .interaction(
                id: interaction.id,
                effects: interaction.completionEffects
            )
        )
    }

    private func documentaryContract(
        beatID: BeatID,
        beatIndex: Int = 0,
        absoluteBeatIndex: Int,
        chapterID: ChapterID = "review-chapter"
    ) -> BeatCompletionContract {
        BeatCompletionContract(
            packageID: "review-package",
            contentVersion: SchemaVersion(major: 1),
            chapterID: chapterID,
            arcID: "review-arc",
            beatID: beatID,
            arcIndex: 0,
            beatIndex: beatIndex,
            absoluteBeatIndex: absoluteBeatIndex,
            mode: .documentary(effects: [])
        )
    }

    private func documentaryReviewRecord(
        beatID: BeatID,
        beatIndex: Int = 0,
        absoluteBeatIndex: Int,
        chapterID: ChapterID = "review-chapter"
    ) -> CompletedBeatReviewRecord {
        CompletedBeatReviewRecord(
            completionContract: documentaryContract(
                beatID: beatID,
                beatIndex: beatIndex,
                absoluteBeatIndex: absoluteBeatIndex,
                chapterID: chapterID
            ),
            sceneVisualSnapshot: SceneVisualSnapshot(
                sceneID: SceneID("scene-\(beatID.rawValue)"),
                deterministicTick: UInt64(absoluteBeatIndex)
            ),
            interaction: nil,
            cameraAnchor: 0.5,
            readingAnchor: nil
        )
    }

    private func reviewSession(record: CompletedBeatReviewRecord) -> ChapterSession {
        ChapterSession(
            chapterID: "review-chapter",
            packageID: "review-package",
            contentVersion: SchemaVersion(major: 1),
            completedBeatIDs: [record.beatID],
            completedBeatReviewRecords: [record]
        )
    }
}

final class AllocationCanonicalQueryTests: XCTestCase {
    func testEveryHarvestDistributionUsesOneMaximumAndCommitAuthority() throws {
        let configuration = AllocateInteractionSpec(
            resourceName: "grain",
            totalUnits: 12,
            destinations: [
                AllocationDestination(id: "food", minimumUnits: 4),
                AllocationDestination(id: "reserve", minimumUnits: 2),
                AllocationDestination(id: "seed", minimumUnits: 3),
            ]
        )
        let spec = InteractionSpec(
            id: "harvest-allocation",
            prompt: "Divide the harvest",
            grammar: .allocate(configuration),
            completionEffects: [],
            accessibilityID: "harvest-allocation-accessibility"
        )

        for food in 0 ... 12 {
            for reserve in 0 ... 12 {
                for seed in 0 ... 12 {
                    let progress = AllocateProgress(
                        allocations: [
                            AllocationValue(destinationID: "food", units: food),
                            AllocationValue(destinationID: "reserve", units: reserve),
                            AllocationValue(destinationID: "seed", units: seed),
                        ]
                    )
                    let total = food + reserve + seed
                    let expectedCommit = total == 12
                        && food >= 4 && reserve >= 2 && seed >= 3
                    XCTAssertEqual(
                        InteractionReducer.allocationCanCommit(
                            progress: progress,
                            configuration: configuration
                        ),
                        expectedCommit,
                        "\(food),\(reserve),\(seed)"
                    )
                    for (id, current, others) in [
                        ("food", food, reserve + seed),
                        ("reserve", reserve, food + seed),
                        ("seed", seed, food + reserve),
                    ] {
                        let expectedMaximum = total <= 12 ? 12 - others : nil
                        XCTAssertEqual(
                            InteractionReducer.maximumAllocatableUnits(
                                for: id,
                                progress: progress,
                                configuration: configuration
                            ),
                            expectedMaximum,
                            "\(id): \(food),\(reserve),\(seed), current \(current)"
                        )
                    }
                    if total <= 12 {
                        var runtime = InteractionRuntimeState(spec: spec)
                        runtime.phase = .active
                        runtime.progress = .allocate(progress)
                        _ = try InteractionReducer.reduce(
                            state: &runtime,
                            spec: spec,
                            action: .commitAllocation
                        )
                        XCTAssertEqual(
                            runtime.phase == .complete,
                            expectedCommit,
                            "reducer: \(food),\(reserve),\(seed)"
                        )
                    }
                }
            }
        }
    }

    func testMalformedAllocationProgressFailsClosed() {
        let configuration = AllocateInteractionSpec(
            resourceName: "grain",
            totalUnits: 4,
            destinations: [
                AllocationDestination(id: "food", minimumUnits: 1),
                AllocationDestination(id: "seed", minimumUnits: 1),
            ]
        )
        let malformed = AllocateProgress(
            allocations: [AllocationValue(destinationID: "food", units: 1)]
        )
        XCTAssertNil(
            InteractionReducer.maximumAllocatableUnits(
                for: "food",
                progress: malformed,
                configuration: configuration
            )
        )
        XCTAssertFalse(
            InteractionReducer.allocationCanCommit(
                progress: malformed,
                configuration: configuration
            )
        )
    }
}

private extension Array where Element == JourneyEffect {
    var containsRejection: Bool {
        contains { effect in
            if case .rejected = effect { return true }
            return false
        }
    }
}
