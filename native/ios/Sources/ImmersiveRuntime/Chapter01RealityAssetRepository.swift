import Foundation
import RealityKit

/// The generated cells bundled for the current simulator review are
/// continuity proofs. They exercise the real USDZ loading, binding and
/// residency path, but their presence must not be interpreted as final-art
/// approval.
public struct Chapter01RealityAssetDescriptor: Hashable, Sendable {
    public let cell: Chapter01WorldCell
    public let bundledResourceName: String
    public let packageRelativePath: String
    public let requiredBindingNames: [String]
    public let actionBindingNames: [String]
    /// Interaction geometry authored as a semantic hit proxy rather than a
    /// visible historical object. It remains collision-bearing and focusable
    /// after import, but its USD preview mesh must never enter the frame.
    public let nonVisualActionBindingNames: Set<String>
    /// Imported geometry whose authored transparency is not preserved by the
    /// mobile USD preview path. Keeping it in the package preserves provenance
    /// and deterministic bindings; suppressing it prevents opaque proxy/VFX
    /// geometry from obscuring the historical action.
    public let suppressedVisualBindingNames: Set<String>

    public init(
        cell: Chapter01WorldCell,
        bundledResourceName: String,
        packageRelativePath: String,
        requiredBindingNames: [String],
        actionBindingNames: [String],
        nonVisualActionBindingNames: Set<String> = [],
        suppressedVisualBindingNames: Set<String> = []
    ) {
        self.cell = cell
        self.bundledResourceName = bundledResourceName
        self.packageRelativePath = packageRelativePath
        self.requiredBindingNames = requiredBindingNames
        self.actionBindingNames = actionBindingNames
        self.nonVisualActionBindingNames = nonVisualActionBindingNames
        self.suppressedVisualBindingNames = suppressedVisualBindingNames
    }
}

public enum Chapter01RealityAssetCatalog {
    public static let continuityProofClassification = "CONTINUITY_PROOF"
    public static let finalArtGate = "OPEN"

    public static let descriptors: [Chapter01RealityAssetDescriptor] = [
        .init(
            cell: .aegeanPassage,
            bundledResourceName: "aegean-crossing-lod0.usdz",
            packageRelativePath: "immersive/first-farmers/cells/cell-01.usdz",
            requiredBindingNames: [
                "western-anatolia-aegean",
                "crossing-boat",
                "action-crossing-line",
                "seed-vessel",
                "western-shore",
                "camera-entry",
                "camera-action-close",
                "camera-seed-close",
                "camera-shore-reveal",
                "transition-carrier-seed",
                "transition-western-shore",
                "storm-rain",
                "current-0",
                "current-1",
                "current-2",
                "current-3",
            ],
            actionBindingNames: ["action-crossing-line"],
            suppressedVisualBindingNames: [
                "storm-rain",
                "current-0",
                "current-1",
                "current-2",
                "current-3",
            ]
        ),
        .init(
            cell: .thessalianHousehold,
            bundledResourceName: "thessaly-household-store.usdz",
            packageRelativePath: "immersive/first-farmers/cells/cell-02.usdz",
            requiredBindingNames: [
                "thessalian-household-store",
                "action-grain-source",
                "action-food",
                "action-reserve",
                "action-seed",
                "action-store-seal",
                "action-store-repair",
                "action-spring-sow",
                "state-harvest",
                "state-winter",
                "state-spring",
                "winter-rain",
                "worked-field",
                "household-hearth-flame",
                "camera-harvest-overview",
                "camera-allocation-close",
                "camera-winter-loss",
                "camera-repair",
                "camera-spring-sowing",
                "transition-aegean-in",
                "transition-iron-gates-out",
            ],
            actionBindingNames: [
                "action-grain-source",
                "action-food",
                "action-reserve",
                "action-seed",
                "action-store-seal",
                "action-store-repair",
                "action-spring-sow",
            ],
            nonVisualActionBindingNames: [
                "action-grain-source",
                "action-food",
                "action-reserve",
                "action-seed",
                "action-store-seal",
                "action-store-repair",
                "action-spring-sow",
            ]
        ),
        .init(
            cell: .ironGates,
            bundledResourceName: "iron-gates.usdz",
            packageRelativePath: "immersive/first-farmers/cells/cell-03.usdz",
            requiredBindingNames: [
                "iron-gates-riverbank",
                "iron-gates-boat",
                "action-landing-line",
                "guide-pole",
                "iron-gates-local-guide",
                "iron-gates-line-receiver",
                "camera-iron-gates-entry",
                "camera-iron-gates-landing",
                "camera-iron-gates-handoff",
                "camera-iron-gates-reduce-motion",
                "transition-in-river-current",
                "transition-out-shared-material",
            ],
            actionBindingNames: ["action-landing-line"]
        ),
        .init(
            cell: .longhouseGround,
            bundledResourceName: "longhouse.usdz",
            packageRelativePath: "immersive/first-farmers/cells/cell-04.usdz",
            requiredBindingNames: [
                "danube-loess-longhouse",
                "longhouse-frame",
                "action-posts",
                "action-hearth",
                "action-hearth-flame",
                "action-storage",
                "action-roof",
                "longhouse-raising-line",
                "camera-longhouse-approach",
                "camera-longhouse-raise",
                "camera-longhouse-hearth",
                "camera-longhouse-repair",
                "camera-longhouse-reduce-motion",
                "transition-in-threshold",
                "transition-out-surviving-posthole",
            ],
            actionBindingNames: [
                "action-posts",
                "action-hearth",
                "action-storage",
                "action-roof",
                "longhouse-raising-line",
            ]
        ),
        .init(
            cell: .settlementLandscape,
            bundledResourceName: "settlement.usdz",
            packageRelativePath: "immersive/first-farmers/cells/cell-05.usdz",
            requiredBindingNames: [
                "expanding-settlement-landscape",
                "action-herd-route",
                "moving-herd",
                "daughter-settlement",
                "daughter-field",
                "action-final-gate",
                "valley-water",
                "farming-trace-0",
                "farming-trace-9",
                "camera-expansion-herd",
                "camera-expansion-field-edge",
                "camera-expansion-daughter",
                "camera-expansion-final",
                "camera-expansion-reduce-motion",
                "transition-in-surviving-posthole",
                "transition-out-eastern-horizon",
            ],
            actionBindingNames: [
                "action-herd-route",
                "action-final-gate",
            ]
        ),
    ]

    public static func descriptor(
        for cell: Chapter01WorldCell
    ) -> Chapter01RealityAssetDescriptor {
        // This is a closed five-cell catalogue. A missing case is a programmer
        // error caught by the catalogue tests, never package data.
        descriptors.first(where: { $0.cell == cell })!
    }
}

@MainActor
public protocol Chapter01RealityAssetLocating: AnyObject {
    func url(for descriptor: Chapter01RealityAssetDescriptor) -> URL?
}

/// Finds review resources in the ImmersiveRuntime framework first, then in
/// the app bundle. The second location also supports a later static-link build.
@MainActor
public final class Chapter01BundledRealityAssetLocator:
    Chapter01RealityAssetLocating
{
    private final class BundleToken: NSObject {}

    private let bundles: [Bundle]

    public init(bundles: [Bundle]? = nil) {
        if let bundles {
            self.bundles = bundles
            return
        }
        let candidates = [Bundle(for: BundleToken.self), .main]
            + Bundle.allFrameworks
        var seen = Set<URL>()
        self.bundles = candidates.filter { seen.insert($0.bundleURL).inserted }
    }

    public func url(for descriptor: Chapter01RealityAssetDescriptor) -> URL? {
        let resourceURL = URL(fileURLWithPath: descriptor.bundledResourceName)
        let name = resourceURL.deletingPathExtension().lastPathComponent
        let fileExtension = resourceURL.pathExtension
        for bundle in bundles {
            if let nested = bundle.url(
                forResource: name,
                withExtension: fileExtension,
                subdirectory: "Chapter01ContinuityProofs"
            ) {
                return nested
            }
            if let flat = bundle.url(
                forResource: name,
                withExtension: fileExtension
            ) {
                return flat
            }
        }
        return nil
    }
}

/// Resolves the canonical V2 package-relative cell paths after package
/// integrity has already been accepted by ContentDelivery.
@MainActor
public final class Chapter01DirectoryRealityAssetLocator:
    Chapter01RealityAssetLocating
{
    private let packageRootURL: URL

    public init(packageRootURL: URL) {
        self.packageRootURL = packageRootURL
    }

    public func url(for descriptor: Chapter01RealityAssetDescriptor) -> URL? {
        let candidate = packageRootURL.appending(
            path: descriptor.packageRelativePath,
            directoryHint: .notDirectory
        )
        guard FileManager.default.fileExists(atPath: candidate.path) else {
            return nil
        }
        return candidate
    }
}

/// Admits a package URL only through the caller's signed, manifest-bound
/// resolver. The runtime never receives a loose directory path when this
/// locator is used.
@MainActor
public final class Chapter01VerifiedRealityAssetLocator:
    Chapter01RealityAssetLocating
{
    public typealias Resolver = @MainActor (String) -> URL?

    private let resolver: Resolver

    public init(resolver: @escaping Resolver) {
        self.resolver = resolver
    }

    public func url(for descriptor: Chapter01RealityAssetDescriptor) -> URL? {
        resolver(descriptor.packageRelativePath)
    }
}

public enum Chapter01RealityAssetRepositoryFailure:
    Error,
    Equatable,
    LocalizedError
{
    case missingResource(cell: Chapter01WorldCell, resourceName: String)
    case loadFailed(
        cell: Chapter01WorldCell,
        resourceName: String,
        reason: String
    )
    case missingBindings(cell: Chapter01WorldCell, names: [String])
    case ambiguousBinding(
        cell: Chapter01WorldCell,
        name: String,
        candidateCount: Int
    )
    case emptyActionGeometry(cell: Chapter01WorldCell, name: String)
    case supersededRequest(cell: Chapter01WorldCell)

    public var errorDescription: String? {
        switch self {
        case let .missingResource(cell, resourceName):
            "Missing Chapter 01 USDZ resource \(resourceName) for \(cell.rawValue)."
        case let .loadFailed(cell, resourceName, reason):
            "Could not decode \(resourceName) for \(cell.rawValue): \(reason)"
        case let .missingBindings(cell, names):
            "The \(cell.rawValue) USDZ is missing runtime bindings: \(names.joined(separator: ", "))."
        case let .ambiguousBinding(cell, name, candidateCount):
            "The \(cell.rawValue) USDZ contains \(candidateCount) candidates for \(name)."
        case let .emptyActionGeometry(cell, name):
            "The action binding \(name) in \(cell.rawValue) has no collision-bearing geometry."
        case let .supersededRequest(cell):
            "The \(cell.rawValue) residency request was superseded by a newer world position."
        }
    }
}

public struct Chapter01RealityAssetValidationReport: Equatable, Sendable {
    public let cell: Chapter01WorldCell
    public let resourceName: String
    public let validatedBindingNames: [String]
    public let interactiveBindingNames: [String]
    public let qualityClassification: String
    public let finalArtGate: String
}

@MainActor
public struct Chapter01RealityAssetResidency {
    public let currentCell: Chapter01WorldCell
    public let nextCell: Chapter01WorldCell?
    public let entities: [Chapter01WorldCell: Entity]
    public let validationReports: [Chapter01RealityAssetValidationReport]

    public func entity(for cell: Chapter01WorldCell) -> Entity? {
        entities[cell]
    }
}

/// Owns only decoded scene graphs. Historical state remains in
/// `Chapter01ExperienceController`; loading or rendering can never complete a
/// beat or emit a WorldEffect.
@MainActor
public final class Chapter01RealityAssetRepository {
    public typealias EntityLoader = @MainActor (URL) async throws -> Entity

    private let locator: any Chapter01RealityAssetLocating
    private let runtimePackageContext: Chapter01RuntimePackageContext?
    private let entityLoader: EntityLoader
    private var loadedEntities: [Chapter01WorldCell: Entity] = [:]
    private var reports: [Chapter01WorldCell: Chapter01RealityAssetValidationReport] = [:]
    private var reconciliationGeneration: UInt64 = 0

    public init(
        locator: any Chapter01RealityAssetLocating = Chapter01BundledRealityAssetLocator(),
        runtimePackageContext: Chapter01RuntimePackageContext? = nil,
        entityLoader: @escaping EntityLoader = { try await Entity(contentsOf: $0) }
    ) {
        self.locator = locator
        self.runtimePackageContext = runtimePackageContext
        self.entityLoader = entityLoader
    }

    public var residentCells: [Chapter01WorldCell] {
        Chapter01WorldCell.allCases.filter { loadedEntities[$0] != nil }
    }

    /// Reconciles the cache to exactly the current cell and its successor.
    /// Stale geometry is detached before a new successor is decoded, keeping
    /// the two-cell memory ceiling true during traversal as well as afterward.
    public func reconcileResidency(
        current: Chapter01WorldCell
    ) async throws -> Chapter01RealityAssetResidency {
        reconciliationGeneration &+= 1
        let requestGeneration = reconciliationGeneration
        try await runtimePackageContext?.prepareSharedLibraryWitnesses()
        let allCells = Chapter01WorldCell.allCases
        let currentIndex = allCells.firstIndex(of: current)!
        let next = currentIndex + 1 < allCells.count
            ? allCells[currentIndex + 1]
            : nil
        let requiredCells = [current, next].compactMap { $0 }
        let requiredSet = Set(requiredCells)

        for stale in loadedEntities.keys where !requiredSet.contains(stale) {
            loadedEntities[stale]?.removeFromParent()
            loadedEntities[stale] = nil
            reports[stale] = nil
        }

        for cell in requiredCells where loadedEntities[cell] == nil {
            let descriptor = Chapter01RealityAssetCatalog.descriptor(for: cell)
            let loaded = try await loadAndValidate(descriptor)
            guard requestGeneration == reconciliationGeneration else {
                loaded.entity.removeFromParent()
                throw Chapter01RealityAssetRepositoryFailure.supersededRequest(
                    cell: current
                )
            }
            loaded.entity.isEnabled = cell == current
            loadedEntities[cell] = loaded.entity
            reports[cell] = loaded.report
        }

        for cell in requiredCells {
            loadedEntities[cell]?.isEnabled = cell == current
        }

        return Chapter01RealityAssetResidency(
            currentCell: current,
            nextCell: next,
            entities: Dictionary(uniqueKeysWithValues: requiredCells.compactMap {
                cell in loadedEntities[cell].map { (cell, $0) }
            }),
            validationReports: requiredCells.compactMap { reports[$0] }
        )
    }

    public func removeAll() {
        reconciliationGeneration &+= 1
        for entity in loadedEntities.values {
            entity.removeFromParent()
        }
        loadedEntities.removeAll(keepingCapacity: false)
        reports.removeAll(keepingCapacity: false)
    }

    private func loadAndValidate(
        _ descriptor: Chapter01RealityAssetDescriptor
    ) async throws -> (
        entity: Entity,
        report: Chapter01RealityAssetValidationReport
    ) {
        let url: URL
        if let runtimePackageContext {
            // The V2 world cell selects its scene graph by stable asset ID;
            // descriptor paths are not consulted on the signed-package path.
            url = try runtimePackageContext.resolveSceneGraph(
                for: descriptor.cell
            )
        } else {
            guard let locatedURL = locator.url(for: descriptor) else {
                throw Chapter01RealityAssetRepositoryFailure.missingResource(
                    cell: descriptor.cell,
                    resourceName: descriptor.bundledResourceName
                )
            }
            url = locatedURL
        }
        let resourceName = runtimePackageContext == nil
            ? descriptor.bundledResourceName
            : url.lastPathComponent

        let entity: Entity
        do {
            entity = try await entityLoader(url)
        } catch let failure as Chapter01RealityAssetRepositoryFailure {
            throw failure
        } catch {
            throw Chapter01RealityAssetRepositoryFailure.loadFailed(
                cell: descriptor.cell,
                resourceName: resourceName,
                reason: String(describing: error)
            )
        }

        let bindingMap = try canonicalizeBindings(
            in: entity,
            descriptor: descriptor
        )
        for name in descriptor.suppressedVisualBindingNames {
            bindingMap[name]?.components.set(OpacityComponent(opacity: 0))
        }
        for name in descriptor.actionBindingNames {
            guard let action = bindingMap[name] else {
                // The required-binding check above normally owns this path.
                throw Chapter01RealityAssetRepositoryFailure.missingBindings(
                    cell: descriptor.cell,
                    names: [name]
                )
            }
            try makeActionEntityInteractive(
                action,
                name: name,
                cell: descriptor.cell,
                isVisible: !descriptor.nonVisualActionBindingNames.contains(name)
            )
        }

        return (
            entity,
            Chapter01RealityAssetValidationReport(
                cell: descriptor.cell,
                resourceName: resourceName,
                validatedBindingNames: descriptor.requiredBindingNames,
                interactiveBindingNames: descriptor.actionBindingNames,
                qualityClassification: Chapter01RealityAssetCatalog
                    .continuityProofClassification,
                finalArtGate: Chapter01RealityAssetCatalog.finalArtGate
            )
        )
    }

    private func canonicalizeBindings(
        in root: Entity,
        descriptor: Chapter01RealityAssetDescriptor
    ) throws -> [String: Entity] {
        let allEntities = flattenedEntities(root)
        var result: [String: Entity] = [:]
        var missing: [String] = []

        for canonicalName in descriptor.requiredBindingNames {
            let exact = allEntities.filter { $0.name == canonicalName }
            let candidates: [Entity]
            if exact.isEmpty {
                let usdIdentifier = canonicalName.replacingOccurrences(
                    of: "-",
                    with: "_"
                )
                candidates = allEntities.filter { $0.name == usdIdentifier }
            } else {
                candidates = exact
            }

            guard !candidates.isEmpty else {
                missing.append(canonicalName)
                continue
            }
            guard candidates.count == 1 else {
                throw Chapter01RealityAssetRepositoryFailure.ambiguousBinding(
                    cell: descriptor.cell,
                    name: canonicalName,
                    candidateCount: candidates.count
                )
            }
            let candidate = candidates[0]
            candidate.name = canonicalName
            result[canonicalName] = candidate
        }

        guard missing.isEmpty else {
            throw Chapter01RealityAssetRepositoryFailure.missingBindings(
                cell: descriptor.cell,
                names: missing.sorted()
            )
        }
        return result
    }

    private func makeActionEntityInteractive(
        _ action: Entity,
        name: String,
        cell: Chapter01WorldCell,
        isVisible: Bool
    ) throws {
        let bounds = action.visualBounds(
            recursive: true,
            relativeTo: action,
            excludeInactive: false
        )
        guard !bounds.isEmpty,
              bounds.extents.x.isFinite,
              bounds.extents.y.isFinite,
              bounds.extents.z.isFinite else {
            throw Chapter01RealityAssetRepositoryFailure.emptyActionGeometry(
                cell: cell,
                name: name
            )
        }

        let minimumTargetExtent: Float = 0.08
        let size = SIMD3<Float>(
            max(bounds.extents.x, minimumTargetExtent),
            max(bounds.extents.y, minimumTargetExtent),
            max(bounds.extents.z, minimumTargetExtent)
        )
        let collisionShape = ShapeResource.generateBox(size: size)
            .offsetBy(translation: bounds.center)
        action.components.set(InputTargetComponent(allowedInputTypes: .all))
        action.components.set(CollisionComponent(shapes: [collisionShape]))
        if !isVisible {
            action.components.set(OpacityComponent(opacity: 0))
        }
    }

    private func flattenedEntities(_ root: Entity) -> [Entity] {
        var entities = [root]
        for child in root.children {
            entities.append(contentsOf: flattenedEntities(child))
        }
        return entities
    }
}
