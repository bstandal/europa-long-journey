import CryptoKit
import Foundation
import JourneyDomain
@testable import ContentKit
@testable import SceneRuntime
import XCTest

final class SceneInteractionVisualStateTests: XCTestCase {
    func testHarvestAllocateInitialPartialAndCompletedStatesSelectOnlyAuthoredVariants() throws {
        let fixture = try loadHarvestFixture()
        let scene = fixture.scene
        let interaction = makeTestOnlyHarvestInteraction(fixture)

        try scene.validate()
        try interaction.validate()
        try scene.validateInteractionVisualBinding(to: interaction)
        XCTAssertEqual(
            fixture.interactionContract.interactionSpecApproval,
            "SEPARATE_EDITOR_APPROVAL_REQUIRED"
        )

        let initial = InteractionRuntimeState(spec: interaction)
        let initialVisualState = try SceneInteractionVisualStateResolver.resolve(
            scene: scene,
            interaction: interaction,
            runtimeState: initial
        )
        XCTAssertEqual(
            initialVisualState.activeLayerVariants,
            layerVariants(fixture.interactionContract.initialLayerVariants)
        )
        assertEverySelectedVariantIsAuthored(initialVisualState, in: scene)

        let partial = makeAllocationState(
            interaction: interaction,
            phase: .active,
            allocations: ["food": 2, "reserve": 4, "seed": 0]
        )
        let partialVisualState = try SceneInteractionVisualStateResolver.resolve(
            scene: scene,
            interaction: interaction,
            runtimeState: partial
        )
        XCTAssertEqual(
            partialVisualState.activeLayerVariants,
            [
                "central-harvest": "reduced",
                "winter-store": "receiving",
                "protected-reserve": "receiving",
                "spring-seed": "empty",
            ]
        )
        assertEverySelectedVariantIsAuthored(partialVisualState, in: scene)

        var completed = InteractionRuntimeState(spec: interaction)
        for allocation in HarvestTestOnlyCompletion.allocations {
            _ = try InteractionReducer.reduce(
                state: &completed,
                spec: interaction,
                action: .allocate(
                    destinationID: allocation.destinationID,
                    units: allocation.units
                )
            )
        }
        let completion = try InteractionReducer.reduce(
            state: &completed,
            spec: interaction,
            action: .commitAllocation
        )
        XCTAssertEqual(completion.feedback, .completed)
        XCTAssertEqual(completed.phase, .complete)

        let completedVisualState = try SceneInteractionVisualStateResolver.resolve(
            scene: scene,
            interaction: interaction,
            runtimeState: completed
        )
        XCTAssertEqual(
            completedVisualState.activeLayerVariants,
            layerVariants(fixture.interactionContract.completionLayerVariants)
        )
        assertEverySelectedVariantIsAuthored(completedVisualState, in: scene)
    }

    func testHarvestResolverRejectsOverAllocationAndForgedCompletion() throws {
        let fixture = try loadHarvestFixture()
        let interaction = makeTestOnlyHarvestInteraction(fixture)

        let overAllocated = makeAllocationState(
            interaction: interaction,
            phase: .active,
            allocations: ["food": 5, "reserve": 4, "seed": 4]
        )
        XCTAssertThrowsError(
            try SceneInteractionVisualStateResolver.resolve(
                scene: fixture.scene,
                interaction: interaction,
                runtimeState: overAllocated
            )
        ) { error in
            XCTAssertEqual(
                error as? SceneInteractionVisualStateError,
                .invalidAllocation
            )
        }

        let forgedCompletion = makeAllocationState(
            interaction: interaction,
            phase: .complete,
            allocations: ["food": 3, "reserve": 6, "seed": 3]
        )
        XCTAssertThrowsError(
            try SceneInteractionVisualStateResolver.resolve(
                scene: fixture.scene,
                interaction: interaction,
                runtimeState: forgedCompletion
            )
        ) { error in
            XCTAssertEqual(
                error as? SceneInteractionVisualStateError,
                .invalidAllocation
            )
        }
    }

    func testHarvestDirectStateRequiresSourceAlphaAndReducerFeedback() throws {
        let fixture = try loadHarvestFixture()
        let interaction = makeTestOnlyHarvestInteraction(fixture)
        let runtimeState = makeAllocationState(
            interaction: interaction,
            phase: .active,
            allocations: ["food": 2, "reserve": 1, "seed": 0]
        )

        for invalidContact in [
            SceneDirectManipulationState.contact(
                at: NormalizedPoint(x: 0.5, y: 0.74),
                progress: 0,
                sourceAlphaHitConfirmed: false
            ),
            SceneDirectManipulationState.contact(
                at: NormalizedPoint(x: 0.05, y: 0.05),
                progress: 0,
                sourceAlphaHitConfirmed: true
            ),
        ] {
            XCTAssertThrowsError(
                try SceneInteractionVisualStateResolver.resolve(
                    scene: fixture.scene,
                    interaction: interaction,
                    runtimeState: runtimeState,
                    directManipulation: invalidContact
                )
            ) { error in
                XCTAssertEqual(
                    error as? SceneInteractionVisualStateError,
                    .invalidDirectManipulation
                )
            }
        }

        XCTAssertThrowsError(
            try SceneInteractionVisualStateResolver.resolve(
                scene: fixture.scene,
                interaction: interaction,
                runtimeState: runtimeState,
                directManipulation: .acceptedAfterReducer(
                    targetID: "winter-food-target",
                    destinationUnits: 3,
                    progress: 1
                )
            )
        ) { error in
            XCTAssertEqual(
                error as? SceneInteractionVisualStateError,
                .invalidDirectManipulation
            )
        }

        let accepted = try SceneInteractionVisualStateResolver.resolve(
            scene: fixture.scene,
            interaction: interaction,
            runtimeState: runtimeState,
            directManipulation: .acceptedAfterReducer(
                targetID: "winter-food-target",
                destinationUnits: 2,
                progress: 1
            )
        )
        XCTAssertEqual(accepted.directManipulation?.phase, .accepted)
    }

    func testHarvestDirectManipulationPhasesProduceDeterministicResponsePlans() throws {
        let fixture = try loadHarvestFixture()
        let interaction = makeTestOnlyHarvestInteraction(fixture)
        let runtimeState = makeAllocationState(
            interaction: interaction,
            phase: .active,
            allocations: ["food": 2, "reserve": 1, "seed": 0]
        )
        let session = makeSession(
            scene: fixture.scene,
            interaction: runtimeState,
            cameraAnchor: 0.32,
            deterministicTick: 18_423_001
        )
        let inventory = try makeInventory(for: fixture.scene)
        let cases: [DirectManipulationExpectation] = [
            DirectManipulationExpectation(
                state: SceneDirectManipulationState.contact(
                    at: NormalizedPoint(x: 0.5, y: 0.74),
                    progress: 0.05,
                    sourceAlphaHitConfirmed: true
                ),
                targetID: nil,
                contactAmount: 0.35,
                resistanceAmount: 0,
                expectsTransferPath: false
            ),
            DirectManipulationExpectation(
                state: SceneDirectManipulationState.carrying(
                    at: NormalizedPoint(x: 0.44, y: 0.69),
                    progress: 0.45,
                    sourceAlphaHitConfirmed: true
                ),
                targetID: nil,
                contactAmount: 0.15,
                resistanceAmount: 0,
                expectsTransferPath: false
            ),
            DirectManipulationExpectation(
                state: SceneDirectManipulationState.targetContact(
                    targetID: "winter-food-target",
                    progress: 0.9
                ),
                targetID: "winter-food-target",
                contactAmount: 1,
                resistanceAmount: 0,
                expectsTransferPath: true
            ),
            DirectManipulationExpectation(
                state: SceneDirectManipulationState.resistanceAfterReducerRejection(
                    targetID: "spring-seed-target",
                    progress: 0.75
                ),
                targetID: "spring-seed-target",
                contactAmount: 0.8,
                resistanceAmount: 1,
                expectsTransferPath: true
            ),
        ]

        for expectation in cases {
            let request = try SceneFrameRequestFactory.make(
                scene: fixture.scene,
                session: session,
                viewportCropID: "baseline-393x852",
                interaction: interaction,
                directManipulation: expectation.state,
                reduceMotion: false
            )
            let first = try SceneFramePlanner.plan(
                scene: fixture.scene,
                request: request,
                assets: inventory
            )
            let second = try SceneFramePlanner.plan(
                scene: fixture.scene,
                request: request,
                assets: inventory
            )
            let response = try XCTUnwrap(first.interactionResponse)

            XCTAssertEqual(first.interactionResponse, second.interactionResponse)
            XCTAssertEqual(response.phase, expectation.state.phase)
            XCTAssertEqual(response.targetID, expectation.targetID)
            XCTAssertEqual(response.transferLayerID, "hands-and-grain")
            XCTAssertEqual(response.progress, expectation.state.progress)
            XCTAssertEqual(response.contactAmount, expectation.contactAmount)
            XCTAssertEqual(response.resistanceAmount, expectation.resistanceAmount)
            XCTAssertEqual(
                response.viewportTransferPath.isEmpty,
                !expectation.expectsTransferPath
            )
            XCTAssertNotNil(response.viewportMaterialPosition)
        }
    }

    func testHarvestTransferPathUsesResourceTransferAndDestinationTransforms() throws {
        let fixture = try loadHarvestFixture()
        let interaction = makeTestOnlyHarvestInteraction(fixture)
        guard case let .allocate(binding)? = fixture.scene.interactionVisualBinding else {
            return XCTFail("Harvest requires its Allocate visual binding")
        }
        let runtimeState = InteractionRuntimeState(spec: interaction)
        let inventory = try makeInventory(for: fixture.scene)

        for cameraAnchor in [0.0, 0.16, 0.32, 0.5, 0.68, 0.84, 1.0] {
            for cropID in ["baseline-393x852", "largest-430x932"] {
                for destination in binding.destinations {
                    let session = makeSession(
                        scene: fixture.scene,
                        interaction: runtimeState,
                        cameraAnchor: cameraAnchor,
                        deterministicTick: 18_423_010
                    )
                    let request = try SceneFrameRequestFactory.make(
                        scene: fixture.scene,
                        session: session,
                        viewportCropID: cropID,
                        interaction: interaction,
                        directManipulation: .targetContact(
                            targetID: destination.interactionTargetID,
                            progress: 0.9
                        ),
                        reduceMotion: false
                    )
                    let plan = try SceneFramePlanner.plan(
                        scene: fixture.scene,
                        request: request,
                        assets: inventory
                    )
                    let response = try XCTUnwrap(plan.interactionResponse)
                    let sourceMotion = try XCTUnwrap(
                        layerMotion(binding.resource.layerID, in: plan)
                    )
                    let transferMotion = try XCTUnwrap(
                        layerMotion(binding.transferLayerID, in: plan)
                    )
                    let destinationMotion = try XCTUnwrap(
                        layerMotion(destination.layerID, in: plan)
                    )
                    let first = try XCTUnwrap(destination.transferPath.first)
                    let last = try XCTUnwrap(destination.transferPath.last)

                    XCTAssertEqual(
                        response.viewportTransferPath.first,
                        project(first, through: plan.camera.sourceRect, motion: sourceMotion)
                    )
                    for index in destination.transferPath.indices.dropFirst().dropLast() {
                        XCTAssertEqual(
                            response.viewportTransferPath[index],
                            project(
                                destination.transferPath[index],
                                through: plan.camera.sourceRect,
                                motion: transferMotion
                            )
                        )
                    }
                    XCTAssertEqual(
                        response.viewportTransferPath.last,
                        project(last, through: plan.camera.sourceRect, motion: destinationMotion)
                    )
                    XCTAssertEqual(
                        response.viewportMaterialPosition,
                        response.viewportTransferPath.last
                    )

                    let hitRegion = try XCTUnwrap(
                        plan.interactionHitRegions.first(where: {
                            $0.interactionTargetID == destination.interactionTargetID
                        })
                    )
                    XCTAssertTrue(
                        point(try XCTUnwrap(response.viewportTransferPath.last), inside: hitRegion.viewportPath),
                        "\(destination.interactionTargetID) endpoint detached at \(cameraAnchor) in \(cropID)"
                    )
                }
            }
        }
    }

    func testHarvestReduceMotionPreservesCausalVariantsWithoutSpatialMaterialTravel() throws {
        let fixture = try loadHarvestFixture()
        let interaction = makeTestOnlyHarvestInteraction(fixture)
        let runtimeState = makeAllocationState(
            interaction: interaction,
            phase: .active,
            allocations: ["food": 2, "reserve": 4, "seed": 0]
        )
        let session = makeSession(
            scene: fixture.scene,
            interaction: runtimeState,
            cameraAnchor: 0.68,
            deterministicTick: 18_423_002
        )
        let directManipulation = SceneDirectManipulationState.targetContact(
            targetID: "protected-reserve-target",
            progress: 0.88
        )
        let inventory = try makeInventory(for: fixture.scene)
        let normalRequest = try SceneFrameRequestFactory.make(
            scene: fixture.scene,
            session: session,
            viewportCropID: "baseline-393x852",
            interaction: interaction,
            directManipulation: directManipulation,
            reduceMotion: false
        )
        let reducedRequest = try SceneFrameRequestFactory.make(
            scene: fixture.scene,
            session: session,
            viewportCropID: "baseline-393x852",
            interaction: interaction,
            directManipulation: directManipulation,
            reduceMotion: true
        )
        let normal = try SceneFramePlanner.plan(
            scene: fixture.scene,
            request: normalRequest,
            assets: inventory
        )
        let reduced = try SceneFramePlanner.plan(
            scene: fixture.scene,
            request: reducedRequest,
            assets: inventory
        )

        XCTAssertEqual(
            normalRequest.visualState.activeLayerVariants,
            reducedRequest.visualState.activeLayerVariants
        )
        XCTAssertEqual(
            selectedVariants(in: reduced),
            reducedRequest.visualState.activeLayerVariants
        )
        XCTAssertEqual(
            selectedVariants(in: normal),
            normalRequest.visualState.activeLayerVariants
        )
        XCTAssertFalse(try XCTUnwrap(normal.interactionResponse).viewportTransferPath.isEmpty)
        XCTAssertNotNil(try XCTUnwrap(normal.interactionResponse).viewportMaterialPosition)
        XCTAssertEqual(try XCTUnwrap(reduced.interactionResponse).viewportTransferPath, [])
        XCTAssertNil(try XCTUnwrap(reduced.interactionResponse).viewportMaterialPosition)
        XCTAssertTrue(reduced.drawCommands.allSatisfy { $0.motion == .still })
        XCTAssertTrue(reduced.atmosphere.allSatisfy { $0.travel == .zero })
        XCTAssertFalse(reduced.camera.followsAuthoredRail)
    }

    func testSceneVisualSnapshotJSONHardKillRestoreRebuildsExactFramePlan() throws {
        let fixture = try loadHarvestFixture()
        let interaction = makeTestOnlyHarvestInteraction(fixture)
        let runtimeState = makeAllocationState(
            interaction: interaction,
            phase: .active,
            allocations: ["food": 3, "reserve": 2, "seed": 1]
        )
        let beforeKill = makeSession(
            scene: fixture.scene,
            interaction: runtimeState,
            cameraAnchor: 0.57,
            deterministicTick: 9_876_543
        )
        let encoded = try JSONEncoder().encode(beforeKill)
        let afterKill = try JSONDecoder().decode(ChapterSession.self, from: encoded)
        let inventory = try makeInventory(for: fixture.scene)

        let beforeRequest = try SceneFrameRequestFactory.make(
            scene: fixture.scene,
            session: beforeKill,
            viewportCropID: "largest-430x932",
            interaction: interaction,
            reduceMotion: false
        )
        let afterRequest = try SceneFrameRequestFactory.make(
            scene: fixture.scene,
            session: afterKill,
            viewportCropID: "largest-430x932",
            interaction: interaction,
            reduceMotion: false
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

        XCTAssertEqual(afterKill.sceneVisualSnapshot, beforeKill.sceneVisualSnapshot)
        XCTAssertEqual(afterRequest, beforeRequest)
        XCTAssertEqual(afterPlan, beforePlan)
    }

    func testRealHarvestFixturePlansBothPortraitCropsInNormalAndReducedMotion() throws {
        let fixture = try loadHarvestFixture()
        let scene = fixture.scene
        let interaction = makeTestOnlyHarvestInteraction(fixture)
        let session = makeSession(
            scene: scene,
            interaction: InteractionRuntimeState(spec: interaction),
            cameraAnchor: 0,
            deterministicTick: 18_423_003
        )
        let inventory = try makeInventory(for: scene)
        let expectedViewports: [String: SceneFrameSize] = [
            "baseline-393x852": SceneFrameSize(width: 393, height: 852),
            "largest-430x932": SceneFrameSize(width: 430, height: 932),
        ]

        XCTAssertEqual(fixture.fixtureSchemaVersion, 1)
        XCTAssertEqual(fixture.status, "NON_SHIPPING_CONTRACT_FIXTURE")
        XCTAssertEqual(
            fixture.shippingState,
            "PROHIBITED_UNTIL_REBUILT_AND_APPROVED"
        )
        XCTAssertEqual(
            Set(scene.sceneCanvas.viewportCrops.map(\.id)),
            Set(expectedViewports.keys)
        )
        XCTAssertEqual(
            Set(scene.reduceMotionComposition.viewportCrops.map(\.id)),
            Set(expectedViewports.keys)
        )

        for cropID in expectedViewports.keys.sorted() {
            for reduceMotion in [false, true] {
                let request = try SceneFrameRequestFactory.make(
                    scene: scene,
                    session: session,
                    viewportCropID: cropID,
                    interaction: interaction,
                    reduceMotion: reduceMotion
                )
                let plan = try SceneFramePlanner.plan(
                    scene: scene,
                    request: request,
                    assets: inventory
                )

                XCTAssertEqual(plan.sceneID, scene.id)
                XCTAssertEqual(plan.viewportCropID, cropID)
                XCTAssertEqual(plan.viewport, expectedViewports[cropID])
                XCTAssertEqual(plan.reduceMotion, reduceMotion)
                XCTAssertEqual(
                    selectedVariants(in: plan),
                    layerVariants(fixture.interactionContract.initialLayerVariants)
                )
                let sourceHit = try XCTUnwrap(plan.interactionSourceHitRegion)
                XCTAssertEqual(
                    sourceHit.interactionID,
                    InteractionID(fixture.nativeInteractionID)
                )
                XCTAssertEqual(sourceHit.layerID, "central-harvest")
                XCTAssertEqual(sourceHit.hitTest, .selectedVariantAlpha)
                XCTAssertEqual(
                    sourceHit.selectedVariantAlphaMask.packagePath,
                    "assets/phase1/harvest-option-1/states/central-harvest-full-alpha.png"
                )
                XCTAssertGreaterThanOrEqual(sourceHit.viewportPath.count, 3)
                XCTAssertFalse(plan.drawCommands.isEmpty)
                if reduceMotion {
                    XCTAssertEqual(
                        plan.drawCommands.first?.source,
                        .reduceMotionStaticStratum("world-underlay")
                    )
                    XCTAssertEqual(
                        plan.drawCommands.last?.source,
                        .reduceMotionStaticStratum("foreground-occlusion")
                    )
                    XCTAssertTrue(plan.drawCommands.allSatisfy { $0.motion == .still })
                }
            }
        }
    }

    func testHarvestTouchResolverRequiresAlphaThenUsesOneReducerAction() throws {
        let fixture = try loadHarvestFixture()
        let interaction = makeTestOnlyHarvestInteraction(fixture)
        let runtime = InteractionRuntimeState(spec: interaction)
        let session = makeSession(
            scene: fixture.scene,
            interaction: runtime,
            cameraAnchor: 0.32,
            deterministicTick: 18_423_011
        )
        let request = try SceneFrameRequestFactory.make(
            scene: fixture.scene,
            session: session,
            viewportCropID: "baseline-393x852",
            interaction: interaction,
            reduceMotion: false
        )
        let frame = try SceneFramePlanner.plan(
            scene: fixture.scene,
            request: request,
            assets: try makeInventory(for: fixture.scene)
        )
        let source = try XCTUnwrap(frame.interactionSourceHitRegion)
        let sourcePoint = centroid(source.viewportPath)
        let destination = try XCTUnwrap(
            frame.interactionHitRegions.first {
                $0.interactionTargetID == "winter-food-target"
            }
        )
        let destinationPoint = centroid(destination.viewportPath)

        XCTAssertThrowsError(
            try SceneTouchActionResolver.resolve(
                .allocateContact(viewportPoint: sourcePoint, progress: 0),
                scene: fixture.scene,
                interaction: interaction,
                runtimeState: runtime,
                frame: frame,
                alphaSampler: HarvestMaskSampler(opaque: false)
            )
        ) { error in
            XCTAssertEqual(error as? SceneTouchGeometryError, .sourceAlphaRejected)
        }

        let contact = try SceneTouchActionResolver.resolve(
            .allocateContact(viewportPoint: sourcePoint, progress: 0.1),
            scene: fixture.scene,
            interaction: interaction,
            runtimeState: runtime,
            frame: frame,
            alphaSampler: HarvestMaskSampler(opaque: true)
        )
        XCTAssertNil(contact.action)
        XCTAssertEqual(contact.directManipulation?.phase, .contact)

        let carry = try SceneTouchActionResolver.resolve(
            .allocateCarry(
                sourceViewportPoint: sourcePoint,
                currentViewportPoint: destinationPoint,
                progress: 0.55
            ),
            scene: fixture.scene,
            interaction: interaction,
            runtimeState: runtime,
            frame: frame,
            alphaSampler: HarvestMaskSampler(opaque: true)
        )
        XCTAssertNil(carry.action)
        XCTAssertEqual(carry.directManipulation?.phase, .carrying)
        XCTAssertEqual(
            carry.directManipulation?.masterPosition,
            try SceneTouchGeometryResolver.masterPoint(
                for: destinationPoint,
                in: frame,
                boundTo: "central-harvest"
            )
        )
        XCTAssertThrowsError(
            try SceneTouchGeometryResolver.sourceContact(
                at: destinationPoint,
                in: frame,
                alphaSampler: HarvestMaskSampler(opaque: true)
            )
        ) { error in
            XCTAssertEqual(
                error as? SceneTouchGeometryError,
                .outsideSourcePolygon
            )
        }

        XCTAssertThrowsError(
            try SceneTouchActionResolver.resolve(
                .allocateDrop(
                    sourceViewportPoint: sourcePoint,
                    destinationViewportPoint: destinationPoint,
                    destinationUnits: 0,
                    progress: 0.9
                ),
                scene: fixture.scene,
                interaction: interaction,
                runtimeState: runtime,
                frame: frame,
                alphaSampler: HarvestMaskSampler(opaque: true)
            )
        ) { error in
            XCTAssertEqual(
                error as? SceneTouchActionResolverError,
                .invalidAmount
            )
        }

        let drop = try SceneTouchActionResolver.resolve(
            .allocateDrop(
                sourceViewportPoint: sourcePoint,
                destinationViewportPoint: destinationPoint,
                destinationUnits: 2,
                progress: 0.9
            ),
            scene: fixture.scene,
            interaction: interaction,
            runtimeState: runtime,
            frame: frame,
            alphaSampler: HarvestMaskSampler(opaque: true)
        )
        XCTAssertEqual(
            drop.action,
            .allocate(destinationID: "food", units: 2)
        )
        XCTAssertEqual(drop.directManipulation?.phase, .targetContact)

        let preview = try SceneInteractionDriver.preview(
            spec: interaction,
            state: runtime,
            input: .touch(try XCTUnwrap(drop.action))
        )
        let committedResponse = try SceneTouchActionResolver.committedDirectManipulation(
            resolution: drop,
            preview: preview
        )
        XCTAssertEqual(committedResponse?.phase, .accepted)
        XCTAssertEqual(committedResponse?.targetID, "winter-food-target")
    }

    func testHarvestRejectedDropProducesResistanceWithoutAParallelReducer() throws {
        let fixture = try loadHarvestFixture()
        let interaction = makeTestOnlyHarvestInteraction(fixture)
        let runtime = makeAllocationState(
            interaction: interaction,
            phase: .active,
            allocations: ["food": 2, "reserve": 4, "seed": 3]
        )
        let session = makeSession(
            scene: fixture.scene,
            interaction: runtime,
            cameraAnchor: 0.32,
            deterministicTick: 18_423_012
        )
        let request = try SceneFrameRequestFactory.make(
            scene: fixture.scene,
            session: session,
            viewportCropID: "baseline-393x852",
            interaction: interaction,
            reduceMotion: false
        )
        let frame = try SceneFramePlanner.plan(
            scene: fixture.scene,
            request: request,
            assets: try makeInventory(for: fixture.scene)
        )
        let sourcePoint = centroid(try XCTUnwrap(frame.interactionSourceHitRegion).viewportPath)
        let destinationPoint = centroid(try XCTUnwrap(
            frame.interactionHitRegions.first {
                $0.interactionTargetID == "winter-food-target"
            }
        ).viewportPath)
        let drop = try SceneTouchActionResolver.resolve(
            .allocateDrop(
                sourceViewportPoint: sourcePoint,
                destinationViewportPoint: destinationPoint,
                destinationUnits: 7,
                progress: 1
            ),
            scene: fixture.scene,
            interaction: interaction,
            runtimeState: runtime,
            frame: frame,
            alphaSampler: HarvestMaskSampler(opaque: true)
        )
        let preview = try SceneInteractionDriver.preview(
            spec: interaction,
            state: runtime,
            input: .touch(try XCTUnwrap(drop.action))
        )
        XCTAssertEqual(preview.feedback, .resistance)
        XCTAssertEqual(preview.candidateState, runtime)
        XCTAssertEqual(
            try SceneTouchActionResolver.committedDirectManipulation(
                resolution: drop,
                preview: preview
            )?.phase,
            .resistance
        )
    }

    private func centroid(_ points: [SceneFramePoint]) -> SceneFramePoint {
        SceneFramePoint(
            x: points.reduce(0) { $0 + $1.x } / Double(points.count),
            y: points.reduce(0) { $0 + $1.y } / Double(points.count)
        )
    }

    private func loadHarvestFixture() throws -> HarvestContractFixture {
        let fixtureURL = Bundle(for: Self.self).url(
            forResource: "harvest-option-1.scene",
            withExtension: "json"
        ) ?? URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "phase1/fixtures/harvest-option-1.scene.json")
            .standardizedFileURL
        return try JSONDecoder().decode(
            HarvestContractFixture.self,
            from: Data(contentsOf: fixtureURL)
        )
    }

    private func makeTestOnlyHarvestInteraction(
        _ fixture: HarvestContractFixture
    ) -> InteractionSpec {
        InteractionSpec(
            id: InteractionID(fixture.nativeInteractionID),
            prompt: LocalizedStringSpec(
                id: "interaction-harvest-store-prompt",
                launchEnglish: "Divide the illustrative harvest."
            ),
            grammar: .allocate(
                AllocateInteractionSpec(
                    resourceName: LocalizedStringSpec(
                        id: "interaction-harvest-store-resource-name",
                        launchEnglish: "illustrative harvest shares"
                    ),
                    totalUnits: fixture.interactionContract.totalUnits,
                    destinations: HarvestTestOnlyMinimums.allocations.map {
                        AllocationDestination(
                            id: $0.destinationID,
                            minimumUnits: $0.units
                        )
                    }
                )
            ),
            completionEffects: [
                WorldEffect(
                    id: "test-only-harvest-allocation-complete",
                    mutation: .setNodeAttribute(
                        nodeID: "test-only-harvest-node",
                        value: NamedValue(
                            key: "test-only-complete",
                            value: .boolean(true)
                        )
                    )
                ),
            ],
            accessibilityID: "test-only-harvest-allocation"
        )
    }

    private func makeAllocationState(
        interaction: InteractionSpec,
        phase: InteractionPhase,
        allocations: [String: Int]
    ) -> InteractionRuntimeState {
        var state = InteractionRuntimeState(spec: interaction)
        state.phase = phase
        state.progress = .allocate(
            AllocateProgress(
                allocations: allocations.map {
                    AllocationValue(destinationID: $0.key, units: $0.value)
                }
            )
        )
        return state
    }

    private func makeSession(
        scene: SceneSpec,
        interaction: InteractionRuntimeState,
        cameraAnchor: Double,
        deterministicTick: UInt64
    ) -> ChapterSession {
        ChapterSession(
            chapterID: "first-farmers",
            packageID: "test-only-harvest-package",
            contentVersion: SchemaVersion(major: 1),
            arcID: "first-farmers-arc-02",
            beatID: "the-harvest-had-to-last",
            sceneVisualSnapshot: SceneVisualSnapshot(
                sceneID: scene.id,
                deterministicTick: deterministicTick
            ),
            interaction: interaction,
            cameraAnchor: cameraAnchor
        )
    }

    private func makeInventory(for scene: SceneSpec) throws -> SceneAssetInventory {
        let root = FileManager.default.temporaryDirectory.appending(
            path: "harvest-scene-runtime-tests-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: root)
        }

        let packagePaths = referencedAssetPaths(in: scene).sorted()
        var records: [PackageFileRecord] = []
        for packagePath in packagePaths {
            let fileURL = root.appending(path: packagePath, directoryHint: .notDirectory)
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try Data([0x01]).write(to: fileURL, options: .atomic)
            let values = try fileURL.resourceValues(forKeys: [.isRegularFileKey])
            XCTAssertEqual(values.isRegularFile, true, packagePath)
            let data = try Data(contentsOf: fileURL)
            records.append(
                PackageFileRecord(
                    path: packagePath,
                    bytes: Int64(data.count),
                    sha256: SHA256.hash(data: data)
                        .map { String(format: "%02x", $0) }
                        .joined()
                )
            )
        }
        XCTAssertEqual(records.count, referencedAssetPaths(in: scene).count)
        let version = SchemaVersion(major: 1)
        let packageID: PackageID = "test-only-harvest-package"
        let manifest = SignedPackageManifest(
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
        )
        let payload = ContentPackagePayload(
            schemaVersion: version,
            packageID: packageID,
            worldSeed: WorldSeedSpec(nodes: [], traces: []),
            chapters: [],
            scenes: [scene],
            audioTimelines: [],
            accessibility: []
        )
        return try SceneAssetInventory(
            verifiedPackage: VerifiedContentPackage(manifest: manifest, payload: payload),
            activatedPackageRoot: root
        )
    }

    private func layerMotion(
        _ layerID: SceneLayerID,
        in plan: SceneFramePlan
    ) -> SceneLayerMotionState? {
        plan.drawCommands.first(where: { command in
            if case let .layer(id, _) = command.source { return id == layerID }
            return false
        })?.motion
    }

    private func project(
        _ point: NormalizedPoint,
        through sourceRect: SceneFrameRect,
        motion: SceneLayerMotionState
    ) -> SceneFramePoint {
        SceneFramePoint(
            x: (point.x - sourceRect.x) / sourceRect.width
                + motion.parallaxOffset.dx + motion.windOffset.dx,
            y: (point.y - sourceRect.y) / sourceRect.height
                + motion.parallaxOffset.dy + motion.windOffset.dy
        )
    }

    private func point(_ point: SceneFramePoint, inside polygon: [SceneFramePoint]) -> Bool {
        guard polygon.count >= 3 else { return false }
        var inside = false
        var previous = polygon[polygon.count - 1]
        for current in polygon {
            let intersects = (current.y > point.y) != (previous.y > point.y)
                && point.x < (previous.x - current.x) * (point.y - current.y)
                    / (previous.y - current.y) + current.x
            if intersects { inside.toggle() }
            previous = current
        }
        return inside
    }

    private func referencedAssetPaths(in scene: SceneSpec) -> Set<String> {
        var paths: Set<String> = Set(
            scene.reduceMotionComposition.strata.compactMap(\.assetPath)
        )
        for layer in scene.layers {
            paths.insert(layer.assetPath)
            insert(layer.masks, into: &paths)
            for variant in layer.stateVariants {
                paths.insert(variant.assetPath)
                insert(variant.masks, into: &paths)
            }
        }
        return paths
    }

    private func insert(_ masks: SceneLayerMaskSet, into paths: inout Set<String>) {
        for path in [
            masks.alphaMaskAssetPath,
            masks.occlusionMaskAssetPath,
            masks.depthMaskAssetPath,
            masks.lightMaskAssetPath,
        ].compactMap({ $0 }) {
            paths.insert(path)
        }
    }

    private func layerVariants(_ values: [String: String]) -> [SceneLayerID: String] {
        Dictionary(uniqueKeysWithValues: values.map { (SceneLayerID($0.key), $0.value) })
    }

    private func assertEverySelectedVariantIsAuthored(
        _ visualState: SceneInteractionVisualState,
        in scene: SceneSpec,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let statefulLayers = scene.layers.filter { !$0.stateVariants.isEmpty }
        XCTAssertEqual(
            Set(visualState.activeLayerVariants.keys),
            Set(statefulLayers.map(\.id)),
            file: file,
            line: line
        )
        for (layerID, variantID) in visualState.activeLayerVariants {
            let layer = statefulLayers.first { $0.id == layerID }
            XCTAssertTrue(
                layer?.stateVariants.contains { $0.id == variantID } == true,
                "Un-authored variant '\(variantID)' selected for '\(layerID)'",
                file: file,
                line: line
            )
        }
    }

    private func selectedVariants(in plan: SceneFramePlan) -> [SceneLayerID: String] {
        var result: [SceneLayerID: String] = [:]
        for command in plan.drawCommands {
            guard case let .layer(layerID, variantID?) = command.source else { continue }
            result[layerID] = variantID
        }
        return result
    }
}

private struct HarvestMaskSampler: SceneAlphaMaskSampling {
    let opaque: Bool

    func isOpaque(
        in alphaMask: SceneResolvedAsset,
        at unitPoint: NormalizedPoint
    ) throws -> Bool {
        _ = alphaMask
        return opaque && unitPoint.isUnitPoint
    }
}

private struct HarvestContractFixture: Decodable {
    let fixtureSchemaVersion: Int
    let status: String
    let shippingState: String
    let nativeInteractionID: String
    let interactionContract: HarvestInteractionContract
    let scene: SceneSpec
}

private struct HarvestInteractionContract: Decodable {
    let totalUnits: Int
    let interactionSpecApproval: String
    let initialLayerVariants: [String: String]
    let completionLayerVariants: [String: String]
}

private struct DirectManipulationExpectation {
    let state: SceneDirectManipulationState
    let targetID: String?
    let contactAmount: Double
    let resistanceAmount: Double
    let expectsTransferPath: Bool
}

private enum HarvestTestOnlyCompletion {
    struct Allocation {
        let destinationID: String
        let units: Int
    }

    // TEST_ONLY: 5/4/3 exists solely to reach the completed runtime state.
    // It does not approve or propose the final native harvest distribution.
    static let allocations = [
        Allocation(destinationID: "food", units: 5),
        Allocation(destinationID: "reserve", units: 4),
        Allocation(destinationID: "seed", units: 3),
    ]
}

private enum HarvestTestOnlyMinimums {
    struct Allocation {
        let destinationID: String
        let units: Int
    }

    // Mirrors the non-shipping Phase 1 editor-review recommendation. Three
    // shares remain deliberately free after these obligations are met.
    static let allocations = [
        Allocation(destinationID: "food", units: 4),
        Allocation(destinationID: "reserve", units: 2),
        Allocation(destinationID: "seed", units: 3),
    ]
}
