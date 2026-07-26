@testable import ChapterRuntime
@testable import ContentDelivery
@testable import ContentKit
@testable import DramaticAudio
import CoreGraphics
import CryptoKit
import Foundation
import ImageIO
import JourneyContent
import JourneyDomain
import Metal
import ProgressStore
import SceneRuntime
import UniformTypeIdentifiers
import XCTest

@MainActor
final class SignedRuntimeFixtureTests: XCTestCase {
    private enum LabGrammar: String, CaseIterable {
        case allocate
        case assemble
        case transform
        case pressure
        case trace
    }

    private struct LabCase {
        let grammar: LabGrammar
        let chapterID: ChapterID
        let beatID: BeatID
        let sceneID: SceneID
        let interactionID: InteractionID
        let effectID: WorldEffectID
        let seedEffectIDs: [WorldEffectID]

        var baseAssetPath: String {
            "assets/\(sceneID.rawValue)-base.png"
        }
    }

    private static let chapterID: ChapterID = "first-farmers"
    private static let chapterIDs: [ChapterID] = [
        "first-farmers",
        "europe-holds-the-line",
        "european-world",
    ]
    private static let packageID: PackageID = "vertical-slice-development-v1"
    private static let version = SchemaVersion(major: 1)
    private static let harvestProofSceneID: SceneID =
        "lab-first-farmers-harvest-v26-parallax-proof"
    private static let harvestProofAssetSHA256 = [
        "assets/harvest-v26-parallax-diagnostic-underlay.png":
            "5459f14eac91f170ff8daa1ffdba75ba456c78a4799bf0ca0f2d4aa8db14f20a",
        "assets/harvest-v26-parallax-development-source.png":
            "e00eebcac9c20b7cd4c30193ea21bc7f032981817840cb85694298240d0618ca",
        "assets/harvest-v26-parallax-alpha-people.png":
            "eb60fffa4ad4bd8a87ebe7165117423a7d6a7baa7c57e873cd9a37671cf4bc59",
        "assets/harvest-v26-parallax-alpha-grain.png":
            "972e9e1f867c9d8e178c7ed1b38b4629b7175c609a30f1ac11d8014f68d810a6",
        "assets/harvest-v26-parallax-alpha-foreground.png":
            "8f6332a7ee341e6075c05493e37f5fae68fa5950eef55a0b3727fce659542b58",
        "assets/harvest-v26-parallax-reduce-motion-static.png":
            "64bb283bbd37e66502fef198d508af8618f6032fa6edac9558bcb34e7c6199a8",
    ]
    private static let labCases = [
        LabCase(
            grammar: .allocate,
            chapterID: "first-farmers",
            beatID: "beat-first-farmers-harvest-allocation",
            sceneID: "lab-first-farmers-harvest-allocation",
            interactionID: "interaction-first-farmers-the-harvest-had-to-last",
            effectID: "effect-first-farmers-the-harvest-had-to-last",
            seedEffectIDs: []
        ),
        LabCase(
            grammar: .assemble,
            chapterID: "first-farmers",
            beatID: "beat-first-farmers-house-assembly",
            sceneID: "lab-first-farmers-house-assembly",
            interactionID: "interaction-first-farmers-the-house-outlives",
            effectID: "effect-first-farmers-the-house-outlives",
            seedEffectIDs: ["effect-first-farmers-at-the-iron-gates"]
        ),
        LabCase(
            grammar: .transform,
            chapterID: "first-farmers",
            beatID: "beat-first-farmers-land-transformation",
            sceneID: "lab-first-farmers-land-transformation",
            interactionID: "interaction-first-farmers-more-mouths-more-land",
            effectID: "effect-first-farmers-more-mouths-more-land",
            seedEffectIDs: ["effect-first-farmers-the-house-outlives"]
        ),
        LabCase(
            grammar: .pressure,
            chapterID: "europe-holds-the-line",
            beatID: "beat-frontiers-northern-valleys-pressure",
            sceneID: "lab-frontiers-northern-valleys-pressure",
            interactionID: "interaction-europe-holds-the-line-northern-valleys-keep-crown",
            effectID: "effect-europe-holds-the-line-northern-valleys-keep-crown",
            seedEffectIDs: []
        ),
        LabCase(
            grammar: .trace,
            chapterID: "european-world",
            beatID: "beat-european-world-ocean-schedule",
            sceneID: "lab-european-world-ocean-schedule",
            interactionID: "interaction-european-world-steam-keeps-the-appointment",
            effectID: "effect-european-world-steam-keeps-the-appointment",
            seedEffectIDs: []
        ),
    ]

    func testHarvestV26PartialPassUsesSignedProductionMetalPathAndRestoresExactly()
        async throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("The current test host exposes no Metal device.")
        }
        let fixture = try loadFixture()
        let scene = try XCTUnwrap(
            fixture.verifiedPackage.payload.scenes.first {
                $0.id == Self.harvestProofSceneID
            }
        )
        XCTAssertFalse(
            fixture.verifiedPackage.payload.chapters
                .flatMap(\.arcs)
                .flatMap(\.beats)
                .contains { $0.sceneID == scene.id }
        )
        XCTAssertNil(scene.interactionVisualBinding)
        XCTAssertTrue(scene.interactionTargets.isEmpty)
        XCTAssertTrue(scene.atmosphere.isEmpty)
        XCTAssertEqual(
            scene.layers.map(\.id),
            ["diagnostic-underlay", "people", "grain", "foreground"]
        )
        XCTAssertTrue(scene.layers.allSatisfy { $0.stateVariants.isEmpty })

        let records = Dictionary(
            uniqueKeysWithValues: fixture.verifiedPackage.manifest.files.map {
                ($0.path, $0)
            }
        )
        for (path, digest) in Self.harvestProofAssetSHA256 {
            XCTAssertEqual(records[path]?.sha256, digest, path)
        }
        let inventory = try SceneAssetInventory(
            verifiedPackage: fixture.verifiedPackage,
            activatedPackageRoot: fixture.packageRoot
        )
        let visualState = try SceneInteractionVisualStateResolver.staticState(for: scene)
        func framePlan(progress: Double, reduceMotion: Bool) throws -> SceneFramePlan {
            let request = SceneFrameRequest(
                viewportCropID: "baseline-393x852",
                cameraProgress: progress,
                visualState: visualState,
                deterministicTick: 4242,
                reduceMotion: reduceMotion
            )
            return try SceneFramePlanner.plan(
                scene: scene,
                request: request,
                assets: inventory
            )
        }

        let normalPlans = try [0.0, 0.5, 1.0].map {
            try framePlan(progress: $0, reduceMotion: false)
        }
        for (index, plan) in normalPlans.enumerated() {
            XCTAssertEqual(
                plan,
                try framePlan(progress: [0.0, 0.5, 1.0][index], reduceMotion: false)
            )
            XCTAssertEqual(
                plan.drawCommands.map(\.authoredOrder),
                [0, 1, 2, 3]
            )
            XCTAssertEqual(
                plan.drawCommands.map(\.asset.packagePath),
                [
                    "assets/harvest-v26-parallax-diagnostic-underlay.png",
                    "assets/harvest-v26-parallax-development-source.png",
                    "assets/harvest-v26-parallax-development-source.png",
                    "assets/harvest-v26-parallax-development-source.png",
                ]
            )
            XCTAssertEqual(
                plan.drawCommands.map { $0.masks.alpha?.packagePath },
                [
                    nil,
                    "assets/harvest-v26-parallax-alpha-people.png",
                    "assets/harvest-v26-parallax-alpha-grain.png",
                    "assets/harvest-v26-parallax-alpha-foreground.png",
                ]
            )
            let preparation = try SceneMetalPreparationPlanner.make(from: plan)
            XCTAssertEqual(
                preparation,
                try SceneMetalPreparationPlanner.make(from: plan)
            )
            XCTAssertEqual(preparation.drawCommands.map(\.authoredOrder), [0, 1, 2, 3])
        }

        assertHarvestStressOffsets(
            normalPlans[1],
            expectedX: [0, -3, -8, -10],
            expectedY: [0, 1, 8.0 / 3.0, 10.0 / 3.0]
        )
        assertHarvestStressOffsets(
            normalPlans[2],
            expectedX: [0, 3, 8, 10],
            expectedY: [0, -1, -8.0 / 3.0, -10.0 / 3.0]
        )

        for progress in [0.0, 0.5, 1.0] {
            let session = ChapterSession(
                chapterID: Self.chapterID,
                packageID: Self.packageID,
                contentVersion: Self.version,
                sceneVisualSnapshot: SceneVisualSnapshot(
                    sceneID: scene.id,
                    deterministicTick: 4242
                ),
                cameraAnchor: progress
            )
            let state = JourneyState(
                route: .chapter(Self.chapterID),
                world: try WorldGraph(seed: fixture.repository.worldSeed),
                activeChapter: session,
                installedContent: [
                    InstalledContentVersion(
                        packageID: Self.packageID,
                        version: Self.version
                    ),
                ]
            )
            let encoded = try JSONEncoder().encode(SaveSnapshot(state: state))
            let restored = try JSONDecoder().decode(SaveSnapshot.self, from: encoded)
            let restoredSession = try XCTUnwrap(restored.state.activeChapter)
            for reduceMotion in [false, true] {
                let beforeRequest = try SceneFrameRequestFactory.make(
                    scene: scene,
                    session: session,
                    viewportCropID: "baseline-393x852",
                    reduceMotion: reduceMotion
                )
                let restoredRequest = try SceneFrameRequestFactory.make(
                    scene: scene,
                    session: restoredSession,
                    viewportCropID: "baseline-393x852",
                    reduceMotion: reduceMotion
                )
                XCTAssertEqual(beforeRequest, restoredRequest)
                XCTAssertEqual(
                    try SceneFramePlanner.plan(
                        scene: scene,
                        request: beforeRequest,
                        assets: inventory
                    ),
                    try SceneFramePlanner.plan(
                        scene: scene,
                        request: restoredRequest,
                        assets: inventory
                    )
                )
            }
        }

        let reducedPlan = try framePlan(progress: 1, reduceMotion: true)
        XCTAssertFalse(reducedPlan.camera.followsAuthoredRail)
        XCTAssertTrue(reducedPlan.atmosphere.allSatisfy { $0.travel == .zero })
        XCTAssertEqual(reducedPlan.drawCommands.count, 1)
        XCTAssertEqual(
            reducedPlan.drawCommands[0].asset.packagePath,
            "assets/harvest-v26-parallax-reduce-motion-static.png"
        )
        XCTAssertEqual(reducedPlan.drawCommands[0].motion, .still)

        let compositor = SceneMetalCompositor()
        XCTAssertEqual(compositor.configure(device: device), .readyForScene)
        let negative = try await compositor.capture(
            normalPlans[1],
            pixelWidth: 786,
            pixelHeight: 1704
        )
        XCTAssertEqual(negative.encoding, .renderComposition)
        let repeatedNegative = try await compositor.capture(
            normalPlans[1],
            pixelWidth: 786,
            pixelHeight: 1704
        )
        XCTAssertEqual(negative, repeatedNegative)
        let positive = try await compositor.capture(
            normalPlans[2],
            pixelWidth: 786,
            pixelHeight: 1704
        )
        XCTAssertEqual(positive.encoding, .renderComposition)
        let repeatedPositive = try await compositor.capture(
            normalPlans[2],
            pixelWidth: 786,
            pixelHeight: 1704
        )
        XCTAssertEqual(positive, repeatedPositive)
        XCTAssertNotEqual(negative.bgra8UnormSRGB, positive.bgra8UnormSRGB)

        let reduced = try await compositor.capture(
            reducedPlan,
            pixelWidth: 786,
            pixelHeight: 1704
        )
        XCTAssertEqual(reduced.encoding, .exactStaticPlateCopy)
        let repeatedReduced = try await compositor.capture(
            reducedPlan,
            pixelWidth: 786,
            pixelHeight: 1704
        )
        XCTAssertEqual(reduced, repeatedReduced)
        let frozenURL = fixture.packageRoot.appending(
            path: "assets/harvest-v26-parallax-reduce-motion-static.png"
        )
        let frozen = try decodeBGRA8SRGBPNG(at: frozenURL)
        XCTAssertEqual(reduced.width, frozen.width)
        XCTAssertEqual(reduced.height, frozen.height)
        XCTAssertEqual(reduced.bytesPerRow, frozen.bytesPerRow)
        XCTAssertEqual(reduced.bgra8UnormSRGB, frozen.bgra8UnormSRGB)
        let productionShaderReduced = try await compositor.capture(
            reducedPlan,
            pixelWidth: 786,
            pixelHeight: 1704,
            useExactStaticPlateCopy: false
        )
        XCTAssertEqual(productionShaderReduced.encoding, .renderComposition)
        XCTAssertEqual(productionShaderReduced.width, frozen.width)
        XCTAssertEqual(productionShaderReduced.height, frozen.height)
        XCTAssertEqual(productionShaderReduced.bytesPerRow, frozen.bytesPerRow)
        XCTAssertEqual(
            productionShaderReduced.bgra8UnormSRGB,
            frozen.bgra8UnormSRGB
        )

        let staticCommand = try XCTUnwrap(reducedPlan.drawCommands.first)
        let deviationPlans = [
            replacingSingleDrawCommand(
                in: reducedPlan,
                with: replacing(
                    staticCommand,
                    opacity: 0.999
                )
            ),
            replacingSingleDrawCommand(
                in: reducedPlan,
                with: replacing(
                    staticCommand,
                    blendMode: .screen
                )
            ),
            replacingSingleDrawCommand(
                in: reducedPlan,
                with: replacing(
                    staticCommand,
                    masks: SceneDrawMaskPlan(
                        alpha: staticCommand.asset,
                        occlusion: nil,
                        depth: nil,
                        light: nil
                    )
                )
            ),
            replacingSingleDrawCommand(
                in: reducedPlan,
                with: replacing(
                    staticCommand,
                    viewportFrame: SceneFrameRect(
                        x: 0.001,
                        y: 0,
                        width: 0.999,
                        height: 1
                    )
                )
            ),
        ]
        for (index, deviationPlan) in deviationPlans.enumerated() {
            let capture = try await compositor.capture(
                deviationPlan,
                pixelWidth: 786,
                pixelHeight: 1704
            )
            XCTAssertEqual(capture.encoding, .renderComposition, "deviation \(index)")
        }
        let scaledCapture = try await compositor.capture(
            reducedPlan,
            pixelWidth: 393,
            pixelHeight: 852
        )
        XCTAssertEqual(scaledCapture.encoding, .renderComposition)

        let comparison = try horizontalPNG([
            frozen,
            negative,
            positive,
            productionShaderReduced,
        ])
        let attachment = XCTAttachment(
            data: comparison,
            uniformTypeIdentifier: UTType.png.identifier
        )
        attachment.name = "harvest-v26-reference-negative-positive-reduce-motion"
        attachment.lifetime = .keepAlways
        add(attachment)
        print("HARVEST_RUNTIME_REFERENCE_SHA256=\(sha256(frozen.bgra8UnormSRGB))")
        print("HARVEST_RUNTIME_NEGATIVE_SHA256=\(sha256(negative.bgra8UnormSRGB))")
        print("HARVEST_RUNTIME_POSITIVE_SHA256=\(sha256(positive.bgra8UnormSRGB))")
        print("HARVEST_RUNTIME_REDUCE_MOTION_SHA256=\(sha256(productionShaderReduced.bgra8UnormSRGB))")
        print("HARVEST_RUNTIME_COMPARISON_PNG_SHA256=\(sha256(comparison))")
    }

    func testSignedFixtureUsesProductionFactoryRealMetalAndOfflineAudioPrewarm()
        async throws {
        let fixture = try loadFixture()
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("The current test host exposes no Metal device.")
        }
        let compositor = SceneMetalCompositor()
        XCTAssertEqual(compositor.configure(device: device), .readyForScene)

        for lab in Self.labCases {
            let state = try stateAtBeat(lab, fixture: fixture)
            let runtime = try await makeRuntime(
                fixture: fixture,
                state: state,
                chapterID: lab.chapterID
            )
            XCTAssertEqual(runtime.contentRevision, 1, lab.grammar.rawValue)
            XCTAssertEqual(runtime.packageID, Self.packageID, lab.grammar.rawValue)
            XCTAssertEqual(runtime.chapterID, lab.chapterID, lab.grammar.rawValue)
            XCTAssertEqual(
                runtime.controller.presentation.cursor.beat.id,
                lab.beatID,
                lab.grammar.rawValue
            )
            let frame = runtime.controller.presentation.framePlan
            XCTAssertEqual(frame.sceneID, lab.sceneID, lab.grammar.rawValue)
            XCTAssertFalse(frame.drawCommands.isEmpty, lab.grammar.rawValue)
            let metalState = await compositor.prepare(frame)
            XCTAssertEqual(
                metalState,
                .sceneReady(
                    sceneID: frame.sceneID,
                    deterministicTick: frame.deterministicTick,
                    reduceMotion: frame.reduceMotion
                ),
                lab.grammar.rawValue
            )
        }

        let resolver = try ManifestBoundAudioAssetResolver(
            verifiedPackage: fixture.verifiedPackage,
            activatedPackageRoot: fixture.packageRoot
        )
        let audioPaths = Set(
            fixture.verifiedPackage.payload.audioTimelines
                .flatMap(\.events)
                .compactMap { $0.role == .silence ? nil : $0.assetPath }
        ).sorted()
        XCTAssertEqual(audioPaths, [
            "audio/lab-european-world-ocean-schedule-soundscape.m4a",
            "audio/lab-first-farmers-harvest-allocation-soundscape.m4a",
            "audio/lab-first-farmers-house-assembly-soundscape.m4a",
            "audio/lab-first-farmers-land-transformation-soundscape.m4a",
            "audio/lab-frontiers-northern-valleys-pressure-soundscape.m4a",
        ])
        try await OfflineAudioAssetPrewarmer.prewarm(
            paths: audioPaths,
            resolver: resolver
        )
        for path in audioPaths {
            let audioURL = try resolver.url(for: path)
            XCTAssertTrue(FileManager.default.fileExists(atPath: audioURL.path), path)
            XCTAssertGreaterThan(
                try Data(contentsOf: audioURL, options: .mappedIfSafe).count,
                1_000,
                path
            )
            XCTAssertEqual(resolver.fullHashCountForTesting(path), 1, path)
        }
    }

    func testTouchAndVoiceOverReachTheSameSignedFixtureFinalHash() async throws {
        let fixture = try loadFixture()
        let initialState = try activeJourneyState(fixture)
        let touchRuntime = try await makeRuntime(
            fixture: fixture,
            state: initialState
        )
        let semanticRuntime = try await makeRuntime(
            fixture: fixture,
            state: initialState
        )
        let sampler = SceneImageAlphaMaskSampler()
        let source = try XCTUnwrap(
            touchRuntime.controller.presentation.framePlan.interactionSourceHitRegion
        )
        try sampler.prewarm(source.selectedVariantAlphaMask)

        for step in [
            AllocationStep(
                targetID: "winter-food-target",
                elementID: "allocate-winter-food",
                finalUnits: 4
            ),
            AllocationStep(
                targetID: "protected-reserve-target",
                elementID: "allocate-protected-reserve",
                finalUnits: 2
            ),
            AllocationStep(
                targetID: "spring-seed-target",
                elementID: "allocate-spring-seed",
                finalUnits: 6
            ),
        ] {
            for units in 1 ... step.finalUnits {
                let touchFrame = touchRuntime.controller.presentation.framePlan
                let touchSource = try XCTUnwrap(
                    touchFrame.interactionSourceHitRegion
                )
                let target = try XCTUnwrap(
                    touchFrame.interactionHitRegions.first {
                        $0.interactionTargetID == step.targetID
                    }
                )
                _ = try await touchRuntime.controller.submitTouch(
                    .allocateDrop(
                        sourceViewportPoint: centroid(touchSource.viewportPath),
                        destinationViewportPoint: centroid(target.viewportPath),
                        destinationUnits: units,
                        progress: 0.8
                    ),
                    alphaSampler: sampler
                )
                _ = try await semanticRuntime.controller.submitVoiceOver(
                    elementID: step.elementID,
                    authoredAction: try authoredAction(
                        in: semanticRuntime,
                        elementID: step.elementID,
                        kind: .increment
                    )
                )
            }
        }

        _ = try await touchRuntime.controller.submitTouch(.commitAllocation)
        _ = try await semanticRuntime.controller.submitVoiceOver(
            elementID: "commit-allocation",
            authoredAction: try authoredAction(
                in: semanticRuntime,
                elementID: "commit-allocation",
                kind: .activate
            )
        )

        let touchState = touchRuntime.controller.presentation.journeyState
        let semanticState = semanticRuntime.controller.presentation.journeyState
        XCTAssertEqual(touchState, semanticState)
        XCTAssertEqual(touchState.activeChapter?.interaction?.phase, .complete)
        XCTAssertTrue(
            touchState.world.appliedEffectIDs.contains(
                "effect-first-farmers-the-harvest-had-to-last"
            )
        )
        let touchHash = try stateHash(touchState)
        let semanticHash = try stateHash(semanticState)
        XCTAssertEqual(touchHash, semanticHash)
        XCTAssertEqual(touchHash.utf8.count, 64)
    }

    func testAllFiveLockedGrammarsConvergeForTouchAndVoiceOver() async throws {
        let fixture = try loadFixture()
        for lab in Self.labCases {
            let initialState = try stateAtBeat(lab, fixture: fixture)
            let touchRuntime = try await makeRuntime(
                fixture: fixture,
                state: initialState,
                chapterID: lab.chapterID
            )
            let semanticRuntime = try await makeRuntime(
                fixture: fixture,
                state: initialState,
                chapterID: lab.chapterID
            )
            try await completeWithTouch(lab, runtime: touchRuntime)
            try await completeWithVoiceOver(lab, runtime: semanticRuntime)

            let touchState = touchRuntime.controller.presentation.journeyState
            let semanticState = semanticRuntime.controller.presentation.journeyState
            XCTAssertEqual(touchState, semanticState, lab.grammar.rawValue)
            XCTAssertEqual(
                touchState.activeChapter?.interaction?.phase,
                .complete,
                lab.grammar.rawValue
            )
            XCTAssertTrue(
                touchState.world.appliedEffectIDs.contains(lab.effectID),
                lab.grammar.rawValue
            )
            let touchHash = try stateHash(touchState)
            XCTAssertEqual(
                touchHash,
                try stateHash(semanticState),
                lab.grammar.rawValue
            )
            XCTAssertEqual(touchHash.utf8.count, 64, lab.grammar.rawValue)
        }
    }

    func testColdStoreRelaunchRestoresTheExactSignedCausalPoint() async throws {
        let fixture = try loadFixture()
        let storeRoot = FileManager.default.temporaryDirectory.appending(
            path: "signed-runtime-restore-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        defer { try? FileManager.default.removeItem(at: storeRoot) }
        let initialState = JourneyState(
            world: try WorldGraph(seed: fixture.repository.worldSeed)
        )
        let store = try ProgressStore(directoryURL: storeRoot)
        let restoration = try await store.restore(initialState: initialState)
        let committer = DurableJourneyCommitter(
            restoredState: restoration.state,
            lastSequence: restoration.lastSequence,
            append: { request in try await store.append(request) },
            checkpoint: { commit in try await store.checkpoint(commit) }
        )
        _ = try await committer.commit(
            .installContent(packageID: Self.packageID, version: Self.version)
        )
        let coordinator = ChapterCoordinator(repository: fixture.repository)
        let planningState = await committer.currentCommittedState()
        for action in try coordinator.beginActions(
            chapterID: Self.chapterID,
            state: planningState
        ) {
            _ = try await committer.commit(action)
        }
        let runtime = try await VerifiedChapterSceneRuntimeFactory.make(
            snapshot: fixture.snapshot,
            chapterID: Self.chapterID,
            committer: committer,
            viewportCropID: "baseline-393x852",
            reduceMotion: false
        )
        let sampler = SceneImageAlphaMaskSampler()
        for units in 1 ... 4 {
            let frame = runtime.controller.presentation.framePlan
            let source = try XCTUnwrap(frame.interactionSourceHitRegion)
            let target = try XCTUnwrap(
                frame.interactionHitRegions.first {
                    $0.interactionTargetID == "winter-food-target"
                }
            )
            let transition = try await runtime.controller.submitTouch(
                .allocateDrop(
                    sourceViewportPoint: centroid(source.viewportPath),
                    destinationViewportPoint: centroid(target.viewportPath),
                    destinationUnits: units,
                    progress: 0.8
                ),
                alphaSampler: sampler
            )
            if let commit = transition.durableCommit,
               commit.requiresCheckpoint {
                try await committer.checkpoint(commit)
            }
        }
        let beforeKill = runtime.controller.presentation.journeyState
        let beforeSequence = await committer.currentCommittedSequence()

        let reopenedStore = try ProgressStore(directoryURL: storeRoot)
        let reopened = try await reopenedStore.restore(initialState: initialState)
        XCTAssertEqual(reopened.state, beforeKill)
        XCTAssertEqual(reopened.lastSequence, beforeSequence)
        XCTAssertEqual(try stateHash(reopened.state), try stateHash(beforeKill))

        let relaunchedCommitter = DurableJourneyCommitter(
            restoredState: reopened.state,
            lastSequence: reopened.lastSequence,
            append: { request in try await reopenedStore.append(request) },
            checkpoint: { commit in try await reopenedStore.checkpoint(commit) }
        )
        let relaunchedRuntime = try await VerifiedChapterSceneRuntimeFactory.make(
            snapshot: fixture.snapshot,
            chapterID: Self.chapterID,
            committer: relaunchedCommitter,
            viewportCropID: "baseline-393x852",
            reduceMotion: false
        )
        XCTAssertEqual(
            relaunchedRuntime.controller.presentation.journeyState,
            beforeKill
        )
        XCTAssertEqual(
            relaunchedRuntime.controller.presentation.cursor.beat.id,
            "beat-first-farmers-harvest-allocation"
        )
    }

    func testAllFiveGrammarsRestoreAtEveryQuarterProgressBoundary() async throws {
        let fixture = try loadFixture()
        for lab in Self.labCases {
            let storeRoot = FileManager.default.temporaryDirectory.appending(
                path: "signed-runtime-quarter-\(lab.grammar.rawValue)-\(UUID().uuidString)",
                directoryHint: .isDirectory
            )
            defer { try? FileManager.default.removeItem(at: storeRoot) }
            let initialState = try stateAtBeat(lab, fixture: fixture)
            let store = try ProgressStore(directoryURL: storeRoot)
            let restoration = try await store.restore(initialState: initialState)
            let committer = DurableJourneyCommitter(
                restoredState: restoration.state,
                lastSequence: restoration.lastSequence,
                append: { request in try await store.append(request) },
                checkpoint: { commit in try await store.checkpoint(commit) }
            )
            let runtime = try await VerifiedChapterSceneRuntimeFactory.make(
                snapshot: fixture.snapshot,
                chapterID: lab.chapterID,
                committer: committer,
                viewportCropID: "baseline-393x852",
                reduceMotion: false
            )

            for quarter in 0 ... 4 {
                if quarter > 0 {
                    try await applyTouchQuarter(
                        quarter,
                        lab: lab,
                        runtime: runtime,
                        committer: committer
                    )
                }
                let expected = runtime.controller.presentation.journeyState
                let expectedSequence = await committer.currentCommittedSequence()
                let reopened = try ProgressStore(directoryURL: storeRoot)
                let restored = try await reopened.restore(initialState: initialState)
                XCTAssertEqual(
                    restored.state,
                    expected,
                    "\(lab.grammar.rawValue) quarter \(quarter)"
                )
                XCTAssertEqual(
                    restored.lastSequence,
                    expectedSequence,
                    "\(lab.grammar.rawValue) quarter \(quarter)"
                )
                XCTAssertEqual(
                    try stateHash(restored.state),
                    try stateHash(expected),
                    "\(lab.grammar.rawValue) quarter \(quarter)"
                )
            }
        }
    }

    func testEveryLabSceneAssetReplacementFailsMetalAndRollsBack() async throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("The current test host exposes no Metal device.")
        }
        let fixture = try loadFixture()
        for (index, lab) in Self.labCases.enumerated() {
            let root = FileManager.default.temporaryDirectory.appending(
                path: "signed-runtime-asset-\(lab.grammar.rawValue)-\(UUID().uuidString)",
                directoryHint: .isDirectory
            )
            defer { try? FileManager.default.removeItem(at: root) }
            let activator = try PackageActivator(rootURL: root)
            _ = try await activateFixture(fixture, with: activator)
            let active = try await activateFixture(fixture, with: activator)
            let retained = try await activator.retainedPackageLocations(
                for: Self.packageID
            )
            let previous = try XCTUnwrap(retained.previousGeneration)
            let previousPackage = try XCTUnwrap(retained.previousPackage)

            let verified = try ContentPackageVerifier.admitPackageAtRuntime(
                at: active.packageURL,
                expectedPackage: fixture.expectedPackage,
                trustedPublicKeys: fixture.trustedKeys,
                supportedSchema: Self.version,
                runtimeVersion: Self.version
            )
            let repository = try ContentRepository(
                developmentVerticalSlice: verified
            )
            let snapshot = VerifiedJourneyContentSnapshot(
                revision: UInt64(index + 2),
                repository: repository,
                reconciledInstalledIndex: try await activator.installedIndex(),
                packageRootURLs: [Self.packageID: active.packageURL],
                verifiedPackagesByID: [Self.packageID: verified]
            )
            let activeFixture = FixtureAuthority(
                packageRoot: active.packageURL,
                expectedPackage: fixture.expectedPackage,
                trustedKeys: fixture.trustedKeys,
                verifiedPackage: verified,
                repository: repository,
                snapshot: snapshot
            )
            let runtime = try await makeRuntime(
                fixture: activeFixture,
                state: try stateAtBeat(lab, fixture: activeFixture),
                chapterID: lab.chapterID
            )

            try replaceOneByte(
                at: active.packageURL.appending(path: lab.baseAssetPath)
            )
            let compositor = SceneMetalCompositor()
            XCTAssertEqual(compositor.configure(device: device), .readyForScene)
            let rejectedMetalState = await compositor.prepare(
                runtime.controller.presentation.framePlan
            )
            XCTAssertEqual(
                rejectedMetalState,
                .failed(.assetVerificationFailed(lab.baseAssetPath)),
                lab.grammar.rawValue
            )
            XCTAssertThrowsError(
                try ContentPackageVerifier.verifyPackage(
                    at: active.packageURL,
                    expectedPackage: fixture.expectedPackage,
                    trustedPublicKeys: fixture.trustedKeys,
                    supportedSchema: Self.version,
                    runtimeVersion: Self.version
                ),
                lab.grammar.rawValue
            )
            _ = try ContentPackageVerifier.verifyPackage(
                at: previousPackage.packageURL,
                expectedPackage: fixture.expectedPackage,
                trustedPublicKeys: fixture.trustedKeys,
                supportedSchema: Self.version,
                runtimeVersion: Self.version
            )
            let rollback = try await activator.rollback(
                packageID: Self.packageID,
                expectedActiveGeneration: active.generation,
                expectedPreviousGeneration: previous
            )
            guard case let .rolledBack(recovered) = rollback else {
                return XCTFail(
                    "\(lab.grammar.rawValue) did not restore its verified predecessor."
                )
            }
            XCTAssertEqual(recovered.generation, previous, lab.grammar.rawValue)
        }
    }

    func testAssetReplacementIsQuarantinedOrRollsBackToVerifiedPredecessor()
        async throws {
        let fixture = try loadFixture()

        let rollbackRoot = FileManager.default.temporaryDirectory.appending(
            path: "signed-runtime-rollback-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        defer { try? FileManager.default.removeItem(at: rollbackRoot) }
        let rollbackActivator = try PackageActivator(rootURL: rollbackRoot)
        _ = try await activateFixture(fixture, with: rollbackActivator)
        let active = try await activateFixture(fixture, with: rollbackActivator)
        let retained = try await rollbackActivator.retainedPackageLocations(
            for: Self.packageID
        )
        let previous = try XCTUnwrap(retained.previousGeneration)
        let previousPackage = try XCTUnwrap(retained.previousPackage)
        XCTAssertEqual(retained.activeGeneration, active.generation)

        let activeVerified = try ContentPackageVerifier.admitPackageAtRuntime(
            at: active.packageURL,
            expectedPackage: fixture.expectedPackage,
            trustedPublicKeys: fixture.trustedKeys,
            supportedSchema: Self.version,
            runtimeVersion: Self.version
        )
        let activeRepository = try ContentRepository(
            developmentVerticalSlice: activeVerified
        )
        let activeSnapshot = VerifiedJourneyContentSnapshot(
            revision: 2,
            repository: activeRepository,
            reconciledInstalledIndex: try await rollbackActivator.installedIndex(),
            packageRootURLs: [Self.packageID: active.packageURL],
            verifiedPackagesByID: [Self.packageID: activeVerified]
        )
        let activeFixture = FixtureAuthority(
            packageRoot: active.packageURL,
            expectedPackage: fixture.expectedPackage,
            trustedKeys: fixture.trustedKeys,
            verifiedPackage: activeVerified,
            repository: activeRepository,
            snapshot: activeSnapshot
        )
        let activeRuntime = try await makeRuntime(
            fixture: activeFixture,
            state: try activeJourneyState(activeFixture)
        )

        try replaceOneByte(
            at: active.packageURL.appending(
                path: "assets/lab-first-farmers-harvest-allocation-base.png"
            )
        )
        if let device = MTLCreateSystemDefaultDevice() {
            let compositor = SceneMetalCompositor()
            XCTAssertEqual(compositor.configure(device: device), .readyForScene)
            let rejectedMetalState = await compositor.prepare(
                activeRuntime.controller.presentation.framePlan
            )
            XCTAssertEqual(
                rejectedMetalState,
                .failed(
                    .assetVerificationFailed(
                        "assets/lab-first-farmers-harvest-allocation-base.png"
                    )
                )
            )
        }
        XCTAssertThrowsError(
            try ContentPackageVerifier.verifyPackage(
                at: active.packageURL,
                expectedPackage: fixture.expectedPackage,
                trustedPublicKeys: fixture.trustedKeys,
                supportedSchema: Self.version,
                runtimeVersion: Self.version
            )
        )
        _ = try ContentPackageVerifier.verifyPackage(
            at: previousPackage.packageURL,
            expectedPackage: fixture.expectedPackage,
            trustedPublicKeys: fixture.trustedKeys,
            supportedSchema: Self.version,
            runtimeVersion: Self.version
        )
        let rollback = try await rollbackActivator.rollback(
            packageID: Self.packageID,
            expectedActiveGeneration: active.generation,
            expectedPreviousGeneration: previous
        )
        guard case let .rolledBack(recovered) = rollback else {
            return XCTFail("The exact verified predecessor was not restored.")
        }
        XCTAssertEqual(recovered.generation, previous)
        let recoveredActive = try await rollbackActivator.activePackage(
            for: Self.packageID
        )
        XCTAssertEqual(recoveredActive?.generation, previous)

        let quarantineRoot = FileManager.default.temporaryDirectory.appending(
            path: "signed-runtime-quarantine-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        defer { try? FileManager.default.removeItem(at: quarantineRoot) }
        let quarantineActivator = try PackageActivator(rootURL: quarantineRoot)
        let loneActive = try await activateFixture(fixture, with: quarantineActivator)
        try replaceOneByte(
            at: loneActive.packageURL.appending(
                path: "assets/lab-first-farmers-harvest-allocation-base.png"
            )
        )
        XCTAssertThrowsError(
            try ContentPackageVerifier.verifyPackage(
                at: loneActive.packageURL,
                expectedPackage: fixture.expectedPackage,
                trustedPublicKeys: fixture.trustedKeys,
                supportedSchema: Self.version,
                runtimeVersion: Self.version
            )
        )
        let quarantine = try await quarantineActivator.deactivate(
            packageID: Self.packageID,
            expectedActiveGeneration: loneActive.generation
        )
        XCTAssertEqual(quarantine, .deactivated(loneActive.generation))
        let quarantinedActive = try await quarantineActivator.activePackage(
            for: Self.packageID
        )
        XCTAssertNil(quarantinedActive)
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: loneActive.packageURL.appending(
                    path: "package-manifest.json"
                ).path
            ),
            "Quarantine must retain failed bytes while removing their active pointer."
        )
    }

    private struct AllocationStep {
        let targetID: String
        let elementID: String
        let finalUnits: Int
    }

    private struct TrustReceipt: Decodable {
        let packageID: PackageID
        let keyID: String
        let manifestDigest: String
        let trustedPublicKeyX963Base64: String
    }

    private struct FixtureAuthority {
        let packageRoot: URL
        let expectedPackage: ContentPackageSpec
        let trustedKeys: [String: Data]
        let verifiedPackage: VerifiedContentPackage
        let repository: ContentRepository
        let snapshot: VerifiedJourneyContentSnapshot
    }

    private enum FixtureTestError: Error {
        case malformedTrustReceipt
        case missingSeedEffect(WorldEffectID)
        case rejectedBootstrapAction
        case imageEvidenceFailure
    }

    private func loadFixture() throws -> FixtureAuthority {
        let locations = try fixtureLocations()
        let packageRoot = locations.packageRoot
        let receipt = try JSONDecoder().decode(
            TrustReceipt.self,
            from: Data(contentsOf: locations.trustReceipt)
        )
        guard receipt.packageID == Self.packageID,
              receipt.keyID == "vertical-slice-development-key-v1",
              let publicKey = Data(
                  base64Encoded: receipt.trustedPublicKeyX963Base64
              ) else {
            throw FixtureTestError.malformedTrustReceipt
        }
        let expectedPackage = ContentPackageSpec(
            id: Self.packageID,
            version: Self.version,
            chapterIDs: Self.chapterIDs,
            maximumInstalledBytes: 750_000_000,
            minimumRuntime: Self.version,
            isEssentialInstall: true
        )
        let trustedKeys = [receipt.keyID: publicKey]
        let verified = try ContentPackageVerifier.admitPackageAtRuntime(
            at: packageRoot,
            expectedPackage: expectedPackage,
            trustedPublicKeys: trustedKeys,
            supportedSchema: Self.version,
            runtimeVersion: Self.version
        )
        guard verified.manifest.manifestDigest == receipt.manifestDigest else {
            throw FixtureTestError.malformedTrustReceipt
        }
        let repository = try ContentRepository(
            developmentVerticalSlice: verified
        )
        let generation = InstalledPackageGeneration(
            generationID: "signed-runtime-fixture-generation-v1",
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
            packageRootURLs: [Self.packageID: packageRoot],
            verifiedPackagesByID: [Self.packageID: verified]
        )
        return FixtureAuthority(
            packageRoot: packageRoot,
            expectedPackage: expectedPackage,
            trustedKeys: trustedKeys,
            verifiedPackage: verified,
            repository: repository,
            snapshot: snapshot
        )
    }

    private func activeJourneyState(
        _ fixture: FixtureAuthority,
        chapterID: ChapterID = "first-farmers"
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
            chapterID: chapterID,
            state: state
        ) {
            try apply(action, reducer: reducer, to: &state)
        }
        return state
    }

    private func stateAtBeat(
        _ lab: LabCase,
        fixture: FixtureAuthority
    ) throws -> JourneyState {
        var state = try activeJourneyState(
            fixture,
            chapterID: lab.chapterID
        )
        let coordinator = ChapterCoordinator(repository: fixture.repository)
        let reducer = JourneyReducer()
        var traversedBeatCount = 0
        while try coordinator.currentCursor(state: state).beat.id != lab.beatID {
            traversedBeatCount += 1
            guard traversedBeatCount <= 5 else {
                throw FixtureTestError.rejectedBootstrapAction
            }
            let cursor = try coordinator.currentCursor(state: state)
            guard let interaction = cursor.beat.interaction else {
                throw FixtureTestError.rejectedBootstrapAction
            }
            for interactionAction in canonicalCompletionActions(for: interaction) {
                try apply(
                    .interact(spec: interaction, action: interactionAction),
                    reducer: reducer,
                    to: &state
                )
            }
            for action in try coordinator.advanceActions(state: state).actions {
                try apply(action, reducer: reducer, to: &state)
            }
        }
        let authoredEffects = fixture.verifiedPackage.payload.chapters.flatMap { chapter in
            chapter.completionEffects + chapter.arcs.flatMap { arc in
                arc.beats.flatMap { beat in
                    beat.interaction?.completionEffects ?? beat.completionEffects
                }
            }
        }
        for effectID in lab.seedEffectIDs
        where !state.world.appliedEffectIDs.contains(effectID) {
            guard let effect = authoredEffects.first(where: { $0.id == effectID }) else {
                throw FixtureTestError.missingSeedEffect(effectID)
            }
            try state.world.applyAtomically([effect])
        }
        guard lab.seedEffectIDs.allSatisfy({
            state.world.appliedEffectIDs.contains($0)
        }) else {
            throw FixtureTestError.missingSeedEffect(
                lab.seedEffectIDs.first ?? lab.effectID
            )
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
                .transform(controlID: $0.controlID, amount: 1)
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
            throw FixtureTestError.rejectedBootstrapAction
        }
    }

    private func makeRuntime(
        fixture: FixtureAuthority,
        state: JourneyState,
        chapterID: ChapterID = "first-farmers"
    ) async throws -> VerifiedChapterSceneRuntime {
        let journal = SequenceJournal()
        let committer = DurableJourneyCommitter(
            restoredState: state,
            lastSequence: 0,
            append: { request in try await journal.append(request) }
        )
        return try await VerifiedChapterSceneRuntimeFactory.make(
            snapshot: fixture.snapshot,
            chapterID: chapterID,
            committer: committer,
            viewportCropID: "baseline-393x852",
            reduceMotion: false
        )
    }

    private func completeWithTouch(
        _ lab: LabCase,
        runtime: VerifiedChapterSceneRuntime
    ) async throws {
        switch lab.grammar {
        case .allocate:
            let sampler = SceneImageAlphaMaskSampler()
            let source = try XCTUnwrap(
                runtime.controller.presentation.framePlan.interactionSourceHitRegion
            )
            try sampler.prewarm(source.selectedVariantAlphaMask)
            for step in [
                AllocationStep(
                    targetID: "winter-food-target",
                    elementID: "allocate-winter-food",
                    finalUnits: 4
                ),
                AllocationStep(
                    targetID: "protected-reserve-target",
                    elementID: "allocate-protected-reserve",
                    finalUnits: 2
                ),
                AllocationStep(
                    targetID: "spring-seed-target",
                    elementID: "allocate-spring-seed",
                    finalUnits: 6
                ),
            ] {
                for units in 1 ... step.finalUnits {
                    let frame = runtime.controller.presentation.framePlan
                    let currentSource = try XCTUnwrap(
                        frame.interactionSourceHitRegion
                    )
                    let target = try target(
                        step.targetID,
                        in: runtime
                    )
                    _ = try await runtime.controller.submitTouch(
                        .allocateDrop(
                            sourceViewportPoint: centroid(currentSource.viewportPath),
                            destinationViewportPoint: centroid(target.viewportPath),
                            destinationUnits: units,
                            progress: 0.8
                        ),
                        alphaSampler: sampler
                    )
                }
            }
            _ = try await runtime.controller.submitTouch(.commitAllocation)

        case .assemble:
            for component in ["posts", "hearth", "storage", "roof"] {
                let frame = runtime.controller.presentation.framePlan
                let source = frame.interactionHitRegions.first {
                    $0.interactionTargetID == "component-\(component)-source"
                }
                let slot = frame.interactionHitRegions.first {
                    $0.interactionTargetID == "component-\(component)-slot"
                }
                if let source, let slot {
                    _ = try await runtime.controller.submitTouch(
                        .assembleDrop(
                            sourceViewportPoint: centroid(source.viewportPath),
                            slotViewportPoint: centroid(slot.viewportPath),
                            progress: 1
                        )
                    )
                } else {
                    // The already-signed development fixture predates distinct
                    // placement slots. It remains readable, but physical
                    // Assemble must fail closed until that fixture is re-signed.
                    let legacySource = try target(
                        "component-\(component)-target",
                        in: runtime
                    )
                    do {
                        _ = try await runtime.controller.submitTouch(
                            .assembleContact(
                                viewportPoint: centroid(legacySource.viewportPath),
                                progress: 0
                            )
                        )
                        XCTFail("Legacy single-target Assemble must fail closed")
                    } catch {
                        XCTAssertEqual(
                            error as? SceneTouchActionResolverError,
                            .assemblyDirectPlacementUnavailable
                        )
                    }
                    let elementID = "assemble-\(component)"
                    _ = try await runtime.controller.submitVoiceOver(
                        elementID: elementID,
                        authoredAction: try authoredAction(
                            in: runtime,
                            elementID: elementID,
                            kind: .activate
                        )
                    )
                }
            }

        case .transform:
            for stage in [
                "new-hearths", "field-edges", "herd-lanes", "daughter-settlements",
            ] {
                let hit = try target("stage-\(stage)-target", in: runtime)
                _ = try await runtime.controller.submitTouch(
                    .adjustTarget(
                        viewportPoint: centroid(hit.viewportPath),
                        amount: 1
                    )
                )
            }

        case .pressure:
            let hit = try target("inhabited-stores-target", in: runtime)
            _ = try await runtime.controller.submitTouch(
                .adjustTarget(
                    viewportPoint: centroid(hit.viewportPath),
                    amount: 0.7
                )
            )
            _ = try await runtime.controller.submitTouch(
                .holdPressure(elapsedMillis: 1_000)
            )

        case .trace:
            for anchor in [
                NormalizedPoint(x: 0.3, y: 0.54),
                NormalizedPoint(x: 0.43, y: 0.52),
                NormalizedPoint(x: 0.57, y: 0.5),
                NormalizedPoint(x: 0.7, y: 0.48),
            ] {
                _ = try await runtime.controller.submitTouch(
                    .trace(
                        viewportPoint: viewportPoint(
                            for: anchor,
                            in: runtime.controller.presentation.framePlan
                        )
                    )
                )
            }
        }
    }

    private func completeWithVoiceOver(
        _ lab: LabCase,
        runtime: VerifiedChapterSceneRuntime
    ) async throws {
        switch lab.grammar {
        case .allocate:
            for step in [
                AllocationStep(
                    targetID: "winter-food-target",
                    elementID: "allocate-winter-food",
                    finalUnits: 4
                ),
                AllocationStep(
                    targetID: "protected-reserve-target",
                    elementID: "allocate-protected-reserve",
                    finalUnits: 2
                ),
                AllocationStep(
                    targetID: "spring-seed-target",
                    elementID: "allocate-spring-seed",
                    finalUnits: 6
                ),
            ] {
                for _ in 1 ... step.finalUnits {
                    _ = try await runtime.controller.submitVoiceOver(
                        elementID: step.elementID,
                        authoredAction: try authoredAction(
                            in: runtime,
                            elementID: step.elementID,
                            kind: .increment
                        )
                    )
                }
            }
            _ = try await runtime.controller.submitVoiceOver(
                elementID: "commit-allocation",
                authoredAction: try authoredAction(
                    in: runtime,
                    elementID: "commit-allocation",
                    kind: .activate
                )
            )

        case .assemble:
            for component in ["posts", "hearth", "storage", "roof"] {
                let elementID = "assemble-\(component)"
                _ = try await runtime.controller.submitVoiceOver(
                    elementID: elementID,
                    authoredAction: try authoredAction(
                        in: runtime,
                        elementID: elementID,
                        kind: .activate
                    )
                )
            }

        case .transform:
            for stage in [
                "new-hearths", "field-edges", "herd-lanes", "daughter-settlements",
            ] {
                let elementID = "transform-\(stage)"
                _ = try await runtime.controller.submitVoiceOver(
                    elementID: elementID,
                    authoredAction: try authoredAction(
                        in: runtime,
                        elementID: elementID,
                        kind: .increment
                    )
                )
            }

        case .pressure:
            _ = try await runtime.controller.submitVoiceOver(
                elementID: "pressure-inhabited-stores",
                authoredAction: try authoredAction(
                    in: runtime,
                    elementID: "pressure-inhabited-stores",
                    kind: .increment
                )
            )
            _ = try await runtime.controller.submitVoiceOver(
                elementID: "pressure-hold-line",
                authoredAction: try authoredAction(
                    in: runtime,
                    elementID: "pressure-hold-line",
                    kind: .activate
                )
            )

        case .trace:
            for _ in 0 ..< 4 {
                _ = try await runtime.controller.submitVoiceOver(
                    elementID: "trace-ocean-route",
                    authoredAction: try authoredAction(
                        in: runtime,
                        elementID: "trace-ocean-route",
                        kind: .increment
                    )
                )
            }
        }
    }

    private func applyTouchQuarter(
        _ quarter: Int,
        lab: LabCase,
        runtime: VerifiedChapterSceneRuntime,
        committer: DurableJourneyCommitter
    ) async throws {
        switch lab.grammar {
        case .allocate:
            let sampler = SceneImageAlphaMaskSampler()
            let frame = runtime.controller.presentation.framePlan
            let source = try XCTUnwrap(frame.interactionSourceHitRegion)
            try sampler.prewarm(source.selectedVariantAlphaMask)
            let allocations: [(targetID: String, units: Int)]
            switch quarter {
            case 1:
                allocations = [("winter-food-target", 3)]
            case 2:
                allocations = [
                    ("winter-food-target", 4),
                    ("protected-reserve-target", 2),
                ]
            case 3:
                allocations = [("spring-seed-target", 3)]
            case 4:
                allocations = [("spring-seed-target", 6)]
            default:
                throw FixtureTestError.rejectedBootstrapAction
            }
            for allocation in allocations {
                let currentFrame = runtime.controller.presentation.framePlan
                let currentSource = try XCTUnwrap(
                    currentFrame.interactionSourceHitRegion
                )
                let hit = try target(allocation.targetID, in: runtime)
                let transition = try await runtime.controller.submitTouch(
                    .allocateDrop(
                        sourceViewportPoint: centroid(currentSource.viewportPath),
                        destinationViewportPoint: centroid(hit.viewportPath),
                        destinationUnits: allocation.units,
                        progress: 0.8
                    ),
                    alphaSampler: sampler
                )
                try await checkpointIfRequired(transition, committer: committer)
            }
            if quarter == 4 {
                let transition = try await runtime.controller.submitTouch(
                    .commitAllocation
                )
                try await checkpointIfRequired(transition, committer: committer)
            }

        case .assemble:
            let component = ["posts", "hearth", "storage", "roof"][quarter - 1]
            let frame = runtime.controller.presentation.framePlan
            let source = frame.interactionHitRegions.first {
                $0.interactionTargetID == "component-\(component)-source"
            }
            let slot = frame.interactionHitRegions.first {
                $0.interactionTargetID == "component-\(component)-slot"
            }
            let transition: ChapterSceneTransition
            if let source, let slot {
                transition = try await runtime.controller.submitTouch(
                    .assembleDrop(
                        sourceViewportPoint: centroid(source.viewportPath),
                        slotViewportPoint: centroid(slot.viewportPath),
                        progress: 1
                    )
                )
            } else {
                let legacySource = try target(
                    "component-\(component)-target",
                    in: runtime
                )
                do {
                    _ = try await runtime.controller.submitTouch(
                        .assembleContact(
                            viewportPoint: centroid(legacySource.viewportPath),
                            progress: 0
                        )
                    )
                    XCTFail("Legacy single-target Assemble must fail closed")
                } catch {
                    XCTAssertEqual(
                        error as? SceneTouchActionResolverError,
                        .assemblyDirectPlacementUnavailable
                    )
                }
                let elementID = "assemble-\(component)"
                transition = try await runtime.controller.submitVoiceOver(
                    elementID: elementID,
                    authoredAction: try authoredAction(
                        in: runtime,
                        elementID: elementID,
                        kind: .activate
                    )
                )
            }
            try await checkpointIfRequired(transition, committer: committer)

        case .transform:
            let stage = [
                "new-hearths", "field-edges", "herd-lanes", "daughter-settlements",
            ][quarter - 1]
            let hit = try target("stage-\(stage)-target", in: runtime)
            let transition = try await runtime.controller.submitTouch(
                .adjustTarget(
                    viewportPoint: centroid(hit.viewportPath),
                    amount: 1
                )
            )
            try await checkpointIfRequired(transition, committer: committer)

        case .pressure:
            if quarter == 1 {
                let hit = try target("inhabited-stores-target", in: runtime)
                let adjustment = try await runtime.controller.submitTouch(
                    .adjustTarget(
                        viewportPoint: centroid(hit.viewportPath),
                        amount: 0.7
                    )
                )
                try await checkpointIfRequired(adjustment, committer: committer)
            }
            let hold = try await runtime.controller.submitTouch(
                .holdPressure(elapsedMillis: 250)
            )
            try await checkpointIfRequired(hold, committer: committer)

        case .trace:
            let anchors = [
                NormalizedPoint(x: 0.3, y: 0.54),
                NormalizedPoint(x: 0.43, y: 0.52),
                NormalizedPoint(x: 0.57, y: 0.5),
                NormalizedPoint(x: 0.7, y: 0.48),
            ]
            let transition = try await runtime.controller.submitTouch(
                .trace(
                    viewportPoint: viewportPoint(
                        for: anchors[quarter - 1],
                        in: runtime.controller.presentation.framePlan
                    )
                )
            )
            try await checkpointIfRequired(transition, committer: committer)
        }
    }

    private func checkpointIfRequired(
        _ transition: ChapterSceneTransition,
        committer: DurableJourneyCommitter
    ) async throws {
        if let commit = transition.durableCommit,
           commit.requiresCheckpoint {
            try await committer.checkpoint(commit)
        }
        if let commit = transition.responsiveAudioCommit,
           commit.requiresCheckpoint {
            try await committer.checkpoint(commit)
        }
    }

    private func target(
        _ id: String,
        in runtime: VerifiedChapterSceneRuntime
    ) throws -> SceneInteractionHitRegionPlan {
        try XCTUnwrap(
            runtime.controller.presentation.framePlan.interactionHitRegions.first {
                $0.interactionTargetID == id
            }
        )
    }

    private func viewportPoint(
        for masterPoint: NormalizedPoint,
        in frame: SceneFramePlan
    ) -> SceneFramePoint {
        SceneFramePoint(
            x: (masterPoint.x - frame.camera.sourceRect.x)
                / frame.camera.sourceRect.width,
            y: (masterPoint.y - frame.camera.sourceRect.y)
                / frame.camera.sourceRect.height
        )
    }

    private func authoredAction(
        in runtime: VerifiedChapterSceneRuntime,
        elementID: String,
        kind: ContentKit.AccessibilityActionKind
    ) throws -> AccessibilityActionSpec {
        try XCTUnwrap(
            runtime.controller.presentation.cursor.accessibility.elements
                .first { $0.id == elementID }?.actions.first { $0.kind == kind }
        )
    }

    private func centroid(_ points: [SceneFramePoint]) -> SceneFramePoint {
        SceneFramePoint(
            x: points.reduce(0) { $0 + $1.x } / Double(points.count),
            y: points.reduce(0) { $0 + $1.y } / Double(points.count)
        )
    }

    private func assertHarvestStressOffsets(
        _ plan: SceneFramePlan,
        expectedX: [Double],
        expectedY: [Double],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(plan.drawCommands.count, expectedX.count, file: file, line: line)
        XCTAssertEqual(plan.drawCommands.count, expectedY.count, file: file, line: line)
        for index in plan.drawCommands.indices {
            let motion = plan.drawCommands[index].motion.parallaxOffset
            let sourcePixelX = motion.dx * plan.camera.sourceRect.width * 1290
            let sourcePixelY = motion.dy * plan.camera.sourceRect.height * 2796
            XCTAssertEqual(
                sourcePixelX,
                expectedX[index],
                accuracy: 0.000_000_001,
                file: file,
                line: line
            )
            XCTAssertEqual(
                sourcePixelY,
                expectedY[index],
                accuracy: 0.000_000_001,
                file: file,
                line: line
            )
        }
    }

    private func replacingSingleDrawCommand(
        in plan: SceneFramePlan,
        with command: SceneDrawCommand
    ) -> SceneFramePlan {
        SceneFramePlan(
            sceneID: plan.sceneID,
            viewportCropID: plan.viewportCropID,
            viewport: plan.viewport,
            deterministicTick: plan.deterministicTick,
            reduceMotion: plan.reduceMotion,
            camera: plan.camera,
            drawCommands: [command],
            atmosphere: plan.atmosphere,
            interactionSourceHitRegion: plan.interactionSourceHitRegion,
            interactionHitRegions: plan.interactionHitRegions,
            interactionResponse: plan.interactionResponse,
            safeTextRegions: plan.safeTextRegions
        )
    }

    private func replacing(
        _ command: SceneDrawCommand,
        masks: SceneDrawMaskPlan? = nil,
        viewportFrame: SceneFrameRect? = nil,
        opacity: Double? = nil,
        blendMode: SceneBlendMode? = nil
    ) -> SceneDrawCommand {
        SceneDrawCommand(
            source: command.source,
            authoredOrder: command.authoredOrder,
            depth: command.depth,
            asset: command.asset,
            masks: masks ?? command.masks,
            masterFrame: command.masterFrame,
            viewportFrame: viewportFrame ?? command.viewportFrame,
            opacity: opacity ?? command.opacity,
            blendMode: blendMode ?? command.blendMode,
            motion: command.motion
        )
    }

    private func decodeBGRA8SRGBPNG(at url: URL) throws -> SceneMetalCapturedFrame {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
              let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else {
            throw FixtureTestError.imageEvidenceFailure
        }
        let width = image.width
        let height = image.height
        let bytesPerRow = width * 4
        var bytes = Data(count: bytesPerRow * height)
        let bitmapInfo = CGBitmapInfo.byteOrder32Little.union(
            CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue)
        )
        let didDraw: Bool = bytes.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: colorSpace,
                bitmapInfo: bitmapInfo.rawValue
            ) else {
                return false
            }
            context.setBlendMode(.copy)
            context.draw(
                image,
                in: CGRect(x: 0, y: 0, width: width, height: height)
            )
            return true
        }
        guard didDraw else { throw FixtureTestError.imageEvidenceFailure }
        return SceneMetalCapturedFrame(
            width: width,
            height: height,
            bytesPerRow: bytesPerRow,
            bgra8UnormSRGB: bytes,
            encoding: .referenceBytes
        )
    }

    private func horizontalPNG(_ frames: [SceneMetalCapturedFrame]) throws -> Data {
        guard let first = frames.first,
              frames.allSatisfy({
                  $0.width == first.width
                      && $0.height == first.height
                      && $0.bytesPerRow == first.bytesPerRow
              }) else {
            throw FixtureTestError.imageEvidenceFailure
        }
        let width = first.width * frames.count
        let bytesPerRow = width * 4
        var combined = Data(count: bytesPerRow * first.height)
        combined.withUnsafeMutableBytes { destination in
            guard let destinationBase = destination.baseAddress else { return }
            for (frameIndex, frame) in frames.enumerated() {
                frame.bgra8UnormSRGB.withUnsafeBytes { source in
                    guard let sourceBase = source.baseAddress else { return }
                    for row in 0 ..< first.height {
                        destinationBase
                            .advanced(by: row * bytesPerRow + frameIndex * first.bytesPerRow)
                            .copyMemory(
                                from: sourceBase.advanced(by: row * first.bytesPerRow),
                                byteCount: first.bytesPerRow
                            )
                    }
                }
            }
        }

        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let provider = CGDataProvider(data: combined as CFData) else {
            throw FixtureTestError.imageEvidenceFailure
        }
        let bitmapInfo = CGBitmapInfo.byteOrder32Little.union(
            CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue)
        )
        guard let image = CGImage(
            width: width,
            height: first.height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: bitmapInfo,
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        ) else {
            throw FixtureTestError.imageEvidenceFailure
        }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            throw FixtureTestError.imageEvidenceFailure
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw FixtureTestError.imageEvidenceFailure
        }
        return output as Data
    }

    private func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private func stateHash(_ state: JourneyState) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return SHA256.hash(data: try encoder.encode(state)).map {
            String(format: "%02x", $0)
        }.joined()
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
            throw FixtureTestError.malformedTrustReceipt
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

    private func activateFixture(
        _ fixture: FixtureAuthority,
        with activator: PackageActivator
    ) async throws -> ActivatedPackage {
        let staging = try await activator.makeStagingDirectory()
        try copyDirectoryContents(from: fixture.packageRoot, to: staging)
        return try await activator.activate(
            stagedPackageURL: staging,
            expectedPackage: fixture.expectedPackage,
            trustedPublicKeys: fixture.trustedKeys,
            supportedSchema: Self.version,
            runtimeVersion: Self.version
        )
    }

    private func copyDirectoryContents(from source: URL, to destination: URL) throws {
        let children = try FileManager.default.contentsOfDirectory(
            at: source,
            includingPropertiesForKeys: nil
        )
        for child in children {
            try FileManager.default.copyItem(
                at: child,
                to: destination.appending(path: child.lastPathComponent)
            )
        }
    }

    private func replaceOneByte(at url: URL) throws {
        var bytes = try Data(contentsOf: url)
        guard !bytes.isEmpty else { throw FixtureTestError.malformedTrustReceipt }
        bytes[bytes.startIndex] ^= 0xFF
        try bytes.write(to: url, options: .atomic)
    }
}

private actor SequenceJournal {
    private var sequence: UInt64 = 0

    func append(_ request: ConditionalJourneyAppendRequest) throws -> UInt64 {
        guard request.expectedPreviousSequence == sequence else {
            throw SignedRuntimeFixtureJournalError.sequenceMismatch
        }
        sequence += 1
        return sequence
    }
}

private enum SignedRuntimeFixtureJournalError: Error {
    case sequenceMismatch
}
