import Foundation
@testable import ImmersiveRuntime
import RealityKit
import XCTest

final class Chapter01RealityAssetRepositoryTests: XCTestCase {
    func testCatalogKeepsExactlyFiveContinuityProofCellsAndSixActionMechanisms() {
        XCTAssertEqual(
            Chapter01RealityAssetCatalog.descriptors.map(\.cell),
            Chapter01WorldCell.allCases
        )
        XCTAssertEqual(
            Chapter01RealityAssetCatalog.descriptors.flatMap(\.actionBindingNames).count,
            16
        )
        XCTAssertEqual(
            Chapter01RealityAssetCatalog.continuityProofClassification,
            "CONTINUITY_PROOF"
        )
        XCTAssertEqual(Chapter01RealityAssetCatalog.finalArtGate, "OPEN")
        XCTAssertEqual(
            Chapter01RealityAssetCatalog.descriptor(for: .aegeanPassage)
                .suppressedVisualBindingNames,
            Set([
                "storm-rain",
                "current-0",
                "current-1",
                "current-2",
                "current-3",
            ])
        )
        XCTAssertTrue(
            Chapter01RealityAssetCatalog.descriptors.allSatisfy {
                $0.suppressedVisualBindingNames.isSubset(
                    of: Set($0.requiredBindingNames)
                )
            }
        )
        XCTAssertEqual(
            Chapter01RealityAssetCatalog.descriptor(for: .thessalianHousehold)
                .nonVisualActionBindingNames,
            Set([
                "action-grain-source",
                "action-food",
                "action-reserve",
                "action-seed",
                "action-store-seal",
                "action-store-repair",
                "action-spring-sow",
            ])
        )
        XCTAssertTrue(
            Chapter01RealityAssetCatalog.descriptors.allSatisfy {
                $0.nonVisualActionBindingNames.isSubset(of: Set($0.actionBindingNames))
            }
        )
        XCTAssertTrue(
            Chapter01RealityAssetCatalog.descriptors.allSatisfy {
                $0.packageRelativePath.hasPrefix("immersive/first-farmers/cells/")
                    && $0.packageRelativePath.hasSuffix(".usdz")
            }
        )
    }

    @MainActor
    func testResidencyNeverKeepsMoreThanCurrentAndNext() async throws {
        let locator = TestRealityAssetLocator(
            descriptors: Chapter01RealityAssetCatalog.descriptors
        )
        var loadedNames: [String] = []
        let repository = Chapter01RealityAssetRepository(
            locator: locator,
            entityLoader: { url in
                loadedNames.append(url.lastPathComponent)
                let descriptor = try XCTUnwrap(
                    Chapter01RealityAssetCatalog.descriptors.first {
                        $0.bundledResourceName == url.lastPathComponent
                    }
                )
                return Self.makeValidEntity(for: descriptor)
            }
        )

        let first = try await repository.reconcileResidency(
            current: .aegeanPassage
        )
        XCTAssertEqual(
            repository.residentCells,
            [.aegeanPassage, .thessalianHousehold]
        )
        XCTAssertEqual(first.entities.count, 2)
        XCTAssertEqual(first.nextCell, .thessalianHousehold)
        XCTAssertEqual(loadedNames.count, 2)

        let second = try await repository.reconcileResidency(
            current: .thessalianHousehold
        )
        XCTAssertEqual(
            repository.residentCells,
            [.thessalianHousehold, .ironGates]
        )
        XCTAssertEqual(second.entities.count, 2)
        XCTAssertEqual(second.nextCell, .ironGates)
        XCTAssertEqual(loadedNames.count, 3)
        XCTAssertNil(second.entities[.aegeanPassage])

        _ = try await repository.reconcileResidency(
            current: .settlementLandscape
        )
        XCTAssertEqual(repository.residentCells, [.settlementLandscape])
        XCTAssertEqual(repository.residentCells.count, 1)
    }

    @MainActor
    func testValidationCanonicalizesUSDIdentifiersAndMakesActionsTouchable()
        async throws
    {
        let descriptor = Chapter01RealityAssetCatalog.descriptor(
            for: .settlementLandscape
        )
        let locator = TestRealityAssetLocator(descriptors: [descriptor])
        let repository = Chapter01RealityAssetRepository(
            locator: locator,
            entityLoader: { _ in
                Self.makeValidEntity(
                    for: descriptor,
                    useUSDIdentifiers: true
                )
            }
        )

        let residency = try await repository.reconcileResidency(
            current: .settlementLandscape
        )
        let cell = try XCTUnwrap(residency.entity(for: .settlementLandscape))
        let action = try XCTUnwrap(
            cell.findEntity(named: "action-herd-route")
        )
        XCTAssertTrue(action.components.has(InputTargetComponent.self))
        XCTAssertTrue(action.components.has(CollisionComponent.self))
        XCTAssertNil(cell.findEntity(named: "action_herd_route"))
        XCTAssertEqual(
            residency.validationReports.first?.validatedBindingNames,
            descriptor.requiredBindingNames
        )
    }

    @MainActor
    func testNonVisualThessalyHitProxiesRemainTouchableWithoutRendering()
        async throws
    {
        let descriptor = Chapter01RealityAssetCatalog.descriptor(
            for: .thessalianHousehold
        )
        let nextDescriptor = Chapter01RealityAssetCatalog.descriptor(
            for: .ironGates
        )
        let descriptors = [descriptor, nextDescriptor]
        let locator = TestRealityAssetLocator(descriptors: descriptors)
        let repository = Chapter01RealityAssetRepository(
            locator: locator,
            entityLoader: { url in
                let matched = try XCTUnwrap(
                    descriptors.first {
                        $0.bundledResourceName == url.lastPathComponent
                    }
                )
                return Self.makeValidEntity(for: matched)
            }
        )

        let residency = try await repository.reconcileResidency(
            current: .thessalianHousehold
        )
        let cell = try XCTUnwrap(residency.entity(for: .thessalianHousehold))

        for name in descriptor.nonVisualActionBindingNames {
            let action = try XCTUnwrap(cell.findEntity(named: name))
            XCTAssertTrue(action.components.has(InputTargetComponent.self))
            XCTAssertTrue(action.components.has(CollisionComponent.self))
            XCTAssertEqual(
                action.components[OpacityComponent.self]?.opacity,
                0
            )
        }
    }

    @MainActor
    func testUnsupportedTransparentWeatherGeometryIsSuppressedAfterImport()
        async throws
    {
        let descriptor = Chapter01RealityAssetCatalog.descriptor(
            for: .aegeanPassage
        )
        let nextDescriptor = Chapter01RealityAssetCatalog.descriptor(
            for: .thessalianHousehold
        )
        let descriptors = [descriptor, nextDescriptor]
        let repository = Chapter01RealityAssetRepository(
            locator: TestRealityAssetLocator(descriptors: descriptors),
            entityLoader: { url in
                let matched = try XCTUnwrap(
                    descriptors.first {
                        $0.bundledResourceName == url.lastPathComponent
                    }
                )
                return Self.makeValidEntity(for: matched)
            }
        )

        let residency = try await repository.reconcileResidency(
            current: .aegeanPassage
        )
        let cell = try XCTUnwrap(residency.entity(for: .aegeanPassage))
        let weather = try XCTUnwrap(cell.findEntity(named: "storm-rain"))
        XCTAssertEqual(
            weather.components[OpacityComponent.self]?.opacity,
            0
        )
    }

    @MainActor
    func testMissingRequiredBindingProducesTypedFailure() async throws {
        let descriptor = Chapter01RealityAssetCatalog.descriptor(
            for: .aegeanPassage
        )
        let locator = TestRealityAssetLocator(descriptors: [descriptor])
        let repository = Chapter01RealityAssetRepository(
            locator: locator,
            entityLoader: { _ in Entity() }
        )

        do {
            _ = try await repository.reconcileResidency(
                current: .aegeanPassage
            )
            XCTFail("Expected missing-binding validation to fail")
        } catch let failure as Chapter01RealityAssetRepositoryFailure {
            guard case let .missingBindings(cell, names) = failure else {
                return XCTFail("Unexpected failure: \(failure)")
            }
            XCTAssertEqual(cell, .aegeanPassage)
            XCTAssertEqual(names, descriptor.requiredBindingNames.sorted())
        }
    }

    @MainActor
    func testMissingResourceProducesTypedFailureBeforeDecode() async throws {
        let repository = Chapter01RealityAssetRepository(
            locator: TestRealityAssetLocator(descriptors: []),
            entityLoader: { _ in
                XCTFail("Missing resources must not reach RealityKit")
                return Entity()
            }
        )

        await XCTAssertThrowsErrorAsync(
            try await repository.reconcileResidency(current: .aegeanPassage)
        ) { error in
            XCTAssertEqual(
                error as? Chapter01RealityAssetRepositoryFailure,
                .missingResource(
                    cell: .aegeanPassage,
                    resourceName: "aegean-crossing-lod0.usdz"
                )
            )
        }
    }

    @MainActor
    func testNewerResidencyRequestCannotBeOverwrittenBySlowDecode()
        async throws
    {
        let descriptors = Chapter01RealityAssetCatalog.descriptors
        let locator = TestRealityAssetLocator(descriptors: descriptors)
        var delayedLoad: CheckedContinuation<Void, Never>?
        let repository = Chapter01RealityAssetRepository(
            locator: locator,
            entityLoader: { url in
                let descriptor = try XCTUnwrap(
                    descriptors.first {
                        $0.bundledResourceName == url.lastPathComponent
                    }
                )
                if descriptor.cell == .aegeanPassage {
                    await withCheckedContinuation { continuation in
                        delayedLoad = continuation
                    }
                }
                return Self.makeValidEntity(for: descriptor)
            }
        )

        let staleRequest = Task { @MainActor in
            try await repository.reconcileResidency(current: .aegeanPassage)
        }
        while delayedLoad == nil { await Task.yield() }

        let current = try await repository.reconcileResidency(
            current: .settlementLandscape
        )
        delayedLoad?.resume()

        do {
            _ = try await staleRequest.value
            XCTFail("The older decode should be superseded")
        } catch let failure as Chapter01RealityAssetRepositoryFailure {
            XCTAssertEqual(failure, .supersededRequest(cell: .aegeanPassage))
        }
        XCTAssertEqual(current.currentCell, .settlementLandscape)
        XCTAssertEqual(repository.residentCells, [.settlementLandscape])
    }

    #if !SWIFT_PACKAGE
    @MainActor
    func testEveryBundledContinuityProofDecodesAndPassesRuntimeBindings()
        async throws
    {
        let repository = Chapter01RealityAssetRepository()
        var reports: [Chapter01RealityAssetValidationReport] = []

        for cell in Chapter01WorldCell.allCases {
            let residency = try await repository.reconcileResidency(
                current: cell
            )
            reports.append(contentsOf: residency.validationReports)
            XCTAssertLessThanOrEqual(repository.residentCells.count, 2)
            let currentEntity = try XCTUnwrap(residency.entity(for: cell))
            let descriptor = Chapter01RealityAssetCatalog.descriptor(for: cell)
            for actionName in descriptor.actionBindingNames {
                let action = try XCTUnwrap(
                    currentEntity.findEntity(named: actionName),
                    "Missing canonical action entity \(actionName)"
                )
                XCTAssertTrue(action.components.has(InputTargetComponent.self))
                XCTAssertTrue(action.components.has(CollisionComponent.self))
            }
        }

        let reportByCell = reports.reduce(
            into: [Chapter01WorldCell: Chapter01RealityAssetValidationReport]()
        ) { result, report in
            result[report.cell] = report
        }
        XCTAssertEqual(Set(reportByCell.keys), Set(Chapter01WorldCell.allCases))
        XCTAssertTrue(
            reportByCell.values.allSatisfy {
                $0.qualityClassification == "CONTINUITY_PROOF"
                    && $0.finalArtGate == "OPEN"
            }
        )
    }
    #endif
}

@MainActor
private final class TestRealityAssetLocator: Chapter01RealityAssetLocating {
    private let urlsByCell: [Chapter01WorldCell: URL]

    init(descriptors: [Chapter01RealityAssetDescriptor]) {
        urlsByCell = Dictionary(uniqueKeysWithValues: descriptors.map {
            descriptor in
            (
                descriptor.cell,
                URL(fileURLWithPath: "/test-assets")
                    .appending(path: descriptor.bundledResourceName)
            )
        })
    }

    func url(for descriptor: Chapter01RealityAssetDescriptor) -> URL? {
        urlsByCell[descriptor.cell]
    }
}

@MainActor
private extension Chapter01RealityAssetRepositoryTests {
    static func makeValidEntity(
        for descriptor: Chapter01RealityAssetDescriptor,
        useUSDIdentifiers: Bool = false
    ) -> Entity {
        let root = Entity()
        root.name = "fixture-\(descriptor.cell.rawValue)"
        let actionNames = Set(descriptor.actionBindingNames)

        for binding in descriptor.requiredBindingNames {
            let entity: Entity
            if actionNames.contains(binding) {
                entity = ModelEntity(
                    mesh: .generateBox(size: 0.25),
                    materials: [SimpleMaterial(color: .white, isMetallic: false)]
                )
            } else {
                entity = Entity()
            }
            entity.name = useUSDIdentifiers
                ? binding.replacingOccurrences(of: "-", with: "_")
                : binding
            root.addChild(entity)
        }
        return root
    }

    func XCTAssertThrowsErrorAsync<T>(
        _ expression: @autoclosure () async throws -> T,
        _ errorHandler: (Error) -> Void,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        do {
            _ = try await expression()
            XCTFail("Expected expression to throw", file: file, line: line)
        } catch {
            errorHandler(error)
        }
    }
}
