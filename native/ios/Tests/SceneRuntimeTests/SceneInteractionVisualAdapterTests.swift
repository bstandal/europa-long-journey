@testable import ContentKit
import ContentKitTestSupport
import CryptoKit
import Foundation
import JourneyDomain
@testable import SceneRuntime
import XCTest

final class SceneInteractionVisualAdapterTests: XCTestCase {
    func testTraceMapsInitialResistanceLatchedAnchorsAndCompletionToAuthoredRouteStates() throws {
        let fixture = VisualAdapterFixtures.trace()
        var driver = try SceneInteractionDriver(spec: fixture.interaction)

        try assertResolved(driver.state, in: fixture, equals: ["route": "idle"])

        let begin = try driver.submit(.touch(.begin))
        XCTAssertEqual(begin.feedback, .progress)
        try assertResolved(driver.state, in: fixture, equals: ["route": "tracing"])

        let resistance = try driver.submit(
            .touch(.trace(NormalizedPoint(x: 0.9, y: 0.1)))
        )
        XCTAssertEqual(resistance.feedback, .resistance)
        try assertResolved(driver.state, in: fixture, equals: ["route": "tracing"])

        _ = try driver.submit(.semantic(.trace(VisualAdapterFixtures.traceAnchors[0])))
        try assertResolved(driver.state, in: fixture, equals: ["route": "bank-reached"])

        _ = try driver.submit(.semantic(.trace(VisualAdapterFixtures.traceAnchors[1])))
        try assertResolved(driver.state, in: fixture, equals: ["route": "ford-reached"])

        _ = try driver.submit(.semantic(.trace(VisualAdapterFixtures.traceAnchors[2])))
        XCTAssertEqual(driver.state.phase, .complete)
        try assertResolved(driver.state, in: fixture, equals: ["route": "completed"])
    }

    func testTraceReachedAnchorVariantStaysLatchedAcrossMissRestoreAndReduceMotion() throws {
        let fixture = VisualAdapterFixtures.trace()
        var driver = try SceneInteractionDriver(spec: fixture.interaction)

        _ = try driver.submit(.touch(.trace(VisualAdapterFixtures.traceAnchors[0])))
        let miss = try driver.submit(
            .touch(.trace(NormalizedPoint(x: 0.9, y: 0.1)))
        )
        XCTAssertEqual(miss.feedback, .resistance)
        guard case let .trace(progress) = driver.state.progress else {
            return XCTFail("Expected durable Trace progress")
        }
        XCTAssertEqual(progress.reachedAnchorCount, 1)

        let beforeKill = VisualAdapterFixtures.session(
            scene: fixture.scene,
            interaction: driver.state,
            deterministicTick: 7_220_027,
            cameraAnchor: 0.58
        )
        let afterKill = try JSONDecoder().decode(
            ChapterSession.self,
            from: JSONEncoder().encode(beforeKill)
        )
        let inventory = try makeInventory(for: fixture.scene)

        for reduceMotion in [false, true] {
            let beforeRequest = try SceneFrameRequestFactory.make(
                scene: fixture.scene,
                session: beforeKill,
                viewportCropID: "baseline-393x852",
                interaction: fixture.interaction,
                reduceMotion: reduceMotion
            )
            let afterRequest = try SceneFrameRequestFactory.make(
                scene: fixture.scene,
                session: afterKill,
                viewportCropID: "baseline-393x852",
                interaction: fixture.interaction,
                reduceMotion: reduceMotion
            )
            let beforePlan = try SceneFramePlanner.plan(
                scene: fixture.scene,
                request: beforeRequest,
                assets: inventory
            )
            let afterPlan = try SceneFramePlanner.plan(
                scene: fixture.scene,
                request: afterRequest,
                assets: inventory
            )

            XCTAssertEqual(afterRequest, beforeRequest)
            XCTAssertEqual(afterPlan, beforePlan)
            XCTAssertEqual(
                selectedVariants(in: afterPlan),
                ["route": "bank-reached"]
            )
        }
    }

    func testAssembleMapsAvailabilityResistancePlacementAndCompletionPerComponent() throws {
        let fixture = VisualAdapterFixtures.assemble()
        var driver = try SceneInteractionDriver(spec: fixture.interaction)

        try assertResolved(
            driver.state,
            in: fixture,
            equals: [
                "foundation": "available",
                "frame": "resisted",
                "roof": "resisted",
            ]
        )

        let resistance = try driver.submit(
            .touch(.place(componentID: "roof", slotID: "cover"))
        )
        XCTAssertEqual(resistance.feedback, .resistance)
        try assertResolved(
            driver.state,
            in: fixture,
            equals: [
                "foundation": "available",
                "frame": "resisted",
                "roof": "resisted",
            ]
        )

        _ = try driver.submit(
            .semantic(.place(componentID: "foundation", slotID: "ground"))
        )
        try assertResolved(
            driver.state,
            in: fixture,
            equals: [
                "foundation": "placed",
                "frame": "available",
                "roof": "resisted",
            ]
        )

        _ = try driver.submit(.touch(.place(componentID: "frame", slotID: "walls")))
        let completion = try driver.submit(
            .semantic(.place(componentID: "roof", slotID: "cover"))
        )
        XCTAssertEqual(completion.feedback, .completed)
        try assertResolved(
            driver.state,
            in: fixture,
            equals: [
                "foundation": "placed",
                "frame": "placed",
                "roof": "placed",
            ]
        )
    }

    func testPressureMapsRestingResistanceThresholdAndCompletionWithoutInventingForceVariants() throws {
        let fixture = VisualAdapterFixtures.pressure()
        var driver = try SceneInteractionDriver(spec: fixture.interaction)

        try assertResolved(driver.state, in: fixture, equals: ["frontier-system": "resting"])

        _ = try driver.submit(
            .touch(.setPressure(forceID: "defence", magnitude: 0.45))
        )
        try assertResolved(driver.state, in: fixture, equals: ["frontier-system": "resisting"])

        let threshold = try driver.submit(
            .semantic(.advancePressure(elapsedMillis: 500))
        )
        XCTAssertEqual(threshold.feedback, .threshold)
        try assertResolved(driver.state, in: fixture, equals: ["frontier-system": "stable"])

        _ = try driver.submit(
            .touch(.setPressure(forceID: "defence", magnitude: 0))
        )
        let resistance = try driver.submit(.touch(.advancePressure(elapsedMillis: 1)))
        XCTAssertEqual(resistance.feedback, .resistance)
        try assertResolved(driver.state, in: fixture, equals: ["frontier-system": "broken"])

        _ = try driver.submit(
            .semantic(.setPressure(forceID: "defence", magnitude: 0.45))
        )
        _ = try driver.submit(.semantic(.advancePressure(elapsedMillis: 1_000)))
        let completion = try driver.submit(
            .touch(.advancePressure(elapsedMillis: 1_000))
        )
        XCTAssertEqual(completion.feedback, .completed)
        try assertResolved(driver.state, in: fixture, equals: ["frontier-system": "stable"])
    }

    func testTransformMapsSharedLayerAcrossBeforeActiveStageThresholdAndCompletion() throws {
        let fixture = VisualAdapterFixtures.transform()
        var driver = try SceneInteractionDriver(spec: fixture.interaction)

        try assertResolved(driver.state, in: fixture, equals: ["ground": "ground-before"])

        let resistance = try driver.submit(
            .touch(.transform(controlID: "seed", amount: 0.4))
        )
        XCTAssertEqual(resistance.feedback, .resistance)
        try assertResolved(driver.state, in: fixture, equals: ["ground": "ground-before"])

        _ = try driver.submit(
            .semantic(.transform(controlID: "field", amount: 0.3))
        )
        try assertResolved(driver.state, in: fixture, equals: ["ground": "ground-active"])

        _ = try driver.submit(
            .touch(.transform(controlID: "field", amount: 0.6))
        )
        try assertResolved(driver.state, in: fixture, equals: ["ground": "seed-before"])

        _ = try driver.submit(
            .semantic(.transform(controlID: "seed", amount: 0.5))
        )
        try assertResolved(driver.state, in: fixture, equals: ["ground": "seed-active"])

        let completion = try driver.submit(
            .touch(.transform(controlID: "seed", amount: 1))
        )
        XCTAssertEqual(completion.feedback, .completed)
        try assertResolved(driver.state, in: fixture, equals: ["ground": "seed-completed"])
    }

    func testEveryAdapterRejectsForgedRuntimeStateAndMismatchedProgressGrammar() throws {
        let trace = VisualAdapterFixtures.trace()
        var forgedTrace = InteractionRuntimeState(spec: trace.interaction)
        forgedTrace.phase = .complete
        forgedTrace.progress = .trace(TraceProgress(reachedAnchorCount: 1, lastPoint: nil))
        try assertInvalidRuntime(forgedTrace, in: trace)

        let assemble = VisualAdapterFixtures.assemble()
        var forgedAssembly = InteractionRuntimeState(spec: assemble.interaction)
        forgedAssembly.phase = .active
        forgedAssembly.progress = .assemble(
            AssembleProgress(
                placements: [AssemblyPlacement(componentID: "roof", slotID: "cover")]
            )
        )
        try assertInvalidRuntime(forgedAssembly, in: assemble)

        let pressure = VisualAdapterFixtures.pressure()
        var forgedPressure = InteractionRuntimeState(spec: pressure.interaction)
        forgedPressure.phase = .active
        forgedPressure.progress = .pressure(
            PressureProgress(
                values: [
                    PressureValue(forceID: "attack", magnitude: 0.2),
                    PressureValue(forceID: "defence", magnitude: 0.45),
                ]
            )
        )
        try assertInvalidRuntime(forgedPressure, in: pressure)

        let transform = VisualAdapterFixtures.transform()
        var forgedTransform = InteractionRuntimeState(spec: transform.interaction)
        forgedTransform.phase = .complete
        forgedTransform.progress = .transform(
            TransformProgress(completedStageCount: 1, currentAmount: 0)
        )
        try assertInvalidRuntime(forgedTransform, in: transform)

        var mismatched = InteractionRuntimeState(spec: trace.interaction)
        mismatched.progress = .assemble(AssembleProgress())
        XCTAssertThrowsError(
            try SceneInteractionVisualStateResolver.resolve(
                scene: trace.scene,
                interaction: trace.interaction,
                runtimeState: mismatched
            )
        ) { error in
            XCTAssertEqual(
                error as? SceneInteractionVisualStateError,
                .mismatchedGrammar
            )
        }
    }

    func testEveryAdapterRequiresEveryAndOnlyStatefulLayerExactlyOnce() throws {
        for fixture in VisualAdapterFixtures.all(includeUnboundStatefulLayer: true) {
            XCTAssertThrowsError(
                try SceneInteractionVisualStateResolver.resolve(
                    scene: fixture.scene,
                    interaction: fixture.interaction,
                    runtimeState: InteractionRuntimeState(spec: fixture.interaction)
                ),
                "Unbound stateful layer escaped for \(fixture.interaction.id)"
            ) { error in
                XCTAssertEqual(
                    error as? SceneInteractionVisualStateError,
                    .invalidRuntimeState
                )
            }
        }
    }

    func testEveryAdapterRejectsAllocateOnlyEphemeralManipulationState() throws {
        let direct = SceneDirectManipulationState.targetContact(
            targetID: "route-control",
            progress: 0.5
        )
        for fixture in VisualAdapterFixtures.all() {
            XCTAssertThrowsError(
                try SceneInteractionVisualStateResolver.resolve(
                    scene: fixture.scene,
                    interaction: fixture.interaction,
                    runtimeState: InteractionRuntimeState(spec: fixture.interaction),
                    directManipulation: direct
                )
            ) { error in
                XCTAssertEqual(
                    error as? SceneInteractionVisualStateError,
                    .invalidDirectManipulation
                )
            }
        }
    }

    func testTouchAndVoiceOverInputPathsProduceIdenticalVisualStateAtEveryStep() throws {
        for fixture in VisualAdapterFixtures.all() {
            var touch = try SceneInteractionDriver(spec: fixture.interaction)
            var voiceOver = try SceneInteractionDriver(spec: fixture.interaction)
            for action in fixture.completionActions {
                let touchResponse = try touch.submit(.touch(action))
                let voiceOverResponse = try voiceOver.submit(.semantic(action))
                XCTAssertEqual(touchResponse, voiceOverResponse, "Reducer parity: \(fixture.interaction.id)")

                let touchVisual = try SceneInteractionVisualStateResolver.resolve(
                    scene: fixture.scene,
                    interaction: fixture.interaction,
                    runtimeState: touch.state
                )
                let voiceOverVisual = try SceneInteractionVisualStateResolver.resolve(
                    scene: fixture.scene,
                    interaction: fixture.interaction,
                    runtimeState: voiceOver.state
                )
                XCTAssertEqual(touchVisual, voiceOverVisual, "Visual parity: \(fixture.interaction.id)")
            }
            XCTAssertEqual(touch.state.phase, .complete)
            XCTAssertEqual(voiceOver.state.phase, .complete)
        }
    }

    func testHardKillSnapshotRestoreRebuildsExactNormalAndReduceMotionFramePlans() throws {
        for fixture in VisualAdapterFixtures.all() {
            var driver = try SceneInteractionDriver(spec: fixture.interaction)
            _ = try driver.submit(.touch(fixture.intermediateAction))
            let beforeKill = VisualAdapterFixtures.session(
                scene: fixture.scene,
                interaction: driver.state,
                deterministicTick: 7_220_024,
                cameraAnchor: 0.63
            )
            let encoded = try JSONEncoder().encode(beforeKill)
            let afterKill = try JSONDecoder().decode(ChapterSession.self, from: encoded)
            let inventory = try makeInventory(for: fixture.scene)

            for reduceMotion in [false, true] {
                let beforeRequest = try SceneFrameRequestFactory.make(
                    scene: fixture.scene,
                    session: beforeKill,
                    viewportCropID: "baseline-393x852",
                    interaction: fixture.interaction,
                    reduceMotion: reduceMotion
                )
                let afterRequest = try SceneFrameRequestFactory.make(
                    scene: fixture.scene,
                    session: afterKill,
                    viewportCropID: "baseline-393x852",
                    interaction: fixture.interaction,
                    reduceMotion: reduceMotion
                )
                let beforePlan = try SceneFramePlanner.plan(
                    scene: fixture.scene,
                    request: beforeRequest,
                    assets: inventory
                )
                let afterPlan = try SceneFramePlanner.plan(
                    scene: fixture.scene,
                    request: afterRequest,
                    assets: inventory
                )

                XCTAssertEqual(afterKill, beforeKill)
                XCTAssertEqual(afterRequest, beforeRequest)
                XCTAssertEqual(afterPlan, beforePlan)
                XCTAssertEqual(
                    selectedVariants(in: afterPlan),
                    afterRequest.visualState.activeLayerVariants
                )
            }
        }
    }

    func testReduceMotionPreservesEveryCausalVariantAndRemovesSpatialMotion() throws {
        for fixture in VisualAdapterFixtures.all() {
            var driver = try SceneInteractionDriver(spec: fixture.interaction)
            _ = try driver.submit(.touch(fixture.intermediateAction))
            let session = VisualAdapterFixtures.session(
                scene: fixture.scene,
                interaction: driver.state,
                deterministicTick: 7_220_025,
                cameraAnchor: 0.47
            )
            let inventory = try makeInventory(for: fixture.scene)
            let normalRequest = try SceneFrameRequestFactory.make(
                scene: fixture.scene,
                session: session,
                viewportCropID: "baseline-393x852",
                interaction: fixture.interaction,
                reduceMotion: false
            )
            let reducedRequest = try SceneFrameRequestFactory.make(
                scene: fixture.scene,
                session: session,
                viewportCropID: "baseline-393x852",
                interaction: fixture.interaction,
                reduceMotion: true
            )
            let reduced = try SceneFramePlanner.plan(
                scene: fixture.scene,
                request: reducedRequest,
                assets: inventory
            )

            XCTAssertEqual(
                reducedRequest.visualState.activeLayerVariants,
                normalRequest.visualState.activeLayerVariants
            )
            XCTAssertEqual(
                selectedVariants(in: reduced),
                reducedRequest.visualState.activeLayerVariants
            )
            XCTAssertTrue(reduced.drawCommands.allSatisfy { $0.motion == .still })
            XCTAssertTrue(reduced.atmosphere.allSatisfy { $0.travel == .zero })
            XCTAssertFalse(reduced.camera.followsAuthoredRail)
        }
    }

    func testDisplayedHitRegionsResolveAllFourNonAllocateGrammarsToCanonicalActions() throws {
        let trace = VisualAdapterFixtures.trace()
        let traceState = InteractionRuntimeState(spec: trace.interaction)
        let traceFrame = try makeFrame(for: trace, runtimeState: traceState)
        let traceRegion = try XCTUnwrap(
            traceFrame.interactionHitRegions.first {
                $0.interactionTargetID == "route-control"
            }
        )
        let tracePoint = centroid(of: traceRegion.viewportPath)
        let traceHit = try XCTUnwrap(
            SceneTouchGeometryResolver.target(at: tracePoint, in: traceFrame)
        )
        let traceResolution = try SceneTouchActionResolver.resolve(
            .trace(viewportPoint: tracePoint),
            scene: trace.scene,
            interaction: trace.interaction,
            runtimeState: traceState,
            frame: traceFrame
        )
        XCTAssertEqual(traceResolution.action, .trace(traceHit.masterPosition))
        XCTAssertEqual(traceResolution.targetID, "route-control")

        let assemble = VisualAdapterFixtures.assemble()
        let assembleState = InteractionRuntimeState(spec: assemble.interaction)
        let assembleFrame = try makeFrame(for: assemble, runtimeState: assembleState)
        let foundationSource = try targetCentroid(
            "foundation-target",
            in: assembleFrame
        )
        let foundationSlot = try targetCentroid(
            "foundation-slot",
            in: assembleFrame
        )
        let assembleResolution = try SceneTouchActionResolver.resolve(
            .assembleDrop(
                sourceViewportPoint: foundationSource,
                slotViewportPoint: foundationSlot,
                progress: 1
            ),
            scene: assemble.scene,
            interaction: assemble.interaction,
            runtimeState: assembleState,
            frame: assembleFrame
        )
        XCTAssertEqual(
            assembleResolution.action,
            .place(componentID: "foundation", slotID: "ground")
        )

        let pressure = VisualAdapterFixtures.pressure()
        let pressureState = InteractionRuntimeState(spec: pressure.interaction)
        let pressureFrame = try makeFrame(for: pressure, runtimeState: pressureState)
        let defencePoint = try targetCentroid("defence-target", in: pressureFrame)
        let pressureResolution = try SceneTouchActionResolver.resolve(
            .adjustTarget(viewportPoint: defencePoint, amount: 0.45),
            scene: pressure.scene,
            interaction: pressure.interaction,
            runtimeState: pressureState,
            frame: pressureFrame
        )
        XCTAssertEqual(
            pressureResolution.action,
            .setPressure(forceID: "defence", magnitude: 0.45)
        )
        let pressureHold = try SceneTouchActionResolver.resolve(
            .holdPressure(elapsedMillis: 500),
            scene: pressure.scene,
            interaction: pressure.interaction,
            runtimeState: pressureState,
            frame: pressureFrame
        )
        XCTAssertEqual(
            pressureHold.action,
            .advancePressure(elapsedMillis: 500)
        )

        let transform = VisualAdapterFixtures.transform()
        let transformState = InteractionRuntimeState(spec: transform.interaction)
        let transformFrame = try makeFrame(for: transform, runtimeState: transformState)
        let clearPoint = try targetCentroid("clear-target", in: transformFrame)
        let transformResolution = try SceneTouchActionResolver.resolve(
            .adjustTarget(viewportPoint: clearPoint, amount: 0.3),
            scene: transform.scene,
            interaction: transform.interaction,
            runtimeState: transformState,
            frame: transformFrame
        )
        XCTAssertEqual(
            transformResolution.action,
            .transform(controlID: "field", amount: 0.3)
        )
    }

    func testTraceDeferredPriorityMatchesResolverThroughParallaxAndWind()
        throws {
        let fixture = VisualAdapterFixtures.trace()
        var driver = try SceneInteractionDriver(spec: fixture.interaction)
        _ = try driver.submit(
            .touch(.trace(VisualAdapterFixtures.traceAnchors[0]))
        )
        let base = try makeFrame(
            for: fixture,
            runtimeState: driver.state
        )
        guard case let .trace(visual)? =
            fixture.scene.interactionVisualBinding,
              case let .trace(configuration) = fixture.interaction.grammar
        else {
            return XCTFail("Expected the Trace laboratory fixture")
        }
        let motion = SceneLayerMotionState(
            parallaxOffset: SceneFrameVector(dx: 0.06, dy: 0.02),
            windOffset: SceneFrameVector(dx: 0.04, dy: 0.015),
            focusAmount: 0.5
        )
        let frame = try replacingMotion(
            in: base,
            for: visual,
            with: motion
        )
        let anchorIndex = 1
        let anchor = configuration.anchors[anchorIndex]
        let viewportPoint = SceneFramePoint(
            x: (anchor.x - frame.camera.sourceRect.x)
                / frame.camera.sourceRect.width
                + motion.parallaxOffset.dx + motion.windOffset.dx,
            y: (anchor.y - frame.camera.sourceRect.y)
                / frame.camera.sourceRect.height
                + motion.parallaxOffset.dy + motion.windOffset.dy
        )

        let legacyUnbound = try SceneTouchGeometryResolver.masterPoint(
            for: viewportPoint,
            in: frame
        )
        XCTAssertGreaterThan(
            legacyUnbound.distance(to: anchor),
            configuration.tolerance,
            "The old still-space classifier must miss this visible anchor"
        )

        let hit = try XCTUnwrap(
            SceneTouchGeometryResolver.target(at: viewportPoint, in: frame)
        )
        XCTAssertEqual(hit.interactionTargetID, visual.interactionTargetID)
        XCTAssertEqual(hit.layerID, visual.layerID)
        XCTAssertEqual(hit.masterPosition.x, anchor.x, accuracy: 1e-12)
        XCTAssertEqual(hit.masterPosition.y, anchor.y, accuracy: 1e-12)

        let priority = TraceDeferredSamplePriority.classify(
            viewportPoint: viewportPoint,
            frame: frame,
            visual: visual,
            configuration: configuration,
            reachedAnchorCount: anchorIndex
        )
        XCTAssertEqual(priority.protectedAnchorIndex, anchorIndex)

        let resolution = try SceneTouchActionResolver.resolve(
            .trace(viewportPoint: viewportPoint),
            scene: fixture.scene,
            interaction: fixture.interaction,
            runtimeState: driver.state,
            frame: frame
        )
        XCTAssertEqual(resolution.action, .trace(anchor))
    }

    func testTouchResolverRejectsWrongDisplayedTargetBeforeReducerSubmission() throws {
        let fixture = VisualAdapterFixtures.transform()
        let runtimeState = InteractionRuntimeState(spec: fixture.interaction)
        let frame = try makeFrame(for: fixture, runtimeState: runtimeState)
        let futureStagePoint = try targetCentroid("sow-target", in: frame)

        XCTAssertThrowsError(
            try SceneTouchActionResolver.resolve(
                .adjustTarget(viewportPoint: futureStagePoint, amount: 0.3),
                scene: fixture.scene,
                interaction: fixture.interaction,
                runtimeState: runtimeState,
                frame: frame
            )
        ) { error in
            XCTAssertEqual(
                error as? SceneTouchActionResolverError,
                .wrongTarget("sow-target")
            )
        }
    }

    private func assertResolved(
        _ runtimeState: InteractionRuntimeState,
        in fixture: VisualAdapterFixture,
        equals expected: [SceneLayerID: String],
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let state = try SceneInteractionVisualStateResolver.resolve(
            scene: fixture.scene,
            interaction: fixture.interaction,
            runtimeState: runtimeState
        )
        XCTAssertEqual(state.activeLayerVariants, expected, file: file, line: line)
        let statefulLayers = fixture.scene.layers.filter { !$0.stateVariants.isEmpty }
        XCTAssertEqual(
            Set(state.activeLayerVariants.keys),
            Set(statefulLayers.map(\.id)),
            file: file,
            line: line
        )
        for (layerID, variantID) in state.activeLayerVariants {
            XCTAssertTrue(
                statefulLayers.first(where: { $0.id == layerID })?
                    .stateVariants.contains(where: { $0.id == variantID }) == true,
                file: file,
                line: line
            )
        }
    }

    private func assertInvalidRuntime(
        _ runtimeState: InteractionRuntimeState,
        in fixture: VisualAdapterFixture,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        XCTAssertThrowsError(
            try SceneInteractionVisualStateResolver.resolve(
                scene: fixture.scene,
                interaction: fixture.interaction,
                runtimeState: runtimeState
            ),
            file: file,
            line: line
        ) { error in
            XCTAssertEqual(
                error as? SceneInteractionVisualStateError,
                .invalidRuntimeState,
                file: file,
                line: line
            )
        }
    }

    private func makeInventory(for scene: SceneSpec) throws -> SceneAssetInventory {
        let root = FileManager.default.temporaryDirectory.appending(
            path: "visual-adapter-tests-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }

        var records: [PackageFileRecord] = []
        for packagePath in referencedAssetPaths(in: scene).sorted() {
            let url = root.appending(path: packagePath, directoryHint: .notDirectory)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let bytes = Data([0x01])
            try bytes.write(to: url, options: .atomic)
            records.append(
                PackageFileRecord(
                    path: packagePath,
                    bytes: Int64(bytes.count),
                    sha256: SHA256.hash(data: bytes)
                        .map { String(format: "%02x", $0) }
                        .joined()
                )
            )
        }
        let version = SchemaVersion(major: 1)
        let packageID: PackageID = "non-shipping-visual-adapter-lab"
        return try SceneAssetInventory(
            verifiedPackage: VerifiedContentPackage(
                manifest: SignedPackageManifest(
                    packageID: packageID,
                    packageVersion: version,
                    schemaVersion: version,
                    minimumRuntime: version,
                    files: records,
                    manifestDigest: "test-only",
                    signature: PackageSignature(
                        algorithm: ContentPackageVerifier.signatureAlgorithm,
                        keyID: "test-only",
                        value: "test-only"
                    )
                ),
                payload: ContentPackagePayload(
                    schemaVersion: version,
                    packageID: packageID,
                    worldSeed: WorldSeedSpec(nodes: [], traces: []),
                    chapters: [],
                    scenes: [scene],
                    audioTimelines: [],
                    accessibility: []
                )
            ),
            activatedPackageRoot: root
        )
    }

    private func makeFrame(
        for fixture: VisualAdapterFixture,
        runtimeState: InteractionRuntimeState
    ) throws -> SceneFramePlan {
        let session = VisualAdapterFixtures.session(
            scene: fixture.scene,
            interaction: runtimeState,
            deterministicTick: 7_220_026,
            cameraAnchor: 0.5
        )
        let request = try SceneFrameRequestFactory.make(
            scene: fixture.scene,
            session: session,
            viewportCropID: "baseline-393x852",
            interaction: fixture.interaction,
            reduceMotion: false
        )
        return try SceneFramePlanner.plan(
            scene: fixture.scene,
            request: request,
            assets: makeInventory(for: fixture.scene)
        )
    }

    func testAssembleDropAcceptanceFollowsAuthoredDependencyDataOnly() throws {
        let strictFixture = VisualAdapterFixtures.assemble()
        let strictState = InteractionRuntimeState(spec: strictFixture.interaction)
        let strictFrame = try makeFrame(
            for: strictFixture,
            runtimeState: strictState
        )
        let roofSource = try targetCentroid("roof-target", in: strictFrame)
        let roofSlot = try targetCentroid("roof-slot", in: strictFrame)
        let strictResolution = try SceneTouchActionResolver.resolve(
            .assembleDrop(
                sourceViewportPoint: roofSource,
                slotViewportPoint: roofSlot,
                progress: 1
            ),
            scene: strictFixture.scene,
            interaction: strictFixture.interaction,
            runtimeState: strictState,
            frame: strictFrame
        )
        let strictPreview = try SceneInteractionDriver.preview(
            spec: strictFixture.interaction,
            state: strictState,
            input: .touch(try XCTUnwrap(strictResolution.action))
        )
        XCTAssertEqual(strictPreview.feedback, .resistance)

        guard case let .assemble(configuration) = strictFixture.interaction.grammar else {
            return XCTFail("Fixture must remain Assemble")
        }
        let relaxedInteraction = InteractionSpec(
            id: strictFixture.interaction.id,
            prompt: strictFixture.interaction.prompt,
            grammar: .assemble(
                AssembleInteractionSpec(
                    components: configuration.components.map {
                        AssemblyComponent(
                            id: $0.id,
                            targetSlot: $0.targetSlot,
                            prerequisites: []
                        )
                    }
                )
            ),
            completionEffects: strictFixture.interaction.completionEffects,
            accessibilityID: strictFixture.interaction.accessibilityID
        )
        let relaxedFixture = VisualAdapterFixture(
            scene: strictFixture.scene,
            interaction: relaxedInteraction,
            intermediateAction: strictFixture.intermediateAction,
            completionActions: strictFixture.completionActions
        )
        let relaxedState = InteractionRuntimeState(spec: relaxedInteraction)
        let relaxedFrame = try makeFrame(
            for: relaxedFixture,
            runtimeState: relaxedState
        )
        let relaxedRoofSource = try targetCentroid("roof-target", in: relaxedFrame)
        let relaxedRoofSlot = try targetCentroid("roof-slot", in: relaxedFrame)
        let relaxedResolution = try SceneTouchActionResolver.resolve(
            .assembleDrop(
                sourceViewportPoint: relaxedRoofSource,
                slotViewportPoint: relaxedRoofSlot,
                progress: 1
            ),
            scene: relaxedFixture.scene,
            interaction: relaxedInteraction,
            runtimeState: relaxedState,
            frame: relaxedFrame
        )
        let relaxedPreview = try SceneInteractionDriver.preview(
            spec: relaxedInteraction,
            state: relaxedState,
            input: .touch(try XCTUnwrap(relaxedResolution.action))
        )
        XCTAssertEqual(
            strictResolution.action,
            relaxedResolution.action,
            "Gesture resolution must not encode the dependency graph"
        )
        XCTAssertEqual(relaxedPreview.feedback, .progress)
    }

    private func targetCentroid(
        _ targetID: String,
        in frame: SceneFramePlan
    ) throws -> SceneFramePoint {
        let region = try XCTUnwrap(
            frame.interactionHitRegions.first {
                $0.interactionTargetID == targetID
            }
        )
        return centroid(of: region.viewportPath)
    }

    private func centroid(of path: [SceneFramePoint]) -> SceneFramePoint {
        let count = Double(path.count)
        return SceneFramePoint(
            x: path.reduce(0) { $0 + $1.x } / count,
            y: path.reduce(0) { $0 + $1.y } / count
        )
    }

    private func replacingMotion(
        in frame: SceneFramePlan,
        for visual: SceneTraceVisualBinding,
        with motion: SceneLayerMotionState
    ) throws -> SceneFramePlan {
        let original = try XCTUnwrap(frame.drawCommands.first(where: {
            guard case let .layer(layerID, _) = $0.source else {
                return false
            }
            return layerID == visual.layerID
        }))
        let oldOffset = SceneFrameVector(
            dx: original.motion.parallaxOffset.dx
                + original.motion.windOffset.dx,
            dy: original.motion.parallaxOffset.dy
                + original.motion.windOffset.dy
        )
        let newOffset = SceneFrameVector(
            dx: motion.parallaxOffset.dx + motion.windOffset.dx,
            dy: motion.parallaxOffset.dy + motion.windOffset.dy
        )
        let delta = SceneFrameVector(
            dx: newOffset.dx - oldOffset.dx,
            dy: newOffset.dy - oldOffset.dy
        )
        let commands = frame.drawCommands.map { command in
            guard case let .layer(layerID, _) = command.source,
                  layerID == visual.layerID else {
                return command
            }
            return SceneDrawCommand(
                source: command.source,
                authoredOrder: command.authoredOrder,
                depth: command.depth,
                asset: command.asset,
                masks: command.masks,
                masterFrame: command.masterFrame,
                viewportFrame: command.viewportFrame,
                opacity: command.opacity,
                blendMode: command.blendMode,
                motion: motion
            )
        }
        let regions = frame.interactionHitRegions.map { region in
            guard region.interactionTargetID == visual.interactionTargetID,
                  region.layerID == visual.layerID else {
                return region
            }
            return SceneInteractionHitRegionPlan(
                interactionTargetID: region.interactionTargetID,
                layerID: region.layerID,
                accessibilityElementID: region.accessibilityElementID,
                viewportPath: region.viewportPath.map {
                    SceneFramePoint(
                        x: $0.x + delta.dx,
                        y: $0.y + delta.dy
                    )
                }
            )
        }
        return SceneFramePlan(
            sceneID: frame.sceneID,
            viewportCropID: frame.viewportCropID,
            viewport: frame.viewport,
            deterministicTick: frame.deterministicTick,
            reduceMotion: frame.reduceMotion,
            camera: frame.camera,
            drawCommands: commands,
            atmosphere: frame.atmosphere,
            interactionSourceHitRegion: frame.interactionSourceHitRegion,
            interactionHitRegions: regions,
            interactionResponse: frame.interactionResponse,
            safeTextRegions: frame.safeTextRegions
        )
    }

    private func referencedAssetPaths(in scene: SceneSpec) -> Set<String> {
        var paths = Set(scene.reduceMotionComposition.strata.compactMap(\.assetPath))
        for layer in scene.layers {
            paths.insert(layer.assetPath)
            for path in layer.masks.assetPathsForTest { paths.insert(path) }
            for variant in layer.stateVariants {
                paths.insert(variant.assetPath)
                for path in variant.masks.assetPathsForTest { paths.insert(path) }
            }
        }
        return paths
    }

    private func selectedVariants(in plan: SceneFramePlan) -> [SceneLayerID: String] {
        Dictionary(uniqueKeysWithValues: plan.drawCommands.compactMap { command in
            guard case let .layer(layerID, variantID?) = command.source else { return nil }
            return (layerID, variantID)
        })
    }
}

private struct VisualAdapterFixture {
    let scene: SceneSpec
    let interaction: InteractionSpec
    let intermediateAction: InteractionAction
    let completionActions: [InteractionAction]
}

/// In-memory NON_SHIPPING laboratory scenes. They prove the runtime contracts
/// without claiming an authored historical scene or production asset approval.
private enum VisualAdapterFixtures {
    static let traceAnchors = [
        NormalizedPoint(x: 0.2, y: 0.5),
        NormalizedPoint(x: 0.5, y: 0.5),
        NormalizedPoint(x: 0.8, y: 0.5),
    ]
    static let traceAnchorIDs = ["river-bank", "ford", "far-bank"]

    static func all(includeUnboundStatefulLayer: Bool = false) -> [VisualAdapterFixture] {
        [
            trace(includeUnboundStatefulLayer: includeUnboundStatefulLayer),
            assemble(includeUnboundStatefulLayer: includeUnboundStatefulLayer),
            pressure(includeUnboundStatefulLayer: includeUnboundStatefulLayer),
            transform(includeUnboundStatefulLayer: includeUnboundStatefulLayer),
        ]
    }

    static func trace(includeUnboundStatefulLayer: Bool = false) -> VisualAdapterFixture {
        let interaction = makeInteraction(
            id: "trace-route",
            grammar: .trace(
                TraceInteractionSpec(
                    anchors: traceAnchors,
                    anchorIDs: traceAnchorIDs,
                    tolerance: 0.05
                )
            )
        )
        let binding = SceneInteractionVisualBinding.trace(
            SceneTraceVisualBinding(
                interactionID: interaction.id,
                interactionTargetID: "route-control",
                layerID: "route",
                idleVariantID: "idle",
                tracingVariantID: "tracing",
                reachedAnchorVariants: [
                    SceneTraceReachedAnchorVisualBinding(
                        anchorID: "river-bank",
                        variantID: "bank-reached"
                    ),
                    SceneTraceReachedAnchorVisualBinding(
                        anchorID: "ford",
                        variantID: "ford-reached"
                    ),
                ],
                completedVariantID: "completed"
            )
        )
        return VisualAdapterFixture(
            scene: makeScene(
                id: "lab-trace-scene",
                layers: [
                    layer(
                        "route",
                        variants: [
                            "idle", "tracing", "bank-reached", "ford-reached", "completed",
                        ]
                    ),
                ],
                targets: [traceTarget("route-control", layerID: "route")],
                binding: binding,
                includeUnboundStatefulLayer: includeUnboundStatefulLayer
            ),
            interaction: interaction,
            intermediateAction: .trace(traceAnchors[0]),
            completionActions: traceAnchors.map(InteractionAction.trace)
        )
    }

    static func assemble(includeUnboundStatefulLayer: Bool = false) -> VisualAdapterFixture {
        let interaction = makeInteraction(
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
        let componentBindings = [
            componentBinding(
                "foundation",
                sourceTargetID: "foundation-target",
                slotTargetID: "foundation-slot",
                layerID: "foundation"
            ),
            componentBinding(
                "frame",
                sourceTargetID: "frame-target",
                slotTargetID: "frame-slot",
                layerID: "frame"
            ),
            componentBinding(
                "roof",
                sourceTargetID: "roof-target",
                slotTargetID: "roof-slot",
                layerID: "roof"
            ),
        ]
        return VisualAdapterFixture(
            scene: makeScene(
                id: "lab-assemble-scene",
                layers: [
                    layer("foundation", variants: ["available", "resisted", "placed"]),
                    layer("frame", variants: ["available", "resisted", "placed"]),
                    layer("roof", variants: ["available", "resisted", "placed"]),
                ],
                targets: [
                    target("foundation-target", layerID: "foundation", column: 0, row: 0),
                    target("foundation-slot", layerID: "foundation", column: 0, row: 1),
                    target("frame-target", layerID: "frame", column: 1, row: 0),
                    target("frame-slot", layerID: "frame", column: 1, row: 1),
                    target("roof-target", layerID: "roof", column: 2, row: 0),
                    target("roof-slot", layerID: "roof", column: 2, row: 1),
                ],
                binding: .assemble(
                    SceneAssembleVisualBinding(
                        interactionID: interaction.id,
                        components: componentBindings
                    )
                ),
                includeUnboundStatefulLayer: includeUnboundStatefulLayer
            ),
            interaction: interaction,
            intermediateAction: .place(componentID: "foundation", slotID: "ground"),
            completionActions: [
                .place(componentID: "foundation", slotID: "ground"),
                .place(componentID: "frame", slotID: "walls"),
                .place(componentID: "roof", slotID: "cover"),
            ]
        )
    }

    static func pressure(includeUnboundStatefulLayer: Bool = false) -> VisualAdapterFixture {
        let interaction = makeInteraction(
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
        return VisualAdapterFixture(
            scene: makeScene(
                id: "lab-pressure-scene",
                layers: [
                    layer("attack-force"),
                    layer("defence-force"),
                    layer(
                        "frontier-system",
                        variants: ["resting", "resisting", "stable", "broken"]
                    ),
                ],
                targets: [target("defence-target", layerID: "defence-force", column: 1)],
                binding: .pressure(
                    ScenePressureVisualBinding(
                        interactionID: interaction.id,
                        forces: [
                            ScenePressureForceVisualBinding(
                                forceID: "attack",
                                layerID: "attack-force"
                            ),
                            ScenePressureForceVisualBinding(
                                forceID: "defence",
                                layerID: "defence-force",
                                interactionTargetID: "defence-target"
                            ),
                        ],
                        systemLayerID: "frontier-system",
                        restingVariantID: "resting",
                        resistingVariantID: "resisting",
                        stableVariantID: "stable",
                        brokenVariantID: "broken"
                    )
                ),
                includeUnboundStatefulLayer: includeUnboundStatefulLayer
            ),
            interaction: interaction,
            intermediateAction: .setPressure(forceID: "defence", magnitude: 0.45),
            completionActions: [
                .setPressure(forceID: "defence", magnitude: 0.45),
                .advancePressure(elapsedMillis: 600),
                .advancePressure(elapsedMillis: 600),
            ]
        )
    }

    static func transform(includeUnboundStatefulLayer: Bool = false) -> VisualAdapterFixture {
        let interaction = makeInteraction(
            id: "transform-ground",
            grammar: .transform(
                TransformInteractionSpec(
                    stages: [
                        TransformationStage(id: "clear", controlID: "field", requiredAmount: 0.6),
                        TransformationStage(id: "sow", controlID: "seed", requiredAmount: 1),
                    ]
                )
            )
        )
        return VisualAdapterFixture(
            scene: makeScene(
                id: "lab-transform-scene",
                layers: [
                    layer(
                        "ground",
                        variants: [
                            "ground-before", "ground-active", "ground-cleared",
                            "seed-before", "seed-active", "seed-completed",
                        ]
                    ),
                ],
                targets: [
                    target("clear-target", layerID: "ground", column: 0),
                    target("sow-target", layerID: "ground", column: 2),
                ],
                binding: .transform(
                    SceneTransformVisualBinding(
                        interactionID: interaction.id,
                        stages: [
                            SceneTransformationStageVisualBinding(
                                stageID: "clear",
                                interactionTargetID: "clear-target",
                                layerID: "ground",
                                beforeVariantID: "ground-before",
                                activeVariantID: "ground-active",
                                completedVariantID: "ground-cleared"
                            ),
                            SceneTransformationStageVisualBinding(
                                stageID: "sow",
                                interactionTargetID: "sow-target",
                                layerID: "ground",
                                beforeVariantID: "seed-before",
                                activeVariantID: "seed-active",
                                completedVariantID: "seed-completed"
                            ),
                        ]
                    )
                ),
                includeUnboundStatefulLayer: includeUnboundStatefulLayer
            ),
            interaction: interaction,
            intermediateAction: .transform(controlID: "field", amount: 0.3),
            completionActions: [
                .transform(controlID: "field", amount: 0.6),
                .transform(controlID: "seed", amount: 1),
            ]
        )
    }

    static func session(
        scene: SceneSpec,
        interaction: InteractionRuntimeState,
        deterministicTick: UInt64,
        cameraAnchor: Double
    ) -> ChapterSession {
        ChapterSession(
            chapterID: "non-shipping-lab",
            packageID: "non-shipping-visual-adapter-lab",
            contentVersion: SchemaVersion(major: 1),
            arcID: "non-shipping-lab-arc",
            beatID: "non-shipping-lab-beat",
            sceneVisualSnapshot: SceneVisualSnapshot(
                sceneID: scene.id,
                deterministicTick: deterministicTick
            ),
            interaction: interaction,
            cameraAnchor: cameraAnchor
        )
    }

    private static func makeInteraction(
        id: InteractionID,
        grammar: InteractionSpec.Grammar
    ) -> InteractionSpec {
        InteractionSpec(
            id: id,
            prompt: "Act on the historical mechanism.",
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

    private static func makeScene(
        id: SceneID,
        layers authoredLayers: [SceneLayerSpec],
        targets: [SceneInteractionTargetBinding],
        binding: SceneInteractionVisualBinding,
        includeUnboundStatefulLayer: Bool
    ) -> SceneSpec {
        var layers = [layer("world-background")] + authoredLayers
        if includeUnboundStatefulLayer {
            layers.append(layer("unbound-state", variants: ["unbound-idle"]))
        }
        layers = layers.enumerated().map { index, source in
            SceneLayerSpec(
                id: source.id,
                order: index,
                assetPath: source.assetPath,
                frame: source.frame,
                depth: source.depth,
                opacity: source.opacity,
                blendMode: source.blendMode,
                masks: source.masks,
                motion: source.motion,
                stateVariants: source.stateVariants
            )
        }
        let crop = baselineCrop
        let overlays = layers.filter { !$0.stateVariants.isEmpty }.map {
            ReduceMotionStratum(
                id: "\($0.id.rawValue)-state",
                kind: .stateOverlay,
                layerID: $0.id
            )
        }
        return SceneSpec(
            id: id,
            sceneCanvas: SceneCanvasSpec(
                canvas: ScenePixelSize(width: 1_179, height: 2_556),
                cameraTravelBounds: NormalizedRect(x: 0.2, y: 0.2, width: 0.6, height: 0.6),
                authoredOverscanFraction: 0.15,
                viewportCrops: [crop]
            ),
            layers: layers,
            cameraRail: CameraRail(
                keyframes: [
                    CameraKeyframe(
                        progress: 0,
                        center: NormalizedPoint(x: 0.5, y: 0.5),
                        scale: 1
                    ),
                    CameraKeyframe(
                        progress: 1,
                        center: NormalizedPoint(x: 0.5, y: 0.5),
                        scale: 1
                    ),
                ]
            ),
            atmosphere: [
                AtmosphereSpec(
                    kind: .dust,
                    density: 0.2,
                    velocity: SignedUnitVector(dx: 0.1, dy: 0),
                    deterministicSeed: 42
                ),
            ],
            interactionTargets: targets,
            interactionVisualBinding: binding,
            reduceMotionComposition: ReduceMotionComposition(
                canvas: ScenePixelSize(width: 1_179, height: 2_556),
                viewportCrops: [crop],
                strata: [
                    ReduceMotionStratum(
                        id: "world-underlay",
                        kind: .staticPlate,
                        assetPath: "assets/\(id.rawValue)/reduced-underlay.png"
                    ),
                ] + overlays + [
                    ReduceMotionStratum(
                        id: "foreground-occlusion",
                        kind: .staticPlate,
                        assetPath: "assets/\(id.rawValue)/reduced-foreground.png"
                    ),
                ]
            ),
            mechanismFocus: "The authored historical mechanism changes visibly.",
            accessibilityID: AccessibilityID("access-\(id.rawValue)")
        )
    }

    private static let baselineCrop = SceneViewportCrop(
        id: "baseline-393x852",
        viewport: SceneViewportSize(widthPoints: 393, heightPoints: 852),
        sourceRect: NormalizedRect(x: 0.15, y: 0.15, width: 0.7, height: 0.7),
        safeTextRegions: [
            SceneSafeTextRegion(
                id: "narrative-copy",
                rect: NormalizedRect(x: 0.18, y: 0.16, width: 0.5, height: 0.12)
            ),
        ]
    )

    private static func layer(
        _ id: SceneLayerID,
        variants: [String] = []
    ) -> SceneLayerSpec {
        SceneLayerSpec(
            id: id,
            order: 0,
            assetPath: "assets/lab/\(id.rawValue)/base.png",
            frame: NormalizedRect(x: 0, y: 0, width: 1, height: 1),
            depth: variants.isEmpty ? 0.2 : 0.6,
            motion: SceneLayerMotion(
                parallaxFactor: variants.isEmpty ? 0.05 : 0.2,
                windResponse: 0,
                focusResponse: variants.isEmpty ? 0 : 0.25
            ),
            stateVariants: variants.map {
                SceneLayerStateVariant(
                    id: $0,
                    assetPath: "assets/lab/\(id.rawValue)/\($0).png"
                )
            }
        )
    }

    private static func target(
        _ id: String,
        layerID: SceneLayerID,
        column: Int,
        row: Int? = nil
    ) -> SceneInteractionTargetBinding {
        let x = [0.22, 0.44, 0.66][column]
        let y = row.map { [0.34, 0.62][$0] } ?? 0.44
        return SceneInteractionTargetBinding(
            interactionTargetID: id,
            layerID: layerID,
            hitRegion: SceneHitRegion(
                path: [
                    NormalizedPoint(x: x, y: y),
                    NormalizedPoint(x: x + 0.12, y: y),
                    NormalizedPoint(x: x + 0.12, y: y + 0.12),
                    NormalizedPoint(x: x, y: y + 0.12),
                ]
            ),
            accessibilityElementID: "\(id)-accessibility"
        )
    }

    private static func traceTarget(
        _ id: String,
        layerID: SceneLayerID
    ) -> SceneInteractionTargetBinding {
        SceneInteractionTargetBinding(
            interactionTargetID: id,
            layerID: layerID,
            hitRegion: SceneHitRegion(
                path: [
                    NormalizedPoint(x: 0.18, y: 0.44),
                    NormalizedPoint(x: 0.82, y: 0.44),
                    NormalizedPoint(x: 0.82, y: 0.56),
                    NormalizedPoint(x: 0.18, y: 0.56),
                ]
            ),
            accessibilityElementID: "\(id)-accessibility"
        )
    }

    private static func componentBinding(
        _ componentID: String,
        sourceTargetID: String,
        slotTargetID: String,
        layerID: SceneLayerID
    ) -> SceneAssemblyComponentVisualBinding {
        SceneAssemblyComponentVisualBinding(
            componentID: componentID,
            sourceInteractionTargetID: sourceTargetID,
            slotInteractionTargetID: slotTargetID,
            layerID: layerID,
            availableVariantID: "available",
            resistedVariantID: "resisted",
            placedVariantID: "placed"
        )
    }
}

private extension SceneLayerMaskSet {
    var assetPathsForTest: [String] {
        [
            alphaMaskAssetPath,
            occlusionMaskAssetPath,
            depthMaskAssetPath,
            lightMaskAssetPath,
        ].compactMap { $0 }
    }
}
