import ContentKit
import JourneyDomain
@testable import SceneRuntime
import XCTest

final class SceneAssemblyGripOffsetTests: XCTestCase {
    func testIrregularSourceKeepsExactPickupPointWithoutRecentering() throws {
        let fixture = try RuntimeTestFixture.assembleDirectManipulation()
        defer { try? FileManager.default.removeItem(at: fixture.packageRoot) }
        let scene = sceneWithIrregularFoundationSource(fixture.repository.sceneValue)
        try scene.validate()
        try scene.validateInteractionVisualBinding(to: fixture.interaction)

        let restingFrame = try frame(
            scene: scene,
            fixture: fixture,
            directManipulation: nil
        )
        let sourceRegion = try XCTUnwrap(
            restingFrame.interactionHitRegions.first {
                $0.interactionTargetID == "runtime-foundation-target"
            }
        )
        let center = centroid(sourceRegion.viewportPath)
        let firstPickup = point(between: center, and: sourceRegion.viewportPath[0], amount: 0.32)
        let secondPickup = point(between: center, and: sourceRegion.viewportPath[2], amount: 0.32)
        let viewportDelta = SceneFrameVector(dx: 0.11, dy: 0.045)

        let firstContact = try resolve(
            .assembleContact(viewportPoint: firstPickup, progress: 0),
            scene: scene,
            fixture: fixture,
            frame: restingFrame
        )
        let secondContact = try resolve(
            .assembleContact(viewportPoint: secondPickup, progress: 0),
            scene: scene,
            fixture: fixture,
            frame: restingFrame
        )
        let firstOffset = try XCTUnwrap(firstContact.directManipulation?.grabOffset)
        let secondOffset = try XCTUnwrap(secondContact.directManipulation?.grabOffset)
        XCTAssertNotEqual(firstOffset, secondOffset)

        assertMaterialOffset(
            .zero,
            in: try frame(
                scene: scene,
                fixture: fixture,
                directManipulation: firstContact.directManipulation
            )
        )
        assertMaterialOffset(
            .zero,
            in: try frame(
                scene: scene,
                fixture: fixture,
                directManipulation: secondContact.directManipulation
            )
        )

        let firstCarry = try resolve(
            .assembleCarry(
                sourceViewportPoint: firstPickup,
                currentViewportPoint: translated(firstPickup, by: viewportDelta),
                progress: 0.55
            ),
            scene: scene,
            fixture: fixture,
            frame: restingFrame
        )
        let secondCarry = try resolve(
            .assembleCarry(
                sourceViewportPoint: secondPickup,
                currentViewportPoint: translated(secondPickup, by: viewportDelta),
                progress: 0.55
            ),
            scene: scene,
            fixture: fixture,
            frame: restingFrame
        )
        XCTAssertEqual(firstCarry.directManipulation?.grabOffset, firstOffset)
        XCTAssertEqual(secondCarry.directManipulation?.grabOffset, secondOffset)

        let firstCarryOffset = try materialOffset(
            in: frame(
                scene: scene,
                fixture: fixture,
                directManipulation: firstCarry.directManipulation
            )
        )
        let secondCarryOffset = try materialOffset(
            in: frame(
                scene: scene,
                fixture: fixture,
                directManipulation: secondCarry.directManipulation
            )
        )
        XCTAssertEqual(firstCarryOffset.dx, secondCarryOffset.dx, accuracy: 0.000_000_001)
        XCTAssertEqual(firstCarryOffset.dy, secondCarryOffset.dy, accuracy: 0.000_000_001)
        XCTAssertNotEqual(firstCarryOffset, .zero)

        let cancelled = try resolve(
            .assembleCancel(
                sourceViewportPoint: secondPickup,
                currentViewportPoint: translated(secondPickup, by: viewportDelta),
                progress: 0.55
            ),
            scene: scene,
            fixture: fixture,
            frame: restingFrame
        )
        XCTAssertEqual(cancelled.directManipulation?.grabOffset, secondOffset)
        XCTAssertEqual(cancelled.directManipulation?.phase, .snapBack)
    }

    private func resolve(
        _ intent: SceneTouchIntent,
        scene: SceneSpec,
        fixture: RuntimeTestFixture,
        frame: SceneFramePlan
    ) throws -> SceneTouchActionResolution {
        let runtime = try XCTUnwrap(fixture.state.activeChapter?.interaction)
        return try SceneTouchActionResolver.resolve(
            intent,
            scene: scene,
            interaction: fixture.interaction,
            runtimeState: runtime,
            frame: frame
        )
    }

    private func frame(
        scene: SceneSpec,
        fixture: RuntimeTestFixture,
        directManipulation: SceneDirectManipulationState?
    ) throws -> SceneFramePlan {
        let session = try XCTUnwrap(fixture.state.activeChapter)
        let request = try SceneFrameRequestFactory.make(
            scene: scene,
            session: session,
            viewportCropID: "baseline-393x852",
            interaction: fixture.interaction,
            directManipulation: directManipulation,
            reduceMotion: false
        )
        return try SceneFramePlanner.plan(
            scene: scene,
            request: request,
            assets: fixture.inventory
        )
    }

    private func sceneWithIrregularFoundationSource(_ scene: SceneSpec) -> SceneSpec {
        let targets = scene.interactionTargets.map { target in
            guard target.interactionTargetID == "runtime-foundation-target" else {
                return target
            }
            return SceneInteractionTargetBinding(
                interactionTargetID: target.interactionTargetID,
                layerID: target.layerID,
                hitRegion: SceneHitRegion(
                    path: [
                        NormalizedPoint(x: 0.215, y: 0.365),
                        NormalizedPoint(x: 0.245, y: 0.335),
                        NormalizedPoint(x: 0.335, y: 0.35),
                        NormalizedPoint(x: 0.345, y: 0.425),
                        NormalizedPoint(x: 0.29, y: 0.465),
                        NormalizedPoint(x: 0.225, y: 0.435),
                    ]
                ),
                accessibilityElementID: target.accessibilityElementID
            )
        }
        return SceneSpec(
            id: scene.id,
            sceneCanvas: scene.sceneCanvas,
            layers: scene.layers,
            cameraRail: scene.cameraRail,
            atmosphere: scene.atmosphere,
            interactionTargets: targets,
            interactionVisualBinding: scene.interactionVisualBinding,
            reduceMotionComposition: scene.reduceMotionComposition,
            mechanismFocus: scene.mechanismFocus,
            accessibilityID: scene.accessibilityID
        )
    }

    private func materialOffset(in frame: SceneFramePlan) throws -> SceneFrameVector {
        let response = try XCTUnwrap(frame.interactionResponse)
        let anchor = try XCTUnwrap(response.viewportTransferLayerAnchor)
        let material = try XCTUnwrap(response.viewportMaterialPosition)
        return SceneFrameVector(dx: material.x - anchor.x, dy: material.y - anchor.y)
    }

    private func assertMaterialOffset(
        _ expected: SceneFrameVector,
        in frame: SceneFramePlan,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        do {
            let actual = try materialOffset(in: frame)
            XCTAssertEqual(actual.dx, expected.dx, accuracy: 0.000_000_001, file: file, line: line)
            XCTAssertEqual(actual.dy, expected.dy, accuracy: 0.000_000_001, file: file, line: line)
        } catch {
            XCTFail("Missing Assemble material offset: \(error)", file: file, line: line)
        }
    }

    private func centroid(_ points: [SceneFramePoint]) -> SceneFramePoint {
        SceneFramePoint(
            x: points.reduce(0) { $0 + $1.x } / Double(points.count),
            y: points.reduce(0) { $0 + $1.y } / Double(points.count)
        )
    }

    private func point(
        between start: SceneFramePoint,
        and end: SceneFramePoint,
        amount: Double
    ) -> SceneFramePoint {
        SceneFramePoint(
            x: start.x + (end.x - start.x) * amount,
            y: start.y + (end.y - start.y) * amount
        )
    }

    private func translated(
        _ point: SceneFramePoint,
        by vector: SceneFrameVector
    ) -> SceneFramePoint {
        SceneFramePoint(x: point.x + vector.dx, y: point.y + vector.dy)
    }
}
