@testable import ChapterRuntime
@testable import ContentDelivery
@testable import ContentKit
import Foundation
import JourneyContent
import JourneyDomain
import ProgressStore
import SceneRuntime
import XCTest

@MainActor
final class AContinentRemadeSignedRuntimeTests: XCTestCase {
    private static let packageID: PackageID = "vertical-slice-development-v1"
    private static let chapterID: ChapterID = "first-farmers"
    private static let beatID: BeatID = "beat-first-farmers-continent-remade"
    private static let sceneID: SceneID = "scene-first-farmers-europe-transformation"
    private static let interactionID: InteractionID =
        "interaction-first-farmers-a-continent-remade"
    private static let effectID: WorldEffectID =
        "effect-first-farmers-a-continent-remade"
    private static let version = SchemaVersion(major: 1)

    func testSignedContinentRemadeRunsThreeStagesAcrossTouchVoiceOverRestoreAndReduceMotion()
        async throws {
        let fixture = try loadFixture()
        let initialState = try stateAtContinentRemade(fixture)
        let initialRuntime = try await makeRuntime(
            fixture: fixture,
            state: initialState,
            reduceMotion: false
        )
        let cursor = initialRuntime.controller.presentation.cursor
        XCTAssertEqual(cursor.beat.id, Self.beatID)
        XCTAssertEqual(cursor.scene.id, Self.sceneID)
        let interaction = try XCTUnwrap(cursor.beat.interaction)
        XCTAssertEqual(interaction.id, Self.interactionID)
        XCTAssertEqual(interaction.completionEffects.map(\.id), [Self.effectID])
        guard case let .transform(configuration) = interaction.grammar else {
            return XCTFail("A Continent Remade must remain a Transform interaction")
        }
        let stages = [
            TransformationStage(
                id: "danube-fields",
                controlID: "continental-spread",
                requiredAmount: 0.34
            ),
            TransformationStage(
                id: "loess-settlements",
                controlID: "continental-spread",
                requiredAmount: 0.7
            ),
            TransformationStage(
                id: "european-farming-belt",
                controlID: "continental-spread",
                requiredAmount: 1
            ),
        ]
        XCTAssertEqual(configuration.stages, stages)
        assertCanonicalTargets(in: initialRuntime, stages: stages)
        try await assertReduceMotionMapping(
            fixture: fixture,
            state: initialState,
            normalFrame: initialRuntime.controller.presentation.framePlan,
            stages: stages,
            expectedVariants: ["before", "before", "before"]
        )

        let dragHaptics = ContinentRemadeHapticSpy()
        let dragRuntime = try await makeRuntime(
            fixture: fixture,
            state: initialState,
            reduceMotion: false,
            hapticBridge: dragHaptics
        )
        let firstTarget = try target(for: stages[0], in: dragRuntime)
        let drag = try await dragRuntime.controller.submitTouch(
            .adjustTarget(
                viewportPoint: centroid(firstTarget.viewportPath),
                amount: stages[0].requiredAmount / 2
            )
        )
        XCTAssertEqual(
            drag.preview?.action,
            .transform(
                controlID: stages[0].controlID,
                amount: stages[0].requiredAmount / 2
            )
        )
        XCTAssertEqual(drag.preview?.feedback, .progress)
        XCTAssertEqual(drag.presentation.interactionFeedback, .progress)
        XCTAssertEqual(hapticSemantics(in: drag.durableCommit), [.drag])
        XCTAssertEqual(dragHaptics.semantics, [.drag])
        assertTransformProgress(
            in: drag.presentation.journeyState,
            completedStageCount: 0,
            currentAmount: stages[0].requiredAmount / 2
        )
        try await assertReduceMotionMapping(
            fixture: fixture,
            state: drag.presentation.journeyState,
            normalFrame: drag.presentation.framePlan,
            stages: stages,
            expectedVariants: ["active", "before", "before"]
        )

        let storeRoot = FileManager.default.temporaryDirectory.appending(
            path: "continent-remade-signed-runtime-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        defer { try? FileManager.default.removeItem(at: storeRoot) }
        let initialTouchStore = try ProgressStore(directoryURL: storeRoot)
        var touchRestoration = try await initialTouchStore.restore(
            initialState: initialState
        )
        var touchCommitter = DurableJourneyCommitter(
            restoredState: touchRestoration.state,
            lastSequence: touchRestoration.lastSequence,
            append: { request in try await initialTouchStore.append(request) },
            checkpoint: { commit in try await initialTouchStore.checkpoint(commit) }
        )
        let touchHaptics = ContinentRemadeHapticSpy()
        var touchRuntime = try await makeRuntime(
            fixture: fixture,
            committer: touchCommitter,
            reduceMotion: false,
            hapticBridge: touchHaptics
        )

        let semanticJournal = ContinentRemadeSequenceJournal()
        let semanticCommitter = DurableJourneyCommitter(
            restoredState: initialState,
            lastSequence: 0,
            append: { request in try await semanticJournal.append(request) }
        )
        let semanticHaptics = ContinentRemadeHapticSpy()
        let semanticRuntime = try await makeRuntime(
            fixture: fixture,
            committer: semanticCommitter,
            reduceMotion: false,
            hapticBridge: semanticHaptics
        )

        for (index, stage) in stages.enumerated() {
            let hitRegion = try target(for: stage, in: touchRuntime)
            let touch = try await touchRuntime.controller.submitTouch(
                .adjustTarget(
                    viewportPoint: centroid(hitRegion.viewportPath),
                    amount: stage.requiredAmount
                )
            )
            let elementID = "transform-\(stage.id)"
            let voiceOver = try await semanticRuntime.controller.submitVoiceOver(
                elementID: elementID,
                authoredAction: try authoredIncrement(
                    elementID: elementID,
                    in: semanticRuntime
                )
            )

            let expectedAction = InteractionAction.transform(
                controlID: stage.controlID,
                amount: stage.requiredAmount
            )
            let expectedFeedback: InteractionFeedback = index == stages.indices.last
                ? .completed
                : .threshold
            let expectedHaptic: HapticSemantic = index == stages.indices.last
                ? .seal
                : .break
            XCTAssertEqual(touch.preview?.action, expectedAction)
            XCTAssertEqual(voiceOver.preview?.action, expectedAction)
            XCTAssertEqual(touch.preview?.feedback, expectedFeedback)
            XCTAssertEqual(voiceOver.preview?.feedback, expectedFeedback)
            XCTAssertEqual(touch.presentation.interactionFeedback, expectedFeedback)
            XCTAssertEqual(voiceOver.presentation.interactionFeedback, expectedFeedback)
            XCTAssertEqual(hapticSemantics(in: touch.durableCommit), [expectedHaptic])
            XCTAssertEqual(hapticSemantics(in: voiceOver.durableCommit), [expectedHaptic])
            XCTAssertNil(touch.postCommitIssue)
            XCTAssertNil(voiceOver.postCommitIssue)
            XCTAssertEqual(
                touch.presentation.journeyState,
                voiceOver.presentation.journeyState,
                "Touch and VoiceOver diverged after \(stage.id)"
            )
            assertTransformProgress(
                in: touch.presentation.journeyState,
                completedStageCount: index + 1,
                currentAmount: 0
            )

            let touchCommit = try XCTUnwrap(touch.durableCommit)
            XCTAssertTrue(touchCommit.requiresCheckpoint)
            try await touchCommitter.checkpoint(touchCommit)
            let hapticsBeforeRelaunch = touchHaptics.semantics

            let reopenedTouchStore = try ProgressStore(directoryURL: storeRoot)
            touchRestoration = try await reopenedTouchStore.restore(
                initialState: initialState
            )
            XCTAssertEqual(
                touchRestoration.state,
                voiceOver.presentation.journeyState,
                "Cold restore lost \(stage.id)"
            )
            touchCommitter = DurableJourneyCommitter(
                restoredState: touchRestoration.state,
                lastSequence: touchRestoration.lastSequence,
                append: { request in try await reopenedTouchStore.append(request) },
                checkpoint: { commit in
                    try await reopenedTouchStore.checkpoint(commit)
                }
            )
            touchRuntime = try await makeRuntime(
                fixture: fixture,
                committer: touchCommitter,
                reduceMotion: false,
                hapticBridge: touchHaptics
            )
            XCTAssertEqual(touchRuntime.controller.presentation.cursor.beat.id, Self.beatID)
            XCTAssertNil(touchRuntime.controller.presentation.interactionFeedback)
            XCTAssertNil(touchRuntime.controller.presentation.directManipulation)
            XCTAssertEqual(
                touchHaptics.semantics,
                hapticsBeforeRelaunch,
                "Cold restore replayed a haptic after \(stage.id)"
            )

            let expectedVariants = stages.indices.map {
                $0 <= index ? "completed" : "before"
            }
            try await assertReduceMotionMapping(
                fixture: fixture,
                state: touchRestoration.state,
                normalFrame: touchRuntime.controller.presentation.framePlan,
                stages: stages,
                expectedVariants: expectedVariants
            )
        }

        XCTAssertEqual(touchHaptics.semantics, [.break, .break, .seal])
        XCTAssertEqual(semanticHaptics.semantics, [.break, .break, .seal])
        XCTAssertEqual(
            touchRuntime.controller.presentation.journeyState,
            semanticRuntime.controller.presentation.journeyState
        )
        XCTAssertEqual(
            touchRuntime.controller.presentation.journeyState.world.appliedEffects.filter {
                $0.id == Self.effectID
            }.count,
            1
        )
        XCTAssertTrue(
            touchRuntime.controller.presentation.journeyState.world.appliedEffectIDs.contains(
                Self.effectID
            )
        )
    }

    private struct TrustReceipt: Decodable {
        let packageID: PackageID
        let keyID: String
        let manifestDigest: String
        let trustedPublicKeyX963Base64: String
    }

    private struct FixtureAuthority {
        let packageRoot: URL
        let repository: ContentRepository
        let snapshot: VerifiedJourneyContentSnapshot
    }

    private enum FixtureError: Error {
        case malformedTrustReceipt
        case targetBeatUnavailable
        case rejectedBootstrapAction
    }

    private func loadFixture() throws -> FixtureAuthority {
        let locations = try fixtureLocations()
        let receipt = try JSONDecoder().decode(
            TrustReceipt.self,
            from: Data(contentsOf: locations.trustReceipt)
        )
        guard receipt.packageID == Self.packageID,
              receipt.keyID == "vertical-slice-development-key-v1",
              let publicKey = Data(
                  base64Encoded: receipt.trustedPublicKeyX963Base64
              ) else {
            throw FixtureError.malformedTrustReceipt
        }
        let expectedPackage = ContentPackageSpec(
            id: Self.packageID,
            version: Self.version,
            chapterIDs: [
                "first-farmers",
                "europe-holds-the-line",
                "european-world",
            ],
            maximumInstalledBytes: 750_000_000,
            minimumRuntime: Self.version,
            isEssentialInstall: true
        )
        let verified = try ContentPackageVerifier.admitPackageAtRuntime(
            at: locations.packageRoot,
            expectedPackage: expectedPackage,
            trustedPublicKeys: [receipt.keyID: publicKey],
            supportedSchema: Self.version,
            runtimeVersion: Self.version
        )
        guard verified.manifest.manifestDigest == receipt.manifestDigest else {
            throw FixtureError.malformedTrustReceipt
        }
        let repository = try ContentRepository(
            developmentVerticalSlice: verified
        )
        let generation = InstalledPackageGeneration(
            generationID: "continent-remade-signed-runtime-generation-v1",
            packageID: Self.packageID,
            packageVersion: Self.version,
            manifestDigest: verified.manifest.manifestDigest,
            relativePath: "vertical-slice-development-v1.runtimefixture",
            activationSequence: 1
        )
        let index = InstalledPackageIndex(
            nextActivationSequence: 2,
            generations: [generation],
            activeGenerationByPackage: [Self.packageID: generation.generationID]
        )
        let snapshot = VerifiedJourneyContentSnapshot(
            revision: 1,
            repository: repository,
            reconciledInstalledIndex: index,
            packageRootURLs: [Self.packageID: locations.packageRoot],
            verifiedPackagesByID: [Self.packageID: verified]
        )
        return FixtureAuthority(
            packageRoot: locations.packageRoot,
            repository: repository,
            snapshot: snapshot
        )
    }

    private func stateAtContinentRemade(
        _ fixture: FixtureAuthority
    ) throws -> JourneyState {
        var state = JourneyState(
            world: try WorldGraph(seed: fixture.repository.worldSeed)
        )
        let reducer = JourneyReducer()
        try apply(
            .installContent(packageID: Self.packageID, version: Self.version),
            reducer: reducer,
            to: &state
        )
        let coordinator = ChapterCoordinator(repository: fixture.repository)
        for action in try coordinator.beginActions(
            chapterID: Self.chapterID,
            state: state
        ) {
            try apply(action, reducer: reducer, to: &state)
        }
        let maximumBeatCount = try coordinator.currentCursor(
            state: state
        ).chapter.arcs.flatMap(\.beats).count
        var traversed = 0
        while try coordinator.currentCursor(state: state).beat.id != Self.beatID {
            traversed += 1
            guard traversed <= maximumBeatCount else {
                throw FixtureError.targetBeatUnavailable
            }
            let cursor = try coordinator.currentCursor(state: state)
            if let interaction = cursor.beat.interaction {
                for interactionAction in canonicalCompletionActions(
                    for: interaction
                ) {
                    try apply(
                        .interact(spec: interaction, action: interactionAction),
                        reducer: reducer,
                        to: &state
                    )
                }
            }
            for action in try coordinator.advanceActions(state: state).actions {
                try apply(action, reducer: reducer, to: &state)
            }
        }
        return state
    }

    private func canonicalCompletionActions(
        for interaction: InteractionSpec
    ) -> [InteractionAction] {
        switch interaction.grammar {
        case let .trace(configuration):
            return configuration.anchors.map(InteractionAction.trace)

        case let .allocate(configuration):
            var allocations = configuration.destinations.map {
                (destinationID: $0.id, units: $0.minimumUnits)
            }
            if let last = allocations.indices.last {
                let allocated = allocations.reduce(0) { $0 + $1.units }
                allocations[last].units += configuration.totalUnits - allocated
            }
            return allocations.map {
                .allocate(destinationID: $0.destinationID, units: $0.units)
            } + [.commitAllocation]

        case let .assemble(configuration):
            return configuration.components.map {
                .place(componentID: $0.id, slotID: $0.targetSlot)
            }

        case .pressure:
            return [
                .setPressure(forceID: "inhabited-stores", magnitude: 0.7),
                .advancePressure(elapsedMillis: 1_000),
            ]

        case let .transform(configuration):
            return configuration.stages.map {
                .transform(
                    controlID: $0.controlID,
                    amount: $0.requiredAmount
                )
            }
        }
    }

    private func apply(
        _ action: JourneyAction,
        reducer: JourneyReducer,
        to state: inout JourneyState
    ) throws {
        let effects = reducer.reduce(state: &state, action: action)
        guard !effects.contains(where: {
            if case .rejected = $0 { return true }
            return false
        }) else {
            throw FixtureError.rejectedBootstrapAction
        }
    }

    private func makeRuntime(
        fixture: FixtureAuthority,
        state: JourneyState,
        reduceMotion: Bool,
        hapticBridge: (any ChapterRuntimeHapticBridging)? = nil
    ) async throws -> VerifiedChapterSceneRuntime {
        let journal = ContinentRemadeSequenceJournal()
        let committer = DurableJourneyCommitter(
            restoredState: state,
            lastSequence: 0,
            append: { request in try await journal.append(request) }
        )
        return try await makeRuntime(
            fixture: fixture,
            committer: committer,
            reduceMotion: reduceMotion,
            hapticBridge: hapticBridge
        )
    }

    private func makeRuntime(
        fixture: FixtureAuthority,
        committer: DurableJourneyCommitter,
        reduceMotion: Bool,
        hapticBridge: (any ChapterRuntimeHapticBridging)? = nil
    ) async throws -> VerifiedChapterSceneRuntime {
        try await VerifiedChapterSceneRuntimeFactory.make(
            snapshot: fixture.snapshot,
            chapterID: Self.chapterID,
            committer: committer,
            viewportCropID: "baseline-393x852",
            reduceMotion: reduceMotion,
            hapticBridge: hapticBridge
        )
    }

    private func target(
        for stage: TransformationStage,
        in runtime: VerifiedChapterSceneRuntime
    ) throws -> SceneInteractionHitRegionPlan {
        try XCTUnwrap(
            runtime.controller.presentation.framePlan.interactionHitRegions.first {
                $0.interactionTargetID == "stage-\(stage.id)-target"
            }
        )
    }

    private func authoredIncrement(
        elementID: String,
        in runtime: VerifiedChapterSceneRuntime
    ) throws -> AccessibilityActionSpec {
        try XCTUnwrap(
            runtime.controller.presentation.cursor.accessibility.elements
                .first { $0.id == elementID }?.actions.first {
                    $0.kind == .increment
                }
        )
    }

    private func assertCanonicalTargets(
        in runtime: VerifiedChapterSceneRuntime,
        stages: [TransformationStage],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let regions = runtime.controller.presentation.framePlan.interactionHitRegions
        XCTAssertEqual(regions.count, stages.count, file: file, line: line)
        for stage in stages {
            let region = regions.first {
                $0.interactionTargetID == "stage-\(stage.id)-target"
            }
            XCTAssertEqual(
                region?.layerID,
                SceneLayerID("stage-\(stage.id)"),
                file: file,
                line: line
            )
            XCTAssertEqual(
                region?.accessibilityElementID,
                "transform-\(stage.id)",
                file: file,
                line: line
            )
            XCTAssertEqual(region?.viewportPath.count, 4, file: file, line: line)
        }
    }

    private func assertTransformProgress(
        in state: JourneyState,
        completedStageCount: Int,
        currentAmount: Double,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard let runtimeState = state.activeChapter?.interaction,
              case let .transform(progress) = runtimeState.progress else {
            return XCTFail("Expected durable Transform progress", file: file, line: line)
        }
        XCTAssertEqual(
            progress.completedStageCount,
            completedStageCount,
            file: file,
            line: line
        )
        XCTAssertEqual(
            progress.currentAmount,
            currentAmount,
            accuracy: 0.000_000_001,
            file: file,
            line: line
        )
    }

    private func assertReduceMotionMapping(
        fixture: FixtureAuthority,
        state: JourneyState,
        normalFrame: SceneFramePlan,
        stages: [TransformationStage],
        expectedVariants: [String],
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        let reduced = try await makeRuntime(
            fixture: fixture,
            state: state,
            reduceMotion: true
        ).controller.presentation.framePlan
        XCTAssertFalse(normalFrame.reduceMotion, file: file, line: line)
        XCTAssertTrue(reduced.reduceMotion, file: file, line: line)
        XCTAssertFalse(reduced.camera.followsAuthoredRail, file: file, line: line)
        XCTAssertTrue(
            reduced.drawCommands.allSatisfy { $0.motion == .still },
            file: file,
            line: line
        )
        XCTAssertTrue(
            reduced.atmosphere.allSatisfy { $0.travel == .zero },
            file: file,
            line: line
        )
        let expected = Dictionary(
            uniqueKeysWithValues: zip(stages, expectedVariants).map {
                (SceneLayerID("stage-\($0.0.id)"), $0.1)
            }
        )
        XCTAssertEqual(
            selectedStageVariants(in: normalFrame, stages: stages),
            expected,
            file: file,
            line: line
        )
        XCTAssertEqual(
            selectedStageVariants(in: reduced, stages: stages),
            expected,
            file: file,
            line: line
        )
        XCTAssertEqual(
            Set(reduced.drawCommands.compactMap { command -> String? in
                guard case let .reduceMotionStaticStratum(id) = command.source else {
                    return nil
                }
                return id
            }),
            Set(["static-underlay", "static-foreground"]),
            file: file,
            line: line
        )
    }

    private func selectedStageVariants(
        in frame: SceneFramePlan,
        stages: [TransformationStage]
    ) -> [SceneLayerID: String] {
        let stageLayers = Set(stages.map { SceneLayerID("stage-\($0.id)") })
        return Dictionary(
            uniqueKeysWithValues: frame.drawCommands.compactMap { command in
                guard case let .layer(layerID, variantID?) = command.source,
                      stageLayers.contains(layerID) else {
                    return nil
                }
                return (layerID, variantID)
            }
        )
    }

    private func hapticSemantics(
        in commit: DurableJourneyCommit?
    ) -> [HapticSemantic] {
        commit?.effects.compactMap { effect in
            guard case let .haptic(semantic) = effect else { return nil }
            return semantic
        } ?? []
    }

    private func centroid(_ points: [SceneFramePoint]) -> SceneFramePoint {
        SceneFramePoint(
            x: points.reduce(0) { $0 + $1.x } / Double(points.count),
            y: points.reduce(0) { $0 + $1.y } / Double(points.count)
        )
    }

    private func fixtureLocations() throws -> (
        packageRoot: URL,
        trustReceipt: URL
    ) {
#if os(iOS)
        let bundle = Bundle(for: Self.self)
        guard let packageRoot = bundle.url(
            forResource: "vertical-slice-development-v1",
            withExtension: "runtimefixture"
        ), let trustReceipt = bundle.url(
            forResource: "vertical-slice-development-trust-receipt",
            withExtension: "json"
        ) else {
            throw FixtureError.malformedTrustReceipt
        }
        return (packageRoot, trustReceipt)
#else
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "phase2/runtime-fixture", directoryHint: .isDirectory)
            .standardizedFileURL
        return (
            root.appending(
                path: "compiled/vertical-slice-development-v1.runtimefixture",
                directoryHint: .isDirectory
            ),
            root.appending(
                path: "vertical-slice-development-trust-receipt.json"
            )
        )
#endif
    }
}

@MainActor
private final class ContinentRemadeHapticSpy: ChapterRuntimeHapticBridging {
    private(set) var semantics: [HapticSemantic] = []

    func play(_ semantic: HapticSemantic) {
        semantics.append(semantic)
    }
}

private actor ContinentRemadeSequenceJournal {
    private var sequence: UInt64 = 0

    func append(_ request: ConditionalJourneyAppendRequest) throws -> UInt64 {
        guard request.expectedPreviousSequence == sequence else {
            throw ContinentRemadeJournalError.sequenceMismatch
        }
        sequence += 1
        return sequence
    }
}

private enum ContinentRemadeJournalError: Error {
    case sequenceMismatch
}
