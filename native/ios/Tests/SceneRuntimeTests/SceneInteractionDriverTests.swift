import ContentKit
import Foundation
import JourneyDomain
import SceneRuntime
import XCTest

final class SceneInteractionDriverTests: XCTestCase {
    func testTraceTouchSamplingDropsOnlyStationaryDuplicatesWithinOneGesture() {
        let first = SceneFramePoint(x: 0.25, y: 0.5)
        let second = SceneFramePoint(x: 0.5, y: 0.5)
        var policy = TraceTouchSampleAdmissionPolicy()

        XCTAssertTrue(policy.admits(first))
        XCTAssertFalse(policy.admits(first))
        XCTAssertFalse(policy.admits(first))
        XCTAssertTrue(policy.admits(second), "Real movement must remain admissible")
        XCTAssertTrue(
            policy.admits(first),
            "Returning after movement is a new sample, not a duplicate"
        )

        policy.endGesture()
        XCTAssertTrue(
            policy.admits(first),
            "The first point of a new gesture must not inherit prior sampling state"
        )
    }

    func testTraceDeferredTransportPreservesAnchorContactAtNinetyDegreeTurn() throws {
        let configuration = TraceInteractionSpec(
            anchors: [
                NormalizedPoint(x: 0.1, y: 0.5),
                NormalizedPoint(x: 0.5, y: 0.5),
                NormalizedPoint(x: 0.5, y: 0.9),
            ],
            tolerance: 0.03
        )
        let ordinaryInbound = TraceDeferredSamplePriority.classify(
            masterPoint: NormalizedPoint(x: 0.4, y: 0.5),
            configuration: configuration,
            reachedAnchorCount: 1
        )
        let cornerContact = TraceDeferredSamplePriority.classify(
            masterPoint: NormalizedPoint(x: 0.5, y: 0.5),
            configuration: configuration,
            reachedAnchorCount: 1
        )
        let ordinaryOutbound = TraceDeferredSamplePriority.classify(
            masterPoint: NormalizedPoint(x: 0.5, y: 0.6),
            configuration: configuration,
            reachedAnchorCount: 1
        )
        let laterAnchor = TraceDeferredSamplePriority.classify(
            masterPoint: NormalizedPoint(x: 0.5, y: 0.9),
            configuration: configuration,
            reachedAnchorCount: 1
        )

        XCTAssertNil(ordinaryInbound.protectedAnchorIndex)
        XCTAssertEqual(cornerContact.protectedAnchorIndex, 1)
        XCTAssertNil(ordinaryOutbound.protectedAnchorIndex)
        XCTAssertEqual(laterAnchor.protectedAnchorIndex, 2)

        var driver = try SceneInteractionDriver(
            spec: DriverFixtures.rightAngleTrace()
        )
        XCTAssertEqual(
            try driver.submit(
                .touch(.trace(NormalizedPoint(x: 0.1, y: 0.5)))
            ).feedback,
            .contact
        )
        XCTAssertEqual(
            try driver.submit(
                .touch(.trace(NormalizedPoint(x: 0.5, y: 0.5)))
            ).feedback,
            .contact
        )
        let afterCorner = try driver.submit(
            .touch(.trace(NormalizedPoint(x: 0.5, y: 0.6)))
        )
        XCTAssertEqual(afterCorner.feedback, .progress)
        guard case let .trace(afterCornerTrace) = afterCorner.after.mechanism else {
            return XCTFail("Expected a trace snapshot")
        }
        XCTAssertEqual(afterCornerTrace.reachedAnchorCount, 2)
    }

    func testTraceProducesResistanceProgressCompletionAndExactRestore() throws {
        let spec = DriverFixtures.trace()
        var driver = try SceneInteractionDriver(spec: spec)

        let initial = try driver.snapshot()
        guard case let .trace(initialTrace) = initial.mechanism else {
            return XCTFail("Expected a trace snapshot")
        }
        XCTAssertEqual(initial.phase, .ready)
        XCTAssertEqual(initialTrace.reachedAnchorCount, 0)
        XCTAssertEqual(initialTrace.totalAnchorCount, 3)

        let miss = NormalizedPoint(x: 0.9, y: 0.1)
        let resistance = try driver.submit(.touch(.trace(miss)))
        XCTAssertEqual(resistance.feedback, .resistance)
        XCTAssertEqual(resistance.completedEffects, [])
        guard case let .trace(missedTrace) = resistance.after.mechanism else {
            return XCTFail("Expected a trace snapshot")
        }
        XCTAssertEqual(missedTrace.reachedAnchorCount, 0)
        XCTAssertEqual(missedTrace.lastPoint, miss)

        let encoded = try JSONEncoder().encode(resistance.checkpoint)
        let decoded = try JSONDecoder().decode(SceneInteractionCheckpoint.self, from: encoded)
        var restored = try SceneInteractionDriver(spec: spec, restoring: decoded)
        XCTAssertEqual(try restored.snapshot(), resistance.after)
        XCTAssertEqual(restored.sequenceNumber, 1)

        let firstAnchor = DriverFixtures.traceAnchors[0]
        var touch = restored
        var semantic = restored
        let touchResponse = try touch.submit(.touch(.trace(firstAnchor)))
        let semanticResponse = try semantic.submit(.semantic(.trace(firstAnchor)))
        XCTAssertEqual(touchResponse, semanticResponse)
        XCTAssertEqual(touchResponse.feedback, .contact)

        let origin = try restored.submit(.semantic(.trace(firstAnchor)))
        XCTAssertEqual(origin.feedback, .contact)

        let viableRoutePoint = NormalizedPoint(x: 0.3, y: 0.35)
        let movement = try restored.submit(.touch(.trace(viableRoutePoint)))
        XCTAssertEqual(movement.feedback, .progress)
        guard case let .trace(movingTrace) = movement.after.mechanism else {
            return XCTFail("Expected a trace snapshot")
        }
        XCTAssertEqual(movingTrace.reachedAnchorCount, 1)
        XCTAssertEqual(movingTrace.lastPoint, viableRoutePoint)

        let offRoutePoint = NormalizedPoint(x: 0.3, y: 0.2)
        let offRoute = try restored.submit(.touch(.trace(offRoutePoint)))
        XCTAssertEqual(offRoute.feedback, .resistance)
        guard case let .trace(resistedTrace) = offRoute.after.mechanism else {
            return XCTFail("Expected a trace snapshot")
        }
        XCTAssertEqual(resistedTrace.reachedAnchorCount, 1)
        XCTAssertEqual(resistedTrace.lastPoint, offRoutePoint)

        let intermediateAnchor = try restored.submit(
            .touch(.trace(DriverFixtures.traceAnchors[1]))
        )
        XCTAssertEqual(intermediateAnchor.feedback, .contact)
        let completion = try restored.submit(.semantic(.trace(DriverFixtures.traceAnchors[2])))
        XCTAssertEqual(completion.feedback, .completed)
        XCTAssertEqual(completion.completedEffects, spec.completionEffects)
        XCTAssertEqual(completion.after.phase, .complete)
        XCTAssertEqual(try restored.checkpoint(), completion.checkpoint)

        let repeated = try restored.submit(.touch(.trace(DriverFixtures.traceAnchors[2])))
        XCTAssertEqual(repeated.feedback, .none)
        XCTAssertEqual(repeated.completedEffects, [])
        XCTAssertEqual(repeated.before, repeated.after)
    }

    func testTraceCoalescedSweepAdvancesExactlyOneAnchorAndReplays() throws {
        let spec = DriverFixtures.trace()
        let origin = DriverFixtures.traceAnchors[0]
        let intermediate = DriverFixtures.traceAnchors[1]
        let preAnchor = NormalizedPoint(x: 0.4, y: 0.425)
        let postAnchor = NormalizedPoint(x: 0.6, y: 0.575)

        var direct = try SceneInteractionDriver(spec: spec)
        _ = try direct.submit(.touch(.trace(origin)))
        let pre = try direct.submit(.touch(.trace(preAnchor)))
        XCTAssertEqual(pre.feedback, .progress)

        let encodedBeforeSweep = try JSONEncoder().encode(pre.checkpoint)
        let decodedBeforeSweep = try JSONDecoder().decode(
            SceneInteractionCheckpoint.self,
            from: encodedBeforeSweep
        )
        var replay = try SceneInteractionDriver(
            spec: spec,
            restoring: decodedBeforeSweep
        )

        let crossed = try direct.submit(.touch(.trace(postAnchor)))
        let replayed = try replay.submit(.semantic(.trace(postAnchor)))
        XCTAssertEqual(crossed, replayed)
        XCTAssertEqual(crossed.feedback, .contact)
        guard case let .trace(crossedTrace) = crossed.after.mechanism else {
            return XCTFail("Expected a trace snapshot")
        }
        XCTAssertEqual(crossedTrace.reachedAnchorCount, 2)
        XCTAssertEqual(
            crossedTrace.lastPoint,
            intermediate,
            "A coalesced crossing must canonicalise one ordered bearing point"
        )

        let encodedAfterSweep = try JSONEncoder().encode(crossed.checkpoint)
        let decodedAfterSweep = try JSONDecoder().decode(
            SceneInteractionCheckpoint.self,
            from: encodedAfterSweep
        )
        let restoredAfterSweep = try SceneInteractionDriver(
            spec: spec,
            restoring: decodedAfterSweep
        )
        XCTAssertEqual(try restoredAfterSweep.snapshot(), crossed.after)

        var turnedAfterCrossing = try SceneInteractionDriver(spec: spec)
        _ = try turnedAfterCrossing.submit(.touch(.trace(origin)))
        _ = try turnedAfterCrossing.submit(
            .touch(.trace(NormalizedPoint(x: 0.44, y: 0.455)))
        )
        let crossedBeforeTurningOff = try turnedAfterCrossing.submit(
            .touch(.trace(NormalizedPoint(x: 0.56, y: 0.62)))
        )
        XCTAssertEqual(crossedBeforeTurningOff.feedback, .contact)
        guard case let .trace(turnedTrace) = crossedBeforeTurningOff.after.mechanism else {
            return XCTFail("Expected a trace snapshot")
        }
        XCTAssertEqual(turnedTrace.reachedAnchorCount, 2)
        XCTAssertEqual(turnedTrace.lastPoint, intermediate)
        XCTAssertEqual(
            try turnedAfterCrossing.submit(
                .touch(.trace(NormalizedPoint(x: 0.56, y: 0.62)))
            ).feedback,
            .resistance,
            "After canonical contact, the following off-route sample must resist"
        )

        var offCorridor = try SceneInteractionDriver(spec: spec)
        _ = try offCorridor.submit(.touch(.trace(origin)))
        let offBefore = NormalizedPoint(x: 0.48, y: 0.7)
        let offAfter = NormalizedPoint(x: 0.52, y: 0.3)
        XCTAssertEqual(
            try offCorridor.submit(.touch(.trace(offBefore))).feedback,
            .resistance
        )
        let falseCrossing = try offCorridor.submit(.touch(.trace(offAfter)))
        XCTAssertEqual(falseCrossing.feedback, .resistance)
        guard case let .trace(falseCrossingTrace) = falseCrossing.after.mechanism else {
            return XCTFail("Expected a trace snapshot")
        }
        XCTAssertEqual(
            falseCrossingTrace.reachedAnchorCount,
            1,
            "An off-corridor segment may not gain authority by geometrically crossing an anchor"
        )
    }

    func testAllocateReportsMaterialTotalsAndCheckpointsResistance() throws {
        let spec = DriverFixtures.allocate()
        var driver = try SceneInteractionDriver(spec: spec)

        let seed = try driver.submit(
            .touch(.allocate(destinationID: "seed", units: 1))
        )
        XCTAssertEqual(seed.feedback, .progress)
        guard case let .allocate(seedState) = seed.after.mechanism else {
            return XCTFail("Expected an allocate snapshot")
        }
        XCTAssertEqual(seedState.totalUnits, 4)
        XCTAssertEqual(seedState.allocatedUnits, 1)
        XCTAssertEqual(seedState.remainingUnits, 3)
        XCTAssertEqual(seedState.allocations.map(\.destinationID), ["seed", "winter"])

        let overdraw = try driver.submit(
            .semantic(.allocate(destinationID: "winter", units: 4))
        )
        XCTAssertEqual(overdraw.feedback, .resistance)
        XCTAssertEqual(overdraw.before, overdraw.after)
        XCTAssertEqual(overdraw.checkpoint.sequenceNumber, 2)

        let resetBeforeCompletion = try driver.submit(.semantic(.reset))
        XCTAssertEqual(resetBeforeCompletion.feedback, .none)
        XCTAssertEqual(resetBeforeCompletion.after.phase, .ready)
        guard case let .allocate(resetState) = resetBeforeCompletion.after.mechanism else {
            return XCTFail("Expected an allocate snapshot")
        }
        XCTAssertEqual(resetState.allocatedUnits, 0)
        XCTAssertEqual(resetState.remainingUnits, 4)

        var restored = try SceneInteractionDriver(spec: spec, restoring: overdraw.checkpoint)
        let winter = try restored.submit(
            .semantic(.allocate(destinationID: "winter", units: 3))
        )
        guard case let .allocate(fullState) = winter.after.mechanism else {
            return XCTFail("Expected an allocate snapshot")
        }
        XCTAssertEqual(fullState.allocatedUnits, 4)
        XCTAssertEqual(fullState.remainingUnits, 0)
        XCTAssertEqual(winter.after.phase, .active)

        let completion = try restored.submit(.touch(.commitAllocation))
        XCTAssertEqual(completion.feedback, .completed)
        XCTAssertEqual(completion.completedEffects, spec.completionEffects)
        XCTAssertEqual(completion.after.phase, .complete)

        let resetAfterCompletion = try restored.submit(.semantic(.reset))
        XCTAssertEqual(resetAfterCompletion.feedback, .none)
        XCTAssertEqual(resetAfterCompletion.completedEffects, [])
        XCTAssertEqual(resetAfterCompletion.before, resetAfterCompletion.after)
        XCTAssertEqual(resetAfterCompletion.after.phase, .complete)
        guard case let .allocate(completedState) = resetAfterCompletion.after.mechanism else {
            return XCTFail("Expected an allocate snapshot")
        }
        XCTAssertEqual(completedState.allocatedUnits, 4)
        XCTAssertEqual(completedState.remainingUnits, 0)
    }

    func testAllocateAcceptsDifferentSurplusChoicesButNeverBrokenObligations() throws {
        let spec = DriverFixtures.allocate()

        for validDistribution in [
            ["seed": 3, "winter": 1],
            ["seed": 1, "winter": 3],
            ["seed": 2, "winter": 2],
        ] {
            var driver = try SceneInteractionDriver(spec: spec)
            for destination in ["seed", "winter"] {
                _ = try driver.submit(
                    .touch(.allocate(
                        destinationID: destination,
                        units: validDistribution[destination]!
                    ))
                )
            }
            let completion = try driver.submit(.touch(.commitAllocation))
            XCTAssertEqual(completion.feedback, .completed)
            XCTAssertEqual(completion.after.phase, .complete)
            XCTAssertEqual(completion.completedEffects, spec.completionEffects)
        }

        var broken = try SceneInteractionDriver(spec: spec)
        _ = try broken.submit(.touch(.allocate(destinationID: "seed", units: 4)))
        let rejected = try broken.submit(.touch(.commitAllocation))
        XCTAssertEqual(rejected.feedback, .resistance)
        XCTAssertEqual(rejected.after.phase, .active)
    }

    func testAssembleExposesOnlyCausallyAvailableComponents() throws {
        let spec = DriverFixtures.assemble()
        var driver = try SceneInteractionDriver(spec: spec)

        guard case let .assemble(initial) = try driver.snapshot().mechanism else {
            return XCTFail("Expected an assemble snapshot")
        }
        XCTAssertEqual(initial.availableComponentIDs, ["foundation"])

        let earlyRoof = try driver.submit(
            .touch(.place(componentID: "roof", slotID: "cover"))
        )
        XCTAssertEqual(earlyRoof.feedback, .resistance)
        guard case let .assemble(afterResistance) = earlyRoof.after.mechanism else {
            return XCTFail("Expected an assemble snapshot")
        }
        XCTAssertEqual(afterResistance.availableComponentIDs, ["foundation"])
        XCTAssertEqual(afterResistance.placements, [])

        let foundation = try driver.submit(
            .semantic(.place(componentID: "foundation", slotID: "ground"))
        )
        guard case let .assemble(afterFoundation) = foundation.after.mechanism else {
            return XCTFail("Expected an assemble snapshot")
        }
        XCTAssertEqual(afterFoundation.availableComponentIDs, ["frame"])
        XCTAssertEqual(afterFoundation.placements.map(\.componentID), ["foundation"])

        var touch = try SceneInteractionDriver(spec: spec, restoring: foundation.checkpoint)
        var semantic = touch
        let touchFrame = try touch.submit(
            .touch(.place(componentID: "frame", slotID: "walls"))
        )
        let semanticFrame = try semantic.submit(
            .semantic(.place(componentID: "frame", slotID: "walls"))
        )
        XCTAssertEqual(touchFrame, semanticFrame)

        let roof = try touch.submit(
            .touch(.place(componentID: "roof", slotID: "cover"))
        )
        XCTAssertEqual(roof.feedback, .completed)
        XCTAssertEqual(roof.completedEffects, spec.completionEffects)
        guard case let .assemble(complete) = roof.after.mechanism else {
            return XCTFail("Expected an assemble snapshot")
        }
        XCTAssertEqual(complete.availableComponentIDs, [])
        XCTAssertEqual(complete.placements.map(\.componentID), ["foundation", "frame", "roof"])
    }

    func testPressureTracksNetForceStableTimeAndBreaksTheHold() throws {
        let spec = DriverFixtures.pressure()
        var driver = try SceneInteractionDriver(spec: spec)

        guard case let .pressure(initial) = try driver.snapshot().mechanism else {
            return XCTFail("Expected a pressure snapshot")
        }
        XCTAssertEqual(initial.netPressure, -0.4, accuracy: 0.000_000_001)
        XCTAssertEqual(initial.stableMillis, 0)
        XCTAssertEqual(initial.requiredHoldMillis, 1_200)

        let balance = try driver.submit(
            .touch(.setPressure(forceID: "defence", magnitude: 0.45))
        )
        guard case let .pressure(balanced) = balance.after.mechanism else {
            return XCTFail("Expected a pressure snapshot")
        }
        XCTAssertEqual(balanced.netPressure, 0.05, accuracy: 0.000_000_001)

        let held = try driver.submit(.semantic(.advancePressure(elapsedMillis: 500)))
        XCTAssertEqual(held.feedback, .threshold)
        guard case let .pressure(heldState) = held.after.mechanism else {
            return XCTFail("Expected a pressure snapshot")
        }
        XCTAssertEqual(heldState.stableMillis, 500)

        var broken = try SceneInteractionDriver(spec: spec, restoring: held.checkpoint)
        _ = try broken.submit(
            .touch(.setPressure(forceID: "defence", magnitude: 0))
        )
        let breakResponse = try broken.submit(
            .touch(.advancePressure(elapsedMillis: 1))
        )
        XCTAssertEqual(breakResponse.feedback, .resistance)
        guard case let .pressure(brokenState) = breakResponse.after.mechanism else {
            return XCTFail("Expected a pressure snapshot")
        }
        XCTAssertEqual(brokenState.stableMillis, 0)

        var completed = try SceneInteractionDriver(spec: spec, restoring: held.checkpoint)
        let completion = try completed.submit(
            .semantic(.advancePressure(elapsedMillis: 1_000))
        )
        XCTAssertEqual(completion.feedback, .completed)
        XCTAssertEqual(completion.completedEffects, spec.completionEffects)
        guard case let .pressure(completedState) = completion.after.mechanism else {
            return XCTFail("Expected a pressure snapshot")
        }
        XCTAssertEqual(completedState.stableMillis, 1_500)
    }

    func testTransformPreservesMonotonicStageProgressAcrossRestore() throws {
        let spec = DriverFixtures.transform()
        var driver = try SceneInteractionDriver(spec: spec)

        let wrongControl = try driver.submit(
            .touch(.transform(controlID: "seed", amount: 0.5))
        )
        XCTAssertEqual(wrongControl.feedback, .resistance)
        XCTAssertEqual(wrongControl.before.mechanism, wrongControl.after.mechanism)

        _ = try driver.submit(.semantic(.transform(controlID: "field", amount: 0.3)))
        let backwards = try driver.submit(
            .touch(.transform(controlID: "field", amount: 0.2))
        )
        guard case let .transform(monotonic) = backwards.after.mechanism else {
            return XCTFail("Expected a transform snapshot")
        }
        XCTAssertEqual(monotonic.currentAmount, 0.3, accuracy: 0.000_000_001)

        let firstStage = try driver.submit(
            .semantic(.transform(controlID: "field", amount: 0.7))
        )
        guard case let .transform(sowing) = firstStage.after.mechanism else {
            return XCTFail("Expected a transform snapshot")
        }
        XCTAssertEqual(sowing.completedStageCount, 1)
        XCTAssertEqual(sowing.currentStageID, "sow")
        XCTAssertEqual(sowing.currentControlID, "seed")
        XCTAssertEqual(sowing.currentAmount, 0)

        var touch = try SceneInteractionDriver(spec: spec, restoring: firstStage.checkpoint)
        var semantic = touch
        let touchCompletion = try touch.submit(
            .touch(.transform(controlID: "seed", amount: 1))
        )
        let semanticCompletion = try semantic.submit(
            .semantic(.transform(controlID: "seed", amount: 1))
        )
        XCTAssertEqual(touchCompletion, semanticCompletion)
        XCTAssertEqual(touchCompletion.feedback, .completed)
        XCTAssertEqual(touchCompletion.completedEffects, spec.completionEffects)
        guard case let .transform(complete) = touchCompletion.after.mechanism else {
            return XCTFail("Expected a transform snapshot")
        }
        XCTAssertEqual(complete.completedStageCount, 2)
        XCTAssertNil(complete.currentStageID)
        XCTAssertNil(complete.currentControlID)
    }

    func testTouchAndResolvedSemanticInputsHaveExactParityForEveryGrammar() throws {
        let paths: [(InteractionSpec, [InteractionAction])] = [
            (
                DriverFixtures.trace(),
                DriverFixtures.traceAnchors.map(InteractionAction.trace)
            ),
            (
                DriverFixtures.allocate(),
                [
                    .allocate(destinationID: "seed", units: 1),
                    .allocate(destinationID: "winter", units: 3),
                    .commitAllocation,
                ]
            ),
            (
                DriverFixtures.assemble(),
                [
                    .place(componentID: "foundation", slotID: "ground"),
                    .place(componentID: "frame", slotID: "walls"),
                    .place(componentID: "roof", slotID: "cover"),
                ]
            ),
            (
                DriverFixtures.pressure(),
                [
                    .setPressure(forceID: "defence", magnitude: 0.45),
                    .advancePressure(elapsedMillis: 600),
                    .advancePressure(elapsedMillis: 600),
                ]
            ),
            (
                DriverFixtures.transform(),
                [
                    .transform(controlID: "field", amount: 0.6),
                    .transform(controlID: "seed", amount: 1),
                ]
            ),
        ]

        for (spec, actions) in paths {
            var touch = try SceneInteractionDriver(spec: spec)
            var semantic = try SceneInteractionDriver(spec: spec)
            for action in actions {
                let touchResponse = try touch.submit(.touch(action))
                let semanticResponse = try semantic.submit(.semantic(action))
                XCTAssertEqual(touchResponse, semanticResponse, "Parity failed for \(spec.id)")
            }
            XCTAssertEqual(touch.state, semantic.state)
            XCTAssertEqual(touch.state.phase, .complete)
            XCTAssertEqual(try touch.checkpoint(), try semantic.checkpoint())
        }
    }

    func testPurePreviewMatchesJourneyReducerWithoutMutatingCommittedState() throws {
        for (spec, actions) in DriverFixtures.canonicalPaths {
            var committed = InteractionRuntimeState(spec: spec)

            for action in actions {
                let before = committed
                let touch = try SceneInteractionDriver.preview(
                    spec: spec,
                    state: committed,
                    input: .touch(action)
                )
                let semantic = try SceneInteractionDriver.preview(
                    spec: spec,
                    state: committed,
                    input: .semantic(action)
                )

                XCTAssertEqual(touch, semantic, "Input source leaked for \(spec.id)")
                XCTAssertEqual(committed, before, "Preview mutated authority for \(spec.id)")

                var reduced = committed
                let reduction = try InteractionReducer.reduce(
                    state: &reduced,
                    spec: spec,
                    action: action
                )
                XCTAssertEqual(touch.candidateState, reduced)
                XCTAssertEqual(touch.feedback, reduction.feedback)
                XCTAssertEqual(touch.completedEffects, reduction.completedEffects)
                committed = reduced
            }

            XCTAssertEqual(committed.phase, .complete)
        }
    }

    func testInstanceSubmitIsOnlyALabWrapperAroundPurePreview() throws {
        for (spec, actions) in DriverFixtures.canonicalPaths {
            var driver = try SceneInteractionDriver(spec: spec)
            for action in actions {
                let expected = try SceneInteractionDriver.preview(
                    spec: spec,
                    state: driver.state,
                    input: .touch(action)
                )
                let response = try driver.submit(.semantic(action))
                XCTAssertEqual(response.action, expected.action)
                XCTAssertEqual(response.feedback, expected.feedback)
                XCTAssertEqual(response.before, expected.before)
                XCTAssertEqual(response.after, expected.after)
                XCTAssertEqual(response.completedEffects, expected.completedEffects)
                XCTAssertEqual(driver.state, expected.candidateState)
            }
        }
    }

    func testPurePreviewCannotUndoACompletedConsequence() throws {
        let spec = DriverFixtures.allocate()
        var state = InteractionRuntimeState(spec: spec)
        for action in [
            InteractionAction.allocate(destinationID: "seed", units: 1),
            .allocate(destinationID: "winter", units: 3),
            .commitAllocation,
        ] {
            state = try SceneInteractionDriver.preview(
                spec: spec,
                state: state,
                input: .touch(action)
            ).candidateState
        }
        XCTAssertEqual(state.phase, .complete)

        let reset = try SceneInteractionDriver.preview(
            spec: spec,
            state: state,
            input: .semantic(.reset)
        )
        XCTAssertEqual(reset.candidateState, state)
        XCTAssertEqual(reset.before, reset.after)
        XCTAssertEqual(reset.feedback, .none)
        XCTAssertEqual(reset.completedEffects, [])
    }

    func testReplayFromEveryCheckpointProducesTheSameNextResponse() throws {
        for (spec, actions) in DriverFixtures.canonicalPaths {
            var uninterrupted = try SceneInteractionDriver(spec: spec)
            for action in actions {
                let prior = try uninterrupted.checkpoint()
                let expected = try uninterrupted.submit(.touch(action))
                var restored = try SceneInteractionDriver(spec: spec, restoring: prior)
                let actual = try restored.submit(.semantic(action))
                XCTAssertEqual(actual, expected, "Restore diverged for \(spec.id)")
                XCTAssertEqual(try restored.checkpoint(), expected.checkpoint)
            }
        }
    }

    func testMismatchedAndMalformedInputsFailWithoutMutatingState() throws {
        let spec = DriverFixtures.trace()
        var driver = try SceneInteractionDriver(spec: spec)
        let before = try driver.checkpoint()

        XCTAssertThrowsError(
            try driver.submit(.touch(.place(componentID: "post", slotID: "wall")))
        ) { error in
            XCTAssertEqual(error as? SceneInteractionDriverError, .mismatchedAction)
        }
        XCTAssertEqual(try driver.checkpoint(), before)

        XCTAssertThrowsError(
            try driver.submit(.semantic(.trace(NormalizedPoint(x: .nan, y: 0.5))))
        ) { error in
            XCTAssertEqual(error as? SceneInteractionDriverError, .invalidActionValue)
        }
        XCTAssertEqual(try driver.checkpoint(), before)

        let allocateSpec = DriverFixtures.allocate()
        var allocate = try SceneInteractionDriver(spec: allocateSpec)
        _ = try allocate.submit(
            .touch(.allocate(destinationID: "seed", units: 1))
        )
        let beforeOverflow = try allocate.checkpoint()
        XCTAssertThrowsError(
            try allocate.submit(
                .semantic(.allocate(destinationID: "winter", units: .max))
            )
        ) { error in
            XCTAssertEqual(error as? SceneInteractionDriverError, .invalidActionValue)
        }
        XCTAssertEqual(try allocate.checkpoint(), beforeOverflow)
    }

    func testRestoreRejectsWrongVersionChangedSpecAndForgedState() throws {
        let spec = DriverFixtures.allocate()
        let driver = try SceneInteractionDriver(spec: spec)
        let checkpoint = try driver.checkpoint()

        let wrongVersion = SceneInteractionCheckpoint(
            formatVersion: SceneInteractionCheckpoint.currentFormatVersion + 1,
            interactionID: checkpoint.interactionID,
            authoredSpecDigest: checkpoint.authoredSpecDigest,
            sequenceNumber: checkpoint.sequenceNumber,
            state: checkpoint.state
        )
        XCTAssertThrowsError(
            try SceneInteractionDriver(spec: spec, restoring: wrongVersion)
        ) { error in
            XCTAssertEqual(
                error as? SceneInteractionDriverError,
                .unsupportedCheckpointVersion(SceneInteractionCheckpoint.currentFormatVersion + 1)
            )
        }

        let changedSpec = DriverFixtures.allocate(totalUnits: 5, seedUnits: 2, winterUnits: 1)
        XCTAssertThrowsError(
            try SceneInteractionDriver(spec: changedSpec, restoring: checkpoint)
        ) { error in
            XCTAssertEqual(error as? SceneInteractionDriverError, .checkpointSpecMismatch)
        }

        let sameIDWrongGrammar = DriverFixtures.trace(id: spec.id)
        let forgedState = InteractionRuntimeState(spec: sameIDWrongGrammar)
        let forged = SceneInteractionCheckpoint(
            interactionID: checkpoint.interactionID,
            authoredSpecDigest: checkpoint.authoredSpecDigest,
            sequenceNumber: checkpoint.sequenceNumber,
            state: forgedState
        )
        XCTAssertThrowsError(
            try SceneInteractionDriver(spec: spec, restoring: forged)
        ) { error in
            XCTAssertEqual(error as? SceneInteractionDriverError, .invalidRuntimeState)
        }

        var duplicateAllocationState = checkpoint.state
        duplicateAllocationState.phase = .active
        duplicateAllocationState.progress = .allocate(
            AllocateProgress(
                allocations: [
                    AllocationValue(destinationID: "seed", units: 1),
                    AllocationValue(destinationID: "seed", units: 3),
                ]
            )
        )
        let duplicateAllocation = SceneInteractionCheckpoint(
            interactionID: checkpoint.interactionID,
            authoredSpecDigest: checkpoint.authoredSpecDigest,
            sequenceNumber: checkpoint.sequenceNumber,
            state: duplicateAllocationState
        )
        XCTAssertThrowsError(
            try SceneInteractionDriver(spec: spec, restoring: duplicateAllocation)
        ) { error in
            XCTAssertEqual(error as? SceneInteractionDriverError, .invalidRuntimeState)
        }

        let pressureSpec = DriverFixtures.pressure()
        let pressureDriver = try SceneInteractionDriver(spec: pressureSpec)
        let pressureCheckpoint = try pressureDriver.checkpoint()
        var forgedPressureState = pressureCheckpoint.state
        guard case var .pressure(forgedPressure) = forgedPressureState.progress,
              let attackIndex = forgedPressure.values.firstIndex(where: {
                  $0.forceID == "attack"
              }) else {
            return XCTFail("Expected a pressure checkpoint")
        }
        forgedPressure.values[attackIndex].magnitude = 0.2
        forgedPressureState.progress = .pressure(forgedPressure)
        let forgedPressureCheckpoint = SceneInteractionCheckpoint(
            interactionID: pressureCheckpoint.interactionID,
            authoredSpecDigest: pressureCheckpoint.authoredSpecDigest,
            sequenceNumber: pressureCheckpoint.sequenceNumber,
            state: forgedPressureState
        )
        XCTAssertThrowsError(
            try SceneInteractionDriver(
                spec: pressureSpec,
                restoring: forgedPressureCheckpoint
            )
        ) { error in
            XCTAssertEqual(error as? SceneInteractionDriverError, .invalidRuntimeState)
        }

        let sequenceLimit = SceneInteractionCheckpoint(
            interactionID: checkpoint.interactionID,
            authoredSpecDigest: checkpoint.authoredSpecDigest,
            sequenceNumber: .max,
            state: checkpoint.state
        )
        var limited = try SceneInteractionDriver(spec: spec, restoring: sequenceLimit)
        XCTAssertThrowsError(try limited.submit(.touch(.begin))) { error in
            XCTAssertEqual(error as? SceneInteractionDriverError, .sequenceOverflow)
        }
        XCTAssertEqual(try limited.checkpoint(), sequenceLimit)
    }

    func testResponseAndCheckpointAreStableCodableValues() throws {
        let spec = DriverFixtures.assemble()
        var driver = try SceneInteractionDriver(spec: spec)
        let response = try driver.submit(
            .semantic(.place(componentID: "foundation", slotID: "ground"))
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let first = try encoder.encode(response)
        let decoded = try JSONDecoder().decode(SceneInteractionResponse.self, from: first)
        let second = try encoder.encode(decoded)
        XCTAssertEqual(decoded, response)
        XCTAssertEqual(first, second)
    }
}

private enum DriverFixtures {
    static let traceAnchors = [
        NormalizedPoint(x: 0.1, y: 0.2),
        NormalizedPoint(x: 0.5, y: 0.5),
        NormalizedPoint(x: 0.9, y: 0.8),
    ]

    static func trace(id: InteractionID = "trace-route") -> InteractionSpec {
        interaction(
            id: id,
            grammar: .trace(
                TraceInteractionSpec(anchors: traceAnchors, tolerance: 0.05)
            )
        )
    }

    static func rightAngleTrace() -> InteractionSpec {
        interaction(
            id: "trace-right-angle",
            grammar: .trace(
                TraceInteractionSpec(
                    anchors: [
                        NormalizedPoint(x: 0.1, y: 0.5),
                        NormalizedPoint(x: 0.5, y: 0.5),
                        NormalizedPoint(x: 0.5, y: 0.9),
                    ],
                    tolerance: 0.03
                )
            )
        )
    }

    static func allocate(
        totalUnits: Int = 4,
        seedUnits: Int = 1,
        winterUnits: Int = 1
    ) -> InteractionSpec {
        interaction(
            id: "allocate-harvest",
            grammar: .allocate(
                AllocateInteractionSpec(
                    resourceName: copy("harvest-resource", "harvest shares"),
                    totalUnits: totalUnits,
                    destinations: [
                        AllocationDestination(id: "winter", minimumUnits: winterUnits),
                        AllocationDestination(id: "seed", minimumUnits: seedUnits),
                    ]
                )
            )
        )
    }

    static func assemble() -> InteractionSpec {
        interaction(
            id: "assemble-house",
            grammar: .assemble(
                AssembleInteractionSpec(
                    components: [
                        AssemblyComponent(id: "roof", targetSlot: "cover", prerequisites: ["frame"]),
                        AssemblyComponent(id: "foundation", targetSlot: "ground"),
                        AssemblyComponent(id: "frame", targetSlot: "walls", prerequisites: ["foundation"]),
                    ]
                )
            )
        )
    }

    static func pressure() -> InteractionSpec {
        interaction(
            id: "pressure-frontier",
            grammar: .pressure(
                PressureInteractionSpec(
                    forces: [
                        PressureForce(
                            id: "defence",
                            direction: 1,
                            initialMagnitude: 0,
                            userControllable: true
                        ),
                        PressureForce(
                            id: "attack",
                            direction: -1,
                            initialMagnitude: 0.4,
                            userControllable: false
                        ),
                    ],
                    stableRange: 0 ... 0.1,
                    requiredHoldMillis: 1_200
                )
            )
        )
    }

    static func transform() -> InteractionSpec {
        interaction(
            id: "transform-field",
            grammar: .transform(
                TransformInteractionSpec(
                    stages: [
                        TransformationStage(id: "clear", controlID: "field", requiredAmount: 0.6),
                        TransformationStage(id: "sow", controlID: "seed", requiredAmount: 1),
                    ]
                )
            )
        )
    }

    static var canonicalPaths: [(InteractionSpec, [InteractionAction])] {
        [
            (trace(), traceAnchors.map(InteractionAction.trace)),
            (
                allocate(),
                [
                    .allocate(destinationID: "seed", units: 1),
                    .allocate(destinationID: "winter", units: 3),
                    .commitAllocation,
                ]
            ),
            (
                assemble(),
                [
                    .place(componentID: "foundation", slotID: "ground"),
                    .place(componentID: "frame", slotID: "walls"),
                    .place(componentID: "roof", slotID: "cover"),
                ]
            ),
            (
                pressure(),
                [
                    .setPressure(forceID: "defence", magnitude: 0.45),
                    .advancePressure(elapsedMillis: 600),
                    .advancePressure(elapsedMillis: 600),
                ]
            ),
            (
                transform(),
                [
                    .transform(controlID: "field", amount: 0.6),
                    .transform(controlID: "seed", amount: 1),
                ]
            ),
        ]
    }

    private static func interaction(
        id: InteractionID,
        grammar: InteractionSpec.Grammar
    ) -> InteractionSpec {
        InteractionSpec(
            id: id,
            prompt: copy("prompt-\(id.rawValue)", "Act on the historical mechanism"),
            grammar: grammar,
            completionEffects: [
                WorldEffect(
                    id: WorldEffectID("effect-\(id.rawValue)"),
                    mutation: .revealNode(
                        WorldNodeBlueprint(
                            id: WorldNodeID("node-\(id.rawValue)"),
                            kind: .institution,
                            form: "A durable historical consequence",
                            position: NormalizedPoint(x: 0.5, y: 0.5)
                        )
                    )
                ),
            ],
            accessibilityID: AccessibilityID("access-\(id.rawValue)")
        )
    }

    private static func copy(_ id: String, _ launchEnglish: String) -> LocalizedStringSpec {
        LocalizedStringSpec(id: LocalizedStringID(id), launchEnglish: launchEnglish)
    }
}
