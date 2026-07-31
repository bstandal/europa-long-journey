import ContentKit
import JourneyPersistence
import XCTest

final class ResponsiveAudioSceneMutationGateTests: XCTestCase {
    func testThreeStageTransformCannotAdmitAnotherStageAfterAudioFailure() throws {
        var gate = ResponsiveAudioSceneMutationGate()
        var durablyAdmittedStageCount = 0

        let first = try XCTUnwrap(try gate.begin(
            requiresResponsiveAudio: true,
            controllerIsReady: true
        ))
        durablyAdmittedStageCount += 1

        XCTAssertThrowsError(try gate.begin(
            requiresResponsiveAudio: true,
            controllerIsReady: true
        ), "A queued input cannot overtake the first audio follow-up")
        XCTAssertFalse(gate.finish(first) { _ in
            XCTFail("No deferred intent exists to materialize")
        })

        for _ in 2 ... 3 {
            XCTAssertThrowsError(try gate.begin(
                requiresResponsiveAudio: true,
                controllerIsReady: false
            )) { error in
                XCTAssertEqual(
                    error as? ResponsiveAudioSceneMutationGateError,
                    .authoredAudioUnavailable
                )
            }
        }
        XCTAssertEqual(durablyAdmittedStageCount, 1)

        XCTAssertNil(try gate.begin(
            requiresResponsiveAudio: false,
            controllerIsReady: false
        ), "A non-responsive beat must not wait on the audio gate")
    }

    @MainActor
    func testBlockingAudioFollowUpDefersSuspendAndPhaseSnapshotMaterialization() async throws {
        let harness = ResponsiveAudioSceneMutationIntegrationHarness()
        let admitted = try harness.begin()
        let audioFollowUp = BlockingResponsiveAudioFollowUp()
        let transaction = Task {
            await audioFollowUp.enterAndWait()
            harness.finish(admitted)
        }
        await audioFollowUp.waitUntilEntered()

        XCTAssertTrue(harness.deferPhase(.resistance))
        XCTAssertTrue(harness.deferSuspension(atEpochMillis: 41))
        XCTAssertTrue(harness.deferSuspension(atEpochMillis: 43))
        XCTAssertEqual(harness.snapshotMaterializationCount, 0)

        await audioFollowUp.release()
        await transaction.value

        let released = harness.materializedIntents
        XCTAssertEqual(released?.phase, .resistance)
        XCTAssertEqual(released?.suspensionEpochMillis, 43)
        XCTAssertEqual(harness.snapshotMaterializationCount, 1)
        harness.finish(admitted)
        XCTAssertEqual(
            harness.snapshotMaterializationCount,
            1,
            "A duplicate release cannot flush intent twice"
        )
    }

    func testDeferredIntentRemainsOwnedByTheOnlyAdmittedResponsiveTransaction() throws {
        var gate = ResponsiveAudioSceneMutationGate()
        let first = try XCTUnwrap(try gate.begin(
            requiresResponsiveAudio: true,
            controllerIsReady: true
        ))

        XCTAssertTrue(gate.deferSuspensionIfNeeded(atEpochMillis: 91))
        var released: ResponsiveAudioSceneMutationGate.DeferredIntents?
        XCTAssertTrue(gate.finish(first) { released = $0 })
        XCTAssertEqual(released?.suspensionEpochMillis, 91)
        XCTAssertFalse(gate.hasActiveResponsiveSceneMutation)
    }

    func testBoundaryAtEverySceneCommitBarrierIsRederivedOnlyAfterSceneFinishes()
        throws {
        for overlap in BoundaryOverlapPoint.allCases {
            var gate = ResponsiveAudioSceneMutationGate()
            let controller = BoundaryControllerIdentity()
            let token = try XCTUnwrap(try gate.begin(
                requiresResponsiveAudio: true,
                controllerIsReady: true
            ))

            XCTAssertEqual(
                gate.receiveAutomaticBoundary(
                    controllerIdentifier: ObjectIdentifier(controller)
                ),
                .deferred,
                "Boundary must remain semantic intent at \(overlap)"
            )
            XCTAssertFalse(gate.automaticBoundaryDurabilityIsPending)
            XCTAssertThrowsError(try gate.begin(
                requiresResponsiveAudio: true,
                controllerIsReady: true
            ))

            var released: ResponsiveAudioSceneMutationGate.DeferredIntents?
            XCTAssertTrue(gate.finish(token) { released = $0 })
            let boundary = try XCTUnwrap(released?.automaticBoundary)
            XCTAssertEqual(
                boundary.controllerIdentifier,
                ObjectIdentifier(controller)
            )
            XCTAssertTrue(gate.automaticBoundaryDurabilityIsPending)
            XCTAssertThrowsError(try gate.begin(
                requiresResponsiveAudio: true,
                controllerIsReady: true
            )) { error in
                XCTAssertEqual(
                    error as? ResponsiveAudioSceneMutationGateError,
                    .automaticBoundaryDurabilityPending
                )
            }

            XCTAssertTrue(gate.finishAutomaticBoundary(boundary.token))
            XCTAssertFalse(gate.automaticBoundaryDurabilityIsPending)
            XCTAssertNotNil(try gate.begin(
                requiresResponsiveAudio: true,
                controllerIsReady: true
            ))
        }
    }

    func testBoundaryBlocksImmediateInputBeforeDurabilityDrainStarts() throws {
        var gate = ResponsiveAudioSceneMutationGate()
        let controller = BoundaryControllerIdentity()

        let admission = gate.receiveAutomaticBoundary(
            controllerIdentifier: ObjectIdentifier(controller)
        )
        guard case let .admitted(boundary) = admission else {
            return XCTFail("A boundary without an active scene must be admitted")
        }
        XCTAssertTrue(gate.automaticBoundaryDurabilityIsPending)
        XCTAssertThrowsError(try gate.begin(
            requiresResponsiveAudio: true,
            controllerIsReady: true
        )) { error in
            XCTAssertEqual(
                error as? ResponsiveAudioSceneMutationGateError,
                .automaticBoundaryDurabilityPending
            )
        }

        XCTAssertTrue(gate.finishAutomaticBoundary(boundary.token))
        XCTAssertNotNil(try gate.begin(
            requiresResponsiveAudio: true,
            controllerIsReady: true
        ))
    }

    func testOverlappingPhaseIsMaterializedOnlyAfterBoundaryDurability()
        throws {
        var gate = ResponsiveAudioSceneMutationGate()
        let controller = BoundaryControllerIdentity()
        let scene = try XCTUnwrap(try gate.begin(
            requiresResponsiveAudio: true,
            controllerIsReady: true
        ))

        XCTAssertEqual(
            gate.receiveAutomaticBoundary(
                controllerIdentifier: ObjectIdentifier(controller)
            ),
            .deferred
        )
        XCTAssertTrue(gate.deferPhaseIfNeeded(.engaged))

        var harness = DeferredBoundaryPhaseOrderingHarness()
        XCTAssertTrue(gate.finish(scene) { harness.accept($0) })
        let boundary = try XCTUnwrap(harness.boundary)
        XCTAssertEqual(
            boundary.controllerIdentifier,
            ObjectIdentifier(controller)
        )
        XCTAssertTrue(gate.automaticBoundaryDurabilityIsPending)
        XCTAssertNil(harness.materializedPhase)
        XCTAssertEqual(harness.events, [.boundaryQueued])

        harness.boundaryDidComplete(
            durably: gate.finishAutomaticBoundary(boundary.token)
        )

        XCTAssertFalse(gate.automaticBoundaryDurabilityIsPending)
        XCTAssertEqual(harness.materializedPhase, .engaged)
        XCTAssertEqual(
            harness.events,
            [.boundaryQueued, .boundaryDurable, .phaseMaterialized]
        )
    }

    func testDeferredBoundaryRejectsDifferentControllerAndDuplicateRelease()
        throws {
        var gate = ResponsiveAudioSceneMutationGate()
        let firstController = BoundaryControllerIdentity()
        let replacementController = BoundaryControllerIdentity()
        let scene = try XCTUnwrap(try gate.begin(
            requiresResponsiveAudio: true,
            controllerIsReady: true
        ))
        XCTAssertEqual(
            gate.receiveAutomaticBoundary(
                controllerIdentifier: ObjectIdentifier(firstController)
            ),
            .deferred
        )
        XCTAssertEqual(
            gate.receiveAutomaticBoundary(
                controllerIdentifier: ObjectIdentifier(replacementController)
            ),
            .rejected
        )

        var released: ResponsiveAudioSceneMutationGate.DeferredIntents?
        XCTAssertTrue(gate.finish(scene) { released = $0 })
        let boundary = try XCTUnwrap(released?.automaticBoundary)
        XCTAssertTrue(gate.finishAutomaticBoundary(boundary.token))
        XCTAssertFalse(gate.finishAutomaticBoundary(boundary.token))
    }
}

private enum BoundaryOverlapPoint: String, CaseIterable {
    case afterHistoricalAppendBeforeBridge
    case afterBridgeBeforeConditionalFollowUp
    case consequenceCompletion
}

private final class BoundaryControllerIdentity {}

/// Deterministic model of JourneyModel's callback seam: a phase delivered in
/// the same intent as an automatic boundary is retained until that boundary's
/// exact gate token has crossed durability. This deliberately has no clock or
/// transport dependency, so the overlap cannot turn into a timing-only test.
private struct DeferredBoundaryPhaseOrderingHarness {
    enum Event: Equatable {
        case boundaryQueued
        case boundaryDurable
        case phaseMaterialized
    }

    private(set) var boundary:
        ResponsiveAudioSceneMutationGate.AutomaticBoundaryIntent?
    private(set) var materializedPhase: ResponsiveInteractionAudioPhase?
    private(set) var events: [Event] = []
    private var retainedPhase: ResponsiveInteractionAudioPhase?

    mutating func accept(
        _ intents: ResponsiveAudioSceneMutationGate.DeferredIntents
    ) {
        if let automaticBoundary = intents.automaticBoundary {
            boundary = automaticBoundary
            retainedPhase = intents.phase
            events.append(.boundaryQueued)
            return
        }
        materialize(intents.phase)
    }

    mutating func boundaryDidComplete(durably: Bool) {
        guard durably else {
            retainedPhase = nil
            return
        }
        events.append(.boundaryDurable)
        materialize(retainedPhase)
        retainedPhase = nil
    }

    private mutating func materialize(
        _ phase: ResponsiveInteractionAudioPhase?
    ) {
        guard let phase else { return }
        materializedPhase = phase
        events.append(.phaseMaterialized)
    }
}

@MainActor
private final class ResponsiveAudioSceneMutationIntegrationHarness {
    private var gate = ResponsiveAudioSceneMutationGate()
    private(set) var snapshotMaterializationCount = 0
    private(set) var materializedIntents:
        ResponsiveAudioSceneMutationGate.DeferredIntents?

    func begin() throws -> ResponsiveAudioSceneMutationGate.Token {
        guard let token = try gate.begin(
            requiresResponsiveAudio: true,
            controllerIsReady: true
        ) else {
            throw ResponsiveAudioSceneMutationGateError.authoredAudioUnavailable
        }
        return token
    }

    func deferPhase(_ phase: ResponsiveInteractionAudioPhase) -> Bool {
        gate.deferPhaseIfNeeded(phase)
    }

    func deferSuspension(atEpochMillis: Int64) -> Bool {
        gate.deferSuspensionIfNeeded(atEpochMillis: atEpochMillis)
    }

    func finish(_ token: ResponsiveAudioSceneMutationGate.Token) {
        gate.finish(token) { [self] intents in
            materializedIntents = intents
            snapshotMaterializationCount += 1
        }
    }
}

private actor BlockingResponsiveAudioFollowUp {
    private var entered = false
    private var released = false
    private var enteredWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseContinuation: CheckedContinuation<Void, Never>?

    func enterAndWait() async {
        entered = true
        let waiters = enteredWaiters
        enteredWaiters.removeAll()
        waiters.forEach { $0.resume() }
        guard !released else { return }
        await withCheckedContinuation { releaseContinuation = $0 }
    }

    func waitUntilEntered() async {
        guard !entered else { return }
        await withCheckedContinuation { enteredWaiters.append($0) }
    }

    func release() {
        released = true
        releaseContinuation?.resume()
        releaseContinuation = nil
    }
}
