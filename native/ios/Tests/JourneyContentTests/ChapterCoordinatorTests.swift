import ContentKit
@testable import JourneyDomain
@testable import JourneyContent
import XCTest

final class ChapterCoordinatorTests: XCTestCase {
    func testBeginActionsResolveTheExactFirstCursorWithoutHardcodedRuntimeContent() throws {
        let coordinator = try makeCoordinator(includePaidPackage: true)

        let freeActions = try coordinator.beginActions(
            chapterID: "first-farmers",
            state: .initial
        )
        XCTAssertEqual(freeActions.count, 2)
        guard case .beginAuthoredChapter = freeActions[0] else {
            return XCTFail("Expected a repository-bound chapter opening")
        }
        guard case .activateScene = freeActions[1] else {
            return XCTFail("Expected the first scene to become durable before presentation")
        }
        let freeState = JourneyContentFixtures.applying(freeActions)
        let freeCursor = try coordinator.currentCursor(state: freeState)
        XCTAssertEqual(freeCursor.arcIndex, 0)
        XCTAssertEqual(freeCursor.beatIndex, 0)
        XCTAssertEqual(freeCursor.scene.id, "first-farmers-scene-one")
        XCTAssertEqual(
            freeCursor.accessibility.id,
            "accessibility-first-farmers-beat-one"
        )

        let paidActions = try coordinator.beginActions(
            chapterID: "steppe-comes-west",
            state: .initial
        )
        XCTAssertEqual(paidActions.count, 3)
        guard case .beginAuthoredChapter = paidActions[0] else {
            return XCTFail("Expected a repository-bound chapter opening")
        }
        guard case .activateScene = paidActions[1] else {
            return XCTFail("Expected repository-bound scene activation")
        }
        guard case let .beginInteraction(interaction) = paidActions[2] else {
            return XCTFail("Expected the authored first-beat interaction")
        }
        XCTAssertEqual(interaction.id, "steppe-comes-west-interaction")
    }

    func testResumeSelectsTheSavedCausalPointWithoutResettingItsState() throws {
        let coordinator = try makeCoordinator()
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
        let tickAction = try coordinator.sceneTickAction(
            deterministicTick: 714,
            state: state
        )
        state = JourneyContentFixtures.applying(
            [
                .interact(
                    spec: interaction,
                    action: .trace(NormalizedPoint(x: 0.4, y: 0.5))
                ),
                tickAction,
                .setCameraAnchor(0.63),
                .setReadingAnchor("paragraph-two"),
                .setNarration(
                    cueID: "saved-cue",
                    sampleOffset: 91_337,
                    enabled: true,
                    playing: true
                ),
                .showWorld,
            ],
            to: state
        )
        let savedSession = try XCTUnwrap(state.chapterSession("first-farmers"))

        let actions = try coordinator.resumeActions(
            chapterID: "first-farmers",
            state: state
        )
        XCTAssertEqual(
            actions,
            [
                .selectChapter(
                    chapterID: "first-farmers",
                    packageID: "essential-free-v1",
                    contentVersion: SchemaVersion(major: 1)
                ),
            ]
        )
        state = JourneyContentFixtures.applying(actions, to: state)

        XCTAssertEqual(state.chapterSession("first-farmers"), savedSession)
        let cursor = try coordinator.currentCursor(state: state)
        XCTAssertEqual(cursor.beat.id, "first-farmers-beat-two")
        XCTAssertEqual(cursor.scene.id, "first-farmers-scene-two")
        XCTAssertEqual(state.activeChapter?.cameraAnchor, 0.63)
        XCTAssertEqual(state.activeChapter?.narration.sampleOffset, 91_337)
        guard case let .trace(progress) = state.activeChapter?.interaction?.progress else {
            return XCTFail("Expected preserved trace progress")
        }
        XCTAssertEqual(progress.reachedAnchorCount, 1)
    }

    func testResumeRepairsOnlyTheCrashBoundaryBeforeInteractionStart() throws {
        let coordinator = try makeCoordinator()
        var state = try stateBeforeFirstInteraction(coordinator: coordinator)
        state = JourneyContentFixtures.applying([.showWorld], to: state)

        let actions = try coordinator.resumeActions(
            chapterID: "first-farmers",
            state: state
        )
        XCTAssertEqual(actions.count, 2)
        guard case .selectChapter = actions[0],
              case .beginInteraction = actions[1] else {
            return XCTFail("Resume must start the exact authored interaction")
        }
        state = JourneyContentFixtures.applying(actions, to: state)
        XCTAssertEqual(state.activeChapter?.interaction?.phase, .ready)
        XCTAssertEqual(
            state.activeChapter?.interaction?.interactionID,
            "first-farmers-interaction"
        )
    }

    func testResumeFillsAnExactEmptySessionAndActivatesItsFirstScene() throws {
        let coordinator = try makeCoordinator()
        var state = JourneyContentFixtures.applying([
            .selectChapter(
                chapterID: "first-farmers",
                packageID: "essential-free-v1",
                contentVersion: SchemaVersion(major: 1)
            ),
            .showWorld,
        ])

        let actions = try coordinator.resumeActions(
            chapterID: "first-farmers",
            state: state
        )
        XCTAssertEqual(actions.count, 2)
        guard case .beginAuthoredChapter = actions[0],
              case .activateScene = actions[1] else {
            return XCTFail("The empty durable shell must resume through sealed authored actions")
        }
        state = JourneyContentFixtures.applying(actions, to: state)

        let cursor = try coordinator.currentCursor(state: state)
        XCTAssertEqual(cursor.beat.id, "first-farmers-beat-one")
        XCTAssertEqual(
            state.activeChapter?.sceneVisualSnapshot,
            SceneVisualSnapshot(
                sceneID: "first-farmers-scene-one",
                deterministicTick: 0
            )
        )
    }

    func testAdvanceRefusesMissingReadyAndActiveInteractions() throws {
        let coordinator = try makeCoordinator()
        var missingState = try stateBeforeFirstInteraction(coordinator: coordinator)
        missingState.activeChapter?.beatCompletionContract = nil
        XCTAssertThrowsError(try coordinator.advanceActions(state: missingState)) { error in
            XCTAssertEqual(
                error as? ChapterCoordinatorError,
                .beatCompletionContractMismatch("first-farmers-beat-two")
            )
        }

        var readyState = try stateBeforeFirstInteraction(coordinator: coordinator)
        let readyInteraction = try XCTUnwrap(
            coordinator.repository.beat("first-farmers-beat-two")?.interaction
        )
        readyState = JourneyContentFixtures.applying(
            [.beginInteraction(readyInteraction)],
            to: readyState
        )
        assertIncompleteInteraction(coordinator: coordinator, state: readyState)

        let interaction = try XCTUnwrap(readyState.activeChapter?.interaction).interactionID
        let spec = try XCTUnwrap(coordinator.repository.interaction(interaction))
        readyState = JourneyContentFixtures.applying(
            [.interact(spec: spec, action: .begin)],
            to: readyState
        )
        assertIncompleteInteraction(coordinator: coordinator, state: readyState)
    }

    func testCompletedInteractionAdvancesAcrossArcAndFinalBeatCompletesChapter() throws {
        let coordinator = try makeCoordinator()
        var state = try stateAtInteractiveBeat(coordinator: coordinator)
        state = try completeCurrentTrace(coordinator: coordinator, state: state)

        let acrossArc = try coordinator.advanceActions(state: state)
        XCTAssertEqual(acrossArc.actions.count, 4)
        guard case .completeBeat(
            arcID: "first-farmers-arc-one",
            beatID: "first-farmers-beat-two"
        ) = acrossArc.actions[0],
        case let .completeAuthoredArc(firstArcContract) = acrossArc.actions[1],
        case .enterAuthoredBeat = acrossArc.actions[2],
        case .activateScene = acrossArc.actions[3] else {
            return XCTFail("Expected interaction completion followed by an authored arc transition")
        }
        XCTAssertEqual(firstArcContract.arcID, "first-farmers-arc-one")
        XCTAssertEqual(
            acrossArc.destination,
            .beat(
                chapterID: "first-farmers",
                arcID: "first-farmers-arc-two",
                beatID: "first-farmers-beat-three"
            )
        )
        XCTAssertTrue(acrossArc.chapterCompletionEffects.isEmpty)
        state = JourneyContentFixtures.applying(acrossArc.actions, to: state)

        XCTAssertEqual(
            state.activeChapter?.completedBeatIDs,
            ["first-farmers-beat-one", "first-farmers-beat-two"]
        )
        XCTAssertEqual(
            state.activeChapter?.completedArcIDs,
            ["first-farmers-arc-one"]
        )
        XCTAssertEqual(
            try coordinator.currentCursor(state: state).beat.id,
            "first-farmers-beat-three"
        )

        let final = try coordinator.advanceActions(state: state)
        let expectedEffects = try XCTUnwrap(
            coordinator.repository.chapter("first-farmers")
        ).completionEffects
        XCTAssertEqual(final.chapterCompletionEffects, expectedEffects)
        XCTAssertEqual(
            final.destination,
            .world(completedChapterID: "first-farmers")
        )
        XCTAssertEqual(final.actions.count, 3)
        guard case .completeDocumentaryBeat = final.actions[0],
              case let .completeAuthoredArc(finalArcContract) = final.actions[1],
              case let .completeAuthoredChapter(completionContract) = final.actions[2] else {
            return XCTFail("Expected atomic documentary completion before chapter completion")
        }
        XCTAssertEqual(finalArcContract.arcID, "first-farmers-arc-two")
        XCTAssertEqual(completionContract.completionEffects, expectedEffects)
        state = JourneyContentFixtures.applying(final.actions, to: state)
        XCTAssertEqual(state.route, .world)
        XCTAssertTrue(state.completedChapterIDs.contains("first-farmers"))
    }

    func testAdvancePlansRecoverDeterministicallyAtEveryPersistedActionBoundary() throws {
        let coordinator = try makeCoordinator()
        let interactionComplete = try completeCurrentTrace(
            coordinator: coordinator,
            state: stateAtInteractiveBeat(coordinator: coordinator)
        )
        let acrossArc = try coordinator.advanceActions(state: interactionComplete)

        for prefixLength in 0 ..< acrossArc.actions.count {
            var interrupted = JourneyContentFixtures.applying(
                Array(acrossArc.actions.prefix(prefixLength)),
                to: interactionComplete
            )
            interrupted = JourneyContentFixtures.applying(
                try coordinator.resumeActions(
                    chapterID: "first-farmers",
                    state: interrupted
                ),
                to: interrupted
            )
            let resumedCursor = try coordinator.currentCursor(state: interrupted)
            let recovered: JourneyState
            if resumedCursor.beat.id == "first-farmers-beat-three" {
                recovered = interrupted
            } else {
                let recovery = try coordinator.advanceActions(state: interrupted)
                recovered = JourneyContentFixtures.applying(
                    recovery.actions,
                    to: interrupted
                )
            }
            XCTAssertEqual(
                try coordinator.currentCursor(state: recovered).beat.id,
                "first-farmers-beat-three"
            )
        }

        let finalBeat = JourneyContentFixtures.applying(
            acrossArc.actions,
            to: interactionComplete
        )
        let final = try coordinator.advanceActions(state: finalBeat)
        for prefixLength in 0 ..< final.actions.count {
            let interrupted = JourneyContentFixtures.applying(
                Array(final.actions.prefix(prefixLength)),
                to: finalBeat
            )
            let firstRecovery = try coordinator.advanceActions(state: interrupted)
            let secondRecovery = try coordinator.advanceActions(state: interrupted)
            XCTAssertEqual(firstRecovery, secondRecovery)
            let recovered = JourneyContentFixtures.applying(
                firstRecovery.actions,
                to: interrupted
            )
            XCTAssertEqual(recovered.route, .world)
            XCTAssertTrue(recovered.completedChapterIDs.contains("first-farmers"))
        }
    }

    func testCursorRejectsForgedPackageVersionRelationshipsAndCompletionState() throws {
        let coordinator = try makeCoordinator()
        let base = ChapterSession(
            chapterID: "first-farmers",
            packageID: "essential-free-v1",
            contentVersion: SchemaVersion(major: 1),
            arcID: "first-farmers-arc-one",
            beatID: "first-farmers-beat-one"
        )
        let cases: [(ChapterSession, ChapterCoordinatorError)] = [
            (
                ChapterSession(
                    chapterID: base.chapterID,
                    packageID: "paid-pack-01",
                    contentVersion: base.contentVersion,
                    arcID: base.arcID,
                    beatID: base.beatID
                ),
                .sessionPackageMismatch("first-farmers")
            ),
            (
                ChapterSession(
                    chapterID: base.chapterID,
                    packageID: base.packageID,
                    contentVersion: SchemaVersion(major: 2),
                    arcID: base.arcID,
                    beatID: base.beatID
                ),
                .sessionVersionMismatch("first-farmers")
            ),
            (
                ChapterSession(
                    chapterID: base.chapterID,
                    packageID: base.packageID,
                    contentVersion: base.contentVersion,
                    arcID: "europe-holds-the-line-arc-one",
                    beatID: "europe-holds-the-line-beat-one"
                ),
                .arcOutsideChapter(
                    arcID: "europe-holds-the-line-arc-one",
                    chapterID: "first-farmers"
                )
            ),
            (
                ChapterSession(
                    chapterID: base.chapterID,
                    packageID: base.packageID,
                    contentVersion: base.contentVersion,
                    arcID: base.arcID,
                    beatID: "first-farmers-beat-two",
                    completedBeatIDs: []
                ),
                .malformedCompletionPrefix("first-farmers")
            ),
            (
                ChapterSession(
                    chapterID: base.chapterID,
                    packageID: base.packageID,
                    contentVersion: base.contentVersion,
                    arcID: base.arcID,
                    beatID: base.beatID,
                    sceneVisualSnapshot: SceneVisualSnapshot(
                        sceneID: "first-farmers-scene-three",
                        deterministicTick: 1
                    )
                ),
                .sceneSnapshotMismatch(
                    expected: "first-farmers-scene-one",
                    actual: "first-farmers-scene-three"
                )
            ),
        ]

        for (session, expectedError) in cases {
            let state = JourneyState(
                route: .chapter("first-farmers"),
                chapterSessions: [session]
            )
            XCTAssertThrowsError(try coordinator.currentCursor(state: state)) { error in
                XCTAssertEqual(error as? ChapterCoordinatorError, expectedError)
            }
        }
    }

    func testCursorRejectsMismatchedInstalledVersionAndCompletedActiveChapter() throws {
        let coordinator = try makeCoordinator()
        let session = ChapterSession(
            chapterID: "first-farmers",
            packageID: "essential-free-v1",
            contentVersion: SchemaVersion(major: 1),
            arcID: "first-farmers-arc-one",
            beatID: "first-farmers-beat-one"
        )
        let stale = JourneyState(
            route: .chapter("first-farmers"),
            chapterSessions: [session],
            installedContent: [
                InstalledContentVersion(
                    packageID: "essential-free-v1",
                    version: SchemaVersion(major: 2)
                ),
            ]
        )
        XCTAssertThrowsError(try coordinator.currentCursor(state: stale)) { error in
            XCTAssertEqual(
                error as? ChapterCoordinatorError,
                .installedVersionMismatch("essential-free-v1")
            )
        }

        let completed = JourneyState(
            route: .chapter("first-farmers"),
            chapterSessions: [session],
            completedChapterIDs: ["first-farmers"]
        )
        XCTAssertThrowsError(try coordinator.currentCursor(state: completed)) { error in
            XCTAssertEqual(
                error as? ChapterCoordinatorError,
                .completedChapterIsActive("first-farmers")
            )
        }
    }

    func testCursorRejectsForgedCompleteProgressAndMissingWorldConsequence() throws {
        let coordinator = try makeCoordinator()
        let interaction = try XCTUnwrap(
            coordinator.repository.beat("first-farmers-beat-two")?.interaction
        )
        var forgedRuntime = InteractionRuntimeState(spec: interaction)
        forgedRuntime.phase = .complete
        var forgedState = try stateBeforeFirstInteraction(coordinator: coordinator)
        forgedState.activeChapter?.interaction = forgedRuntime
        XCTAssertThrowsError(try coordinator.currentCursor(state: forgedState)) { error in
            XCTAssertEqual(
                error as? ChapterCoordinatorError,
                .interactionProgressMismatch(interaction.id)
            )
        }

        let validCompleteState = try completeCurrentTrace(
            coordinator: coordinator,
            state: stateAtInteractiveBeat(coordinator: coordinator)
        )
        let completeSession = try XCTUnwrap(
            validCompleteState.chapterSession("first-farmers")
        )
        let consequenceRemoved = JourneyState(
            route: .chapter("first-farmers"),
            world: try stateBeforeFirstInteraction(coordinator: coordinator).world,
            chapterSessions: [completeSession]
        )
        XCTAssertThrowsError(
            try coordinator.currentCursor(state: consequenceRemoved)
        ) { error in
            XCTAssertEqual(
                error as? ChapterCoordinatorError,
                .interactionEffectMismatch(interaction.id)
            )
        }
    }

    func testResponsiveAudioCursorIsDurableRepositoryBoundAndRestorationRequiresAuthority() throws {
        let coordinator = try makeCoordinator()
        var state = try stateAtInteractiveBeat(coordinator: coordinator)
        let cursor = try coordinator.currentCursor(state: state)
        let program = try XCTUnwrap(cursor.responsiveAudioProgram)
        XCTAssertEqual(program.scope.interactionID, "first-farmers-interaction")
        XCTAssertEqual(cursor.responsiveAudioTimelineIDs.count, 5)
        let waiting = try XCTUnwrap(program.interactionBed(for: .waiting))
        let snapshot = ResponsiveAudioProgramSnapshot(
            programID: program.id,
            stage: .interaction,
            interactionPhase: .waiting,
            timelineID: waiting.timelineID,
            cursorSample: 17_031,
            loopIteration: 4,
            durableCompletionSequence: nil
        )
        state = JourneyContentFixtures.applying(
            [.setResponsiveAudioSnapshot(snapshot)],
            to: state
        )
        let roundTrip = try JSONDecoder().decode(
            SaveSnapshot.self,
            from: JSONEncoder().encode(SaveSnapshot(state: state))
        ).state
        XCTAssertEqual(roundTrip.activeChapter?.responsiveAudioSnapshot, snapshot)

        let activePlan = try XCTUnwrap(
            coordinator.responsiveAudioRestorationPlan(state: roundTrip)
        )
        XCTAssertEqual(activePlan.snapshot, snapshot)
        XCTAssertFalse(activePlan.requiresCompletionAuthority)

        let completed = try completeCurrentTrace(coordinator: coordinator, state: roundTrip)
        let completedPlan = try XCTUnwrap(
            coordinator.responsiveAudioRestorationPlan(state: completed)
        )
        XCTAssertEqual(completedPlan.snapshot, snapshot)
        XCTAssertTrue(completedPlan.requiresCompletionAuthority)
    }

    func testCoordinatorFailsClosedOnForgedResponsiveAudioIdentityAndCursor() throws {
        let coordinator = try makeCoordinator()
        var state = try stateAtInteractiveBeat(coordinator: coordinator)
        let program = try XCTUnwrap(
            coordinator.currentCursor(state: state).responsiveAudioProgram
        )
        state.activeChapter?.responsiveAudioSnapshot = ResponsiveAudioProgramSnapshot(
            programID: "forged-responsive-program",
            stage: .approach,
            interactionPhase: nil,
            timelineID: program.approachTimelineID,
            cursorSample: 0,
            loopIteration: 0,
            durableCompletionSequence: nil
        )
        XCTAssertThrowsError(try coordinator.currentCursor(state: state)) { error in
            XCTAssertEqual(
                error as? ChapterCoordinatorError,
                .responsiveAudioSnapshotMismatch("first-farmers-interaction")
            )
        }
    }

    func testSceneAuthorityMustBeDurableBeforePresentationAndCannotBeForged() throws {
        let coordinator = try makeCoordinator()
        let opening = try coordinator.beginActions(
            chapterID: "first-farmers",
            state: .initial
        )
        guard case let .activateScene(contract) = opening[1] else {
            return XCTFail("Expected sealed scene activation")
        }
        var state = JourneyContentFixtures.applying([opening[0]])

        XCTAssertThrowsError(try coordinator.currentCursor(state: state)) { error in
            XCTAssertEqual(
                error as? ChapterCoordinatorError,
                .sceneSnapshotMissing("first-farmers-scene-one")
            )
        }

        let encoded = try JSONEncoder().encode(contract)
        let tamperedText = String(decoding: encoded, as: UTF8.self)
            .replacingOccurrences(
                of: "first-farmers-scene-one",
                with: "first-farmers-scene-forged"
            )
        let forged = try JSONDecoder().decode(
            SceneActivationContract.self,
            from: Data(tamperedText.utf8)
        )
        XCTAssertFalse(forged.isStructurallyValid)
        let beforeForgery = state
        let rejected = JourneyReducer().reduce(
            state: &state,
            action: .activateScene(forged)
        )
        XCTAssertEqual(state, beforeForgery)
        XCTAssertTrue(rejected.containsRejection)

        let repair = try coordinator.resumeActions(
            chapterID: "first-farmers",
            state: state
        )
        XCTAssertEqual(repair.count, 2)
        guard case .selectChapter = repair[0],
              case .activateScene = repair[1] else {
            return XCTFail("Resume must journal the missing scene before presentation")
        }
        state = JourneyContentFixtures.applying(repair, to: state)
        XCTAssertNoThrow(try coordinator.currentCursor(state: state))

        let tick = try coordinator.sceneTickAction(
            deterministicTick: 714,
            state: state
        )
        state = JourneyContentFixtures.applying([tick], to: state)
        XCTAssertEqual(state.activeChapter?.sceneVisualSnapshot?.deterministicTick, 714)

        let beforeRegression = state
        let regressed = JourneyReducer().reduce(
            state: &state,
            action: try coordinator.sceneTickAction(
                deterministicTick: 713,
                state: state
            )
        )
        XCTAssertEqual(state, beforeRegression)
        XCTAssertTrue(regressed.containsRejection)
    }

    func testChapterCompletionAuthorityRejectsForgeryPrematurityAndBrokenWorldState() throws {
        let coordinator = try makeCoordinator()
        let opening = JourneyContentFixtures.applying(
            try coordinator.beginActions(chapterID: "first-farmers", state: .initial)
        )
        var interactive = JourneyContentFixtures.applying(
            try coordinator.advanceActions(state: opening).actions,
            to: opening
        )
        interactive = try completeCurrentTrace(
            coordinator: coordinator,
            state: interactive
        )
        let finalBeat = JourneyContentFixtures.applying(
            try coordinator.advanceActions(state: interactive).actions,
            to: interactive
        )
        let finalPlan = try coordinator.advanceActions(state: finalBeat)
        guard case let .completeAuthoredChapter(contract) = finalPlan.actions.last else {
            return XCTFail("Expected sealed chapter completion")
        }
        let readyToComplete = JourneyContentFixtures.applying(
            Array(finalPlan.actions.dropLast()),
            to: finalBeat
        )

        var premature = opening
        let prematureBefore = premature
        let prematureEffects = JourneyReducer().reduce(
            state: &premature,
            action: .completeAuthoredChapter(contract)
        )
        XCTAssertEqual(premature, prematureBefore)
        XCTAssertTrue(prematureEffects.containsRejection)

        var missingArc = readyToComplete
        missingArc.activeChapter?.completedArcIDs.removeLast()
        let missingArcBefore = missingArc
        let missingArcEffects = JourneyReducer().reduce(
            state: &missingArc,
            action: .completeAuthoredChapter(contract)
        )
        XCTAssertEqual(missingArc, missingArcBefore)
        XCTAssertTrue(missingArcEffects.containsRejection)

        var brokenWorld = readyToComplete
        let requiredBeatEffect = try XCTUnwrap(
            contract.beatInventory.flatMap { $0.completion.effects }.first
        )
        brokenWorld.world = WorldGraph(
            nodes: brokenWorld.world.nodes,
            traces: brokenWorld.world.traces,
            appliedEffects: brokenWorld.world.appliedEffects.filter {
                $0.id != requiredBeatEffect.id
            }
        )
        let brokenWorldBefore = brokenWorld
        let brokenWorldEffects = JourneyReducer().reduce(
            state: &brokenWorld,
            action: .completeAuthoredChapter(contract)
        )
        XCTAssertEqual(brokenWorld, brokenWorldBefore)
        XCTAssertTrue(brokenWorldEffects.containsRejection)

        let encoded = try JSONEncoder().encode(contract)
        let forgedText = String(decoding: encoded, as: UTF8.self)
            .replacingOccurrences(
                of: contract.finalSceneID.rawValue,
                with: "forged-final-scene"
            )
        let forged = try JSONDecoder().decode(
            ChapterCompletionContract.self,
            from: Data(forgedText.utf8)
        )
        XCTAssertFalse(forged.isStructurallyValid)
        var forgedState = readyToComplete
        let forgedBefore = forgedState
        let forgedEffects = JourneyReducer().reduce(
            state: &forgedState,
            action: .completeAuthoredChapter(forged)
        )
        XCTAssertEqual(forgedState, forgedBefore)
        XCTAssertTrue(forgedEffects.containsRejection)

        var completed = readyToComplete
        let emitted = JourneyReducer().reduce(
            state: &completed,
            action: .completeAuthoredChapter(contract)
        )
        XCTAssertEqual(completed.route, .world)
        XCTAssertEqual(completed.completedChapterIDs, ["first-farmers"])
        XCTAssertEqual(
            completed.world.appliedEffects.filter {
                contract.completionEffects.map(\.id).contains($0.id)
            },
            contract.completionEffects
        )
        XCTAssertFalse(emitted.containsRejection)
    }

    private func makeCoordinator(includePaidPackage: Bool = false) throws -> ChapterCoordinator {
        var packages = [JourneyContentFixtures.package("essential-free-v1")]
        if includePaidPackage {
            packages.append(JourneyContentFixtures.package("paid-pack-01"))
        }
        return try ChapterCoordinator(
            repository: ContentRepository(packagePayloads: packages)
        )
    }

    private func stateAtInteractiveBeat(
        coordinator: ChapterCoordinator
    ) throws -> JourneyState {
        var state = try stateBeforeFirstInteraction(coordinator: coordinator)
        let interaction = try XCTUnwrap(
            coordinator.repository.beat("first-farmers-beat-two")?.interaction
        )
        state = JourneyContentFixtures.applying([.beginInteraction(interaction)], to: state)
        return state
    }

    private func stateBeforeFirstInteraction(
        coordinator: ChapterCoordinator
    ) throws -> JourneyState {
        let opening = JourneyContentFixtures.applying(
            try coordinator.beginActions(chapterID: "first-farmers", state: .initial)
        )
        let plan = try coordinator.advanceActions(state: opening)
        XCTAssertEqual(plan.actions.count, 4)
        return JourneyContentFixtures.applying(Array(plan.actions.prefix(3)), to: opening)
    }

    private func completeCurrentTrace(
        coordinator: ChapterCoordinator,
        state: JourneyState
    ) throws -> JourneyState {
        let interaction = try XCTUnwrap(
            coordinator.repository.beat("first-farmers-beat-two")?.interaction
        )
        return JourneyContentFixtures.applying(
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
    }

    private func assertIncompleteInteraction(
        coordinator: ChapterCoordinator,
        state: JourneyState,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertThrowsError(
            try coordinator.advanceActions(state: state),
            file: file,
            line: line
        ) { error in
            XCTAssertEqual(
                error as? ChapterCoordinatorError,
                .interactionIncomplete("first-farmers-interaction"),
                file: file,
                line: line
            )
        }
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
