@testable import ContentKit
import Foundation
@testable import JourneyContent
@testable import JourneyDomain
import XCTest

final class ChapterReviewCoordinatorTests: XCTestCase {
    func testActiveChapterReviewProjectsOnlyExactVisitedScenes() throws {
        let coordinator = try makeCoordinator()
        var state = JourneyContentFixtures.applying(
            try coordinator.beginActions(chapterID: "first-farmers", state: .initial)
        )
        state = JourneyContentFixtures.applying(
            try coordinator.advanceActions(state: state).actions,
            to: state
        )
        XCTAssertEqual(state.activeChapter?.beatID, "first-farmers-beat-two")
        XCTAssertEqual(
            state.activeChapter?.completedBeatReviewRecords.map(\.beatID),
            ["first-farmers-beat-one"]
        )

        let plan = try coordinator.openReviewPlan(
            chapterID: "first-farmers",
            state: state
        )
        XCTAssertEqual(
            plan.action,
            .openBeatReview(
                chapterID: "first-farmers",
                beatID: "first-farmers-beat-one"
            )
        )
        XCTAssertEqual(plan.projection.cursors.map(\.beat.id), ["first-farmers-beat-one"])
        XCTAssertEqual(plan.projection.visitedBeatCount, 1)
        XCTAssertEqual(plan.projection.totalBeatCount, 3)
        XCTAssertNil(plan.projection.previousBeatID)
        XCTAssertNil(plan.projection.nextBeatID)

        let worldBefore = state.world
        state = JourneyContentFixtures.applying([plan.action], to: state)
        XCTAssertEqual(state.route, .chapter("first-farmers"))
        XCTAssertEqual(state.activeChapter?.beatID, "first-farmers-beat-two")
        XCTAssertEqual(state.world, worldBefore)
        XCTAssertEqual(
            try coordinator.currentReviewProjection(state: state),
            plan.projection
        )
        XCTAssertThrowsError(
            try coordinator.openReviewPlan(
                chapterID: "first-farmers",
                state: state
            )
        ) { error in
            XCTAssertEqual(error as? ChapterCoordinatorError, .reviewAlreadyOpen)
        }
    }

    func testCompletedChapterOpensFirstSceneAndMovesThroughArchivedResults() throws {
        let coordinator = try makeCoordinator()
        var state = try completedChapterState(coordinator: coordinator)
        XCTAssertEqual(state.route, .world)
        XCTAssertEqual(
            state.chapterSession("first-farmers")?.completedBeatReviewRecords.map(\.beatID),
            [
                "first-farmers-beat-one",
                "first-farmers-beat-two",
                "first-farmers-beat-three",
            ]
        )

        let worldBefore = state.world
        let routeBefore = state.route
        let plan = try coordinator.openReviewPlan(
            chapterID: "first-farmers",
            state: state
        )
        XCTAssertEqual(plan.projection.selectedIndex, 0)
        XCTAssertEqual(plan.projection.selected.beat.id, "first-farmers-beat-one")
        XCTAssertNil(plan.projection.previousBeatID)
        XCTAssertEqual(plan.projection.nextBeatID, "first-farmers-beat-two")

        state = JourneyContentFixtures.applying([plan.action], to: state)
        let move = try coordinator.moveReviewPlan(
            to: "first-farmers-beat-two",
            state: state
        )
        XCTAssertEqual(move.projection.selectedIndex, 1)
        XCTAssertEqual(move.projection.previousBeatID, "first-farmers-beat-one")
        XCTAssertEqual(move.projection.nextBeatID, "first-farmers-beat-three")
        XCTAssertEqual(move.projection.selected.record.interaction?.phase, .complete)
        state = JourneyContentFixtures.applying([move.action], to: state)

        XCTAssertEqual(state.route, routeBefore)
        XCTAssertEqual(state.world, worldBefore)
        XCTAssertEqual(state.chapterReview?.beatID, "first-farmers-beat-two")
        XCTAssertEqual(
            try coordinator.currentReviewProjection(state: state).selected.beat.id,
            "first-farmers-beat-two"
        )
    }

    func testReviewSurvivesColdRestoreWithoutChangingItsUnderlyingRoute() throws {
        let coordinator = try makeCoordinator()
        var state = try completedChapterState(coordinator: coordinator)
        let plan = try coordinator.openReviewPlan(
            chapterID: "first-farmers",
            beatID: "first-farmers-beat-three",
            state: state
        )
        state = JourneyContentFixtures.applying(
            [plan.action, .setReviewReadingAnchor("review-paragraph-two")],
            to: state
        )
        let encoded = try JSONEncoder().encode(SaveSnapshot(state: state))
        var restored = try JSONDecoder().decode(SaveSnapshot.self, from: encoded).state
        let worldBefore = restored.world

        let effects = JourneyReducer().reduce(state: &restored, action: .launch)

        XCTAssertTrue(effects.isEmpty)
        XCTAssertEqual(restored.route, .world)
        XCTAssertEqual(restored.world, worldBefore)
        XCTAssertEqual(restored.chapterReview?.beatID, "first-farmers-beat-three")
        XCTAssertEqual(restored.chapterReview?.readingAnchor, "review-paragraph-two")
        XCTAssertEqual(
            try coordinator.currentReviewProjection(state: restored).selected.beat.id,
            "first-farmers-beat-three"
        )
    }

    func testColdRestoredCompletedFutureChapterUsesFutureCoordinatorAndFirstRecord()
        throws
    {
        let launchCoordinator = try makeCoordinator()
        let futureCoordinator = try makeFutureCoordinator()
        let chapterID = ChapterID("alpha-deep-dive")
        var state = JourneyContentFixtures.applying(
            try futureCoordinator.beginActions(
                chapterID: chapterID,
                state: .initial
            )
        )
        let beat: BeatSpec = try XCTUnwrap(
            futureCoordinator.repository.chapter(chapterID)?
                .arcs.first?.beats.first
        )
        let interaction: InteractionSpec = try XCTUnwrap(beat.interaction)
        guard case let .trace(configuration) = interaction.grammar else {
            return XCTFail("Future fixture must use the trace grammar")
        }
        let interactionActions: [JourneyAction] = configuration.anchors.map {
                JourneyAction.interact(
                    spec: interaction,
                    action: InteractionAction.trace($0)
                )
            }
        state = JourneyContentFixtures.applying(
            interactionActions,
            to: state
        )
        state = JourneyContentFixtures.applying(
            try futureCoordinator.advanceActions(state: state).actions,
            to: state
        )
        XCTAssertEqual(state.route, JourneyRoute.world)
        XCTAssertEqual(state.completedChapterIDs, [chapterID])

        let plan = try futureCoordinator.openReviewPlan(
            chapterID: chapterID,
            beatID: nil,
            state: state
        )
        XCTAssertEqual(plan.projection.selectedIndex, 0)
        XCTAssertEqual(plan.projection.selected.beat.id, beat.id)
        state = JourneyContentFixtures.applying([plan.action], to: state)
        let restored = try JSONDecoder().decode(
            JourneyState.self,
            from: JSONEncoder().encode(state)
        )

        XCTAssertThrowsError(
            try launchCoordinator.currentReviewProjection(state: restored)
        ) { error in
            XCTAssertEqual(
                error as? ChapterCoordinatorError,
                .reviewUnavailable(chapterID)
            )
        }
        XCTAssertEqual(
            try futureCoordinator.currentReviewProjection(state: restored)
                .selected.beat.id,
            beat.id
        )
    }

    func testCoordinatorRejectsArchivedFrameThatDoesNotMatchVerifiedBeat() throws {
        let coordinator = try makeCoordinator()
        var state = try completedChapterState(coordinator: coordinator)
        var session = try XCTUnwrap(state.chapterSession("first-farmers"))
        let first = try XCTUnwrap(session.completedBeatReviewRecords.first)
        session.completedBeatReviewRecords[0] = CompletedBeatReviewRecord(
            completionContract: first.completionContract,
            sceneVisualSnapshot: SceneVisualSnapshot(
                sceneID: "forged-scene",
                deterministicTick: first.sceneVisualSnapshot.deterministicTick
            ),
            interaction: first.interaction,
            cameraAnchor: first.cameraAnchor,
            readingAnchor: first.readingAnchor
        )
        state.chapterSessions = [session]

        XCTAssertThrowsError(
            try coordinator.openReviewPlan(
                chapterID: "first-farmers",
                state: state
            )
        ) { error in
            XCTAssertEqual(
                error as? ChapterCoordinatorError,
                .reviewRecordMismatch("first-farmers-beat-one")
            )
        }
    }

    private func makeCoordinator() throws -> ChapterCoordinator {
        try ChapterCoordinator(
            repository: ContentRepository(
                packagePayloads: [JourneyContentFixtures.package("essential-free-v1")]
            )
        )
    }

    private func makeFutureCoordinator() throws -> ChapterCoordinator {
        let payload = JourneyContentFixtures.futurePackage()
        let release = Release(
            id: "release-alpha-deep-dive-v1",
            contentID: payload.chapters[0].id.rawValue,
            packageID: payload.packageID,
            version: SchemaVersion(major: 1, minor: 2),
            chapterIDs: payload.chapters.map(\.id),
            maximumInstalledBytes: 420_000_000,
            publishedAtUnixMillis: 1_800_000_000_000,
            minimumRuntime: SchemaVersion(major: 1)
        )
        let verifiedPackage = VerifiedContentPackage(
            manifest: JourneyContentFixtures.signedManifest(
                for: payload,
                packageVersion: release.version,
                minimumRuntime: release.minimumRuntime
            ),
            payload: payload
        )
        return try ChapterCoordinator(
            repository: ContentRepository(
                trustedFutureRelease: release,
                verifiedPackage: verifiedPackage,
                expectedWorldSeed: payload.worldSeed
            )
        )
    }

    private func completedChapterState(
        coordinator: ChapterCoordinator
    ) throws -> JourneyState {
        var state = JourneyContentFixtures.applying(
            try coordinator.beginActions(chapterID: "first-farmers", state: .initial)
        )
        state = JourneyContentFixtures.applying(
            try coordinator.advanceActions(state: state).actions,
            to: state
        )
        let interaction = try XCTUnwrap(
            coordinator.repository.beat("first-farmers-beat-two")?.interaction
        )
        state = JourneyContentFixtures.applying(
            [
                .interact(
                    spec: interaction,
                    action: .trace(NormalizedPoint(x: 0.4, y: 0.5))
                ),
                .interact(
                    spec: interaction,
                    action: .trace(NormalizedPoint(x: 0.6, y: 0.5))
                ),
            ],
            to: state
        )
        state = JourneyContentFixtures.applying(
            try coordinator.advanceActions(state: state).actions,
            to: state
        )
        state = JourneyContentFixtures.applying(
            try coordinator.advanceActions(state: state).actions,
            to: state
        )
        return state
    }
}
