@testable import ContentKit
import Foundation
import XCTest

final class TraceStageSchemaTests: XCTestCase {
    func testLegacyTraceWireDecodesWithoutNamedOrLatchedStages() throws {
        let interactionWire = Data(
            #"{"anchors":[{"x":0.2,"y":0.5},{"x":0.8,"y":0.5}],"tolerance":0.05}"#.utf8
        )
        let decodedInteraction = try JSONDecoder().decode(
            TraceInteractionSpec.self,
            from: interactionWire
        )
        XCTAssertNil(decodedInteraction.anchorIDs)
        XCTAssertFalse(
            try XCTUnwrap(
                String(
                    data: JSONEncoder().encode(decodedInteraction),
                    encoding: .utf8
                )
            ).contains("anchorIDs")
        )

        let visualWire = Data(
            #"{"interactionID":"trace-route","interactionTargetID":"route-control","layerID":"route","idleVariantID":"idle","tracingVariantID":"tracing","completedVariantID":"completed"}"#.utf8
        )
        let decodedVisual = try JSONDecoder().decode(
            SceneTraceVisualBinding.self,
            from: visualWire
        )
        XCTAssertNil(decodedVisual.reachedAnchorVariants)
        XCTAssertFalse(
            try XCTUnwrap(
                String(
                    data: JSONEncoder().encode(decodedVisual),
                    encoding: .utf8
                )
            ).contains("reachedAnchorVariants")
        )
    }

    func testNamedTraceRequiresParallelUniqueStableAnchorIDs() throws {
        XCTAssertNoThrow(try makeInteraction().validate())

        for malformedIDs in [
            ["river-bank", "ford"],
            ["river-bank", "river-bank", "far-bank"],
            ["river-bank", "Not Stable", "far-bank"],
        ] {
            XCTAssertThrowsError(
                try makeInteraction(anchorIDs: malformedIDs).validate()
            ) { error in
                XCTAssertTrue(
                    String(describing: error).contains("interaction.trace.anchorIDs")
                )
            }
        }
    }

    func testReachedAnchorBindingsRequireExactNonterminalIdentityAndOrder() throws {
        let interaction = makeInteraction()
        let valid = makeScene(
            reachedAnchors: [
                .init(anchorID: "river-bank", variantID: "bank-reached"),
                .init(anchorID: "ford", variantID: "ford-reached"),
            ]
        )
        XCTAssertNoThrow(try valid.validate())
        XCTAssertNoThrow(
            try valid.validateInteractionVisualBinding(to: interaction)
        )

        let malformedBindings: [[SceneTraceReachedAnchorVisualBinding]?] = [
            [
                .init(anchorID: "ford", variantID: "ford-reached"),
                .init(anchorID: "river-bank", variantID: "bank-reached"),
            ],
            [
                .init(anchorID: "river-bank", variantID: "bank-reached"),
            ],
            nil,
        ]
        for reachedAnchors in malformedBindings {
            let scene = makeScene(reachedAnchors: reachedAnchors)
            XCTAssertThrowsError(
                try scene.validateInteractionVisualBinding(to: interaction)
            ) { error in
                XCTAssertTrue(
                    String(describing: error).contains("reachedAnchorVariants")
                )
            }
        }

        let unknownVariant = makeScene(
            reachedAnchors: [
                .init(anchorID: "river-bank", variantID: "missing-variant"),
                .init(anchorID: "ford", variantID: "ford-reached"),
            ]
        )
        XCTAssertThrowsError(try unknownVariant.validate()) { error in
            XCTAssertTrue(
                String(describing: error).contains("reached-anchor variants")
            )
        }
    }

    func testMasterSpacePolygonContainmentIncludesInteriorAndEdgeButRejectsOutside() {
        let region = SceneHitRegion(
            path: [
                NormalizedPoint(x: 0.2, y: 0.2),
                NormalizedPoint(x: 0.8, y: 0.2),
                NormalizedPoint(x: 0.8, y: 0.8),
                NormalizedPoint(x: 0.2, y: 0.8),
            ]
        )

        XCTAssertTrue(
            SceneHitRegionGeometry.contains(
                NormalizedPoint(x: 0.5, y: 0.5),
                in: region
            )
        )
        XCTAssertTrue(
            SceneHitRegionGeometry.contains(
                NormalizedPoint(x: 0.2, y: 0.5),
                in: region
            )
        )
        XCTAssertFalse(
            SceneHitRegionGeometry.contains(
                NormalizedPoint(x: 0.1, y: 0.5),
                in: region
            )
        )
    }

    func testNamedTraceRejectsAnAnchorOutsideItsBoundMasterSpaceTarget() throws {
        let interaction = makeInteraction()
        let scene = makeScene(
            reachedAnchors: [
                .init(anchorID: "river-bank", variantID: "bank-reached"),
                .init(anchorID: "ford", variantID: "ford-reached"),
            ],
            targetPath: [
                NormalizedPoint(x: 0.18, y: 0.44),
                NormalizedPoint(x: 0.65, y: 0.44),
                NormalizedPoint(x: 0.65, y: 0.56),
                NormalizedPoint(x: 0.18, y: 0.56),
            ]
        )

        XCTAssertThrowsError(
            try scene.validateInteractionVisualBinding(to: interaction)
        ) { error in
            XCTAssertTrue(
                String(describing: error).contains(
                    "must contain every named Trace anchor"
                )
            )
        }
    }

    func testLegacyUnnamedTraceKeepsItsOriginalCrossBindingCompatibility() throws {
        let interaction = makeInteraction(anchorIDs: nil)
        let scene = makeScene(
            reachedAnchors: nil,
            targetPath: [
                NormalizedPoint(x: 0.42, y: 0.44),
                NormalizedPoint(x: 0.58, y: 0.44),
                NormalizedPoint(x: 0.58, y: 0.56),
                NormalizedPoint(x: 0.42, y: 0.56),
            ]
        )

        XCTAssertNoThrow(try interaction.validate())
        XCTAssertNoThrow(
            try scene.validateInteractionVisualBinding(to: interaction)
        )
    }

    private func makeInteraction(
        anchorIDs: [String]? = ["river-bank", "ford", "far-bank"]
    ) -> InteractionSpec {
        InteractionSpec(
            id: "trace-route",
            prompt: "Carry the route across the river.",
            grammar: .trace(
                TraceInteractionSpec(
                    anchors: [
                        NormalizedPoint(x: 0.2, y: 0.5),
                        NormalizedPoint(x: 0.5, y: 0.5),
                        NormalizedPoint(x: 0.8, y: 0.5),
                    ],
                    anchorIDs: anchorIDs,
                    tolerance: 0.05
                )
            ),
            completionEffects: [
                WorldEffect(
                    id: "effect-trace-route",
                    mutation: .revealNode(
                        WorldNodeBlueprint(
                            id: "node-trace-route",
                            kind: .landscape,
                            form: "The crossing remains open",
                            position: NormalizedPoint(x: 0.5, y: 0.5)
                        )
                    )
                ),
            ],
            accessibilityID: "trace-route-accessibility"
        )
    }

    private func makeScene(
        reachedAnchors: [SceneTraceReachedAnchorVisualBinding]?,
        targetPath: [NormalizedPoint] = [
            NormalizedPoint(x: 0.18, y: 0.44),
            NormalizedPoint(x: 0.82, y: 0.44),
            NormalizedPoint(x: 0.82, y: 0.56),
            NormalizedPoint(x: 0.18, y: 0.56),
        ]
    ) -> SceneSpec {
        let crop = SceneViewportCrop(
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
        let variantIDs = [
            "idle", "tracing", "bank-reached", "ford-reached", "completed",
        ]
        let layer = SceneLayerSpec(
            id: "route",
            order: 0,
            assetPath: "assets/lab/route/base.png",
            frame: NormalizedRect(x: 0, y: 0, width: 1, height: 1),
            depth: 0.6,
            motion: SceneLayerMotion(parallaxFactor: 0.2),
            stateVariants: variantIDs.map {
                SceneLayerStateVariant(
                    id: $0,
                    assetPath: "assets/lab/route/\($0).png"
                )
            }
        )
        return SceneSpec(
            id: "trace-stage-lab",
            sceneCanvas: SceneCanvasSpec(
                canvas: ScenePixelSize(width: 1_179, height: 2_556),
                cameraTravelBounds: NormalizedRect(
                    x: 0.2,
                    y: 0.2,
                    width: 0.6,
                    height: 0.6
                ),
                authoredOverscanFraction: 0.15,
                viewportCrops: [crop]
            ),
            layers: [layer],
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
            atmosphere: [],
            interactionTargets: [
                SceneInteractionTargetBinding(
                    interactionTargetID: "route-control",
                    layerID: "route",
                    hitRegion: SceneHitRegion(path: targetPath),
                    accessibilityElementID: "route-control-accessibility"
                ),
            ],
            interactionVisualBinding: .trace(
                SceneTraceVisualBinding(
                    interactionID: "trace-route",
                    interactionTargetID: "route-control",
                    layerID: "route",
                    idleVariantID: "idle",
                    tracingVariantID: "tracing",
                    reachedAnchorVariants: reachedAnchors,
                    completedVariantID: "completed"
                )
            ),
            reduceMotionComposition: ReduceMotionComposition(
                canvas: ScenePixelSize(width: 1_179, height: 2_556),
                viewportCrops: [crop],
                strata: [
                    ReduceMotionStratum(
                        id: "world-underlay",
                        kind: .staticPlate,
                        assetPath: "assets/lab/reduced-underlay.png"
                    ),
                    ReduceMotionStratum(
                        id: "route-state",
                        kind: .stateOverlay,
                        layerID: "route"
                    ),
                    ReduceMotionStratum(
                        id: "world-foreground",
                        kind: .staticPlate,
                        assetPath: "assets/lab/reduced-foreground.png"
                    ),
                ]
            ),
            mechanismFocus: "The crossing changes as each ground is reached.",
            accessibilityID: "trace-stage-lab-accessibility"
        )
    }
}
