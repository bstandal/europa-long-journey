import RealityKit
import SwiftUI

public enum Chapter01RealityWorldAssetState: Equatable, Sendable {
    case idle
    case loading(Chapter01WorldCell)
    case ready(current: Chapter01WorldCell, resident: [Chapter01WorldCell])
    case failed(current: Chapter01WorldCell, message: String)
}

@MainActor
public final class Chapter01RealityWorld {
    public let root = Entity()
    public let camera = PerspectiveCamera()
    public private(set) var assetState: Chapter01RealityWorldAssetState = .idle

    private let palette = Chapter01RealityPrimitives.palette
    private let transitionCarrier = Entity()
    private let assetRepository: Chapter01RealityAssetRepository
    private let usesVerifiedRuntimePackageContext: Bool
    private var loadedCells: [Chapter01WorldCell: Entity] = [:]
    private var authoredAssetCells = Set<Chapter01WorldCell>()
    private var residencyTask: Task<Void, Never>?
    private var requestedResidencyCell: Chapter01WorldCell?
    private var lastCell: Chapter01WorldCell?
    private var lastBeatID: String?

    public init(
        runtimePackageContext: Chapter01RuntimePackageContext? = nil,
        assetRepository: Chapter01RealityAssetRepository? = nil
    ) {
        usesVerifiedRuntimePackageContext = runtimePackageContext != nil
        self.assetRepository = assetRepository
            ?? Chapter01RealityAssetRepository(
                runtimePackageContext: runtimePackageContext
            )
        root.name = "chapter01-world"
        camera.name = "chapter01-camera"
        camera.camera = PerspectiveCameraComponent(
            near: 0.05,
            far: 180,
            // Authored cameras were composed against a 3:4 portrait render.
            // A 0.46-aspect iPhone needs the wider vertical cone below to
            // preserve that horizontal composition instead of cropping the
            // active hands behind foreground architecture.
            fieldOfViewInDegrees: 68,
            fieldOfViewOrientation: .vertical
        )
        root.addChild(camera)
        configureTransitionCarrier()
        addWorldLighting()
    }

    deinit {
        residencyTask?.cancel()
    }

    public func prepare(initialCell: Chapter01WorldCell) async {
        await reconcileResidency(current: initialCell)
        configureCamera(
            for: initialCell,
            sequenceProgress: 0,
            beatID: nil,
            beatProgress: 0,
            reduceMotion: false
        )
    }

    public func update(
        from controller: Chapter01ExperienceController,
        reduceMotion: Bool,
        elapsedTime: TimeInterval = 0
    ) {
        let cell = controller.currentCell
        if requestedResidencyCell != cell {
            scheduleResidency(current: cell)
        }
        loadedCells.forEach { key, value in
            value.isEnabled = key == cell
        }

        let cellOrBeatChanged = lastCell != cell || lastBeatID != controller.currentBeat.id
        lastCell = cell
        lastBeatID = controller.currentBeat.id
        if cellOrBeatChanged || !reduceMotion {
            configureCamera(
                for: cell,
                sequenceProgress: controller.normalizedSequenceProgress,
                beatID: controller.currentBeat.id,
                beatProgress: controller.currentBeatProgress,
                reduceMotion: reduceMotion
            )
        }

        guard let active = loadedCells[cell] else { return }
        let progress = Float(controller.normalizedSequenceProgress)
        let transient = Float(controller.transientManipulation)
        switch cell {
        case .aegeanPassage:
            updateAegean(active, progress: progress, transient: transient)
        case .thessalianHousehold:
            updateThessaly(
                active,
                controller: controller,
                progress: progress,
                transient: transient
            )
        case .ironGates:
            updateIronGates(active, progress: progress, transient: transient)
        case .longhouseGround:
            updateLonghouse(active, progress: progress, transient: transient)
        case .settlementLandscape:
            updateSettlement(active, controller: controller, progress: progress, transient: transient)
        }
        animateLivingWorld(active, cell: cell, elapsedTime: elapsedTime, reduceMotion: reduceMotion)
        updateCarrier(from: controller, reduceMotion: reduceMotion)
    }

    private func scheduleResidency(current: Chapter01WorldCell) {
        requestedResidencyCell = current
        residencyTask?.cancel()
        residencyTask = Task { [weak self] in
            await self?.reconcileResidency(current: current)
        }
    }

    private func reconcileResidency(current: Chapter01WorldCell) async {
        requestedResidencyCell = current
        assetState = .loading(current)
        do {
            let residency = try await assetRepository.reconcileResidency(
                current: current
            )
            guard requestedResidencyCell == current else { return }
            mount(residency)
            assetState = .ready(
                current: current,
                resident: residency.entities.keys.sorted {
                    cellIndex($0) < cellIndex($1)
                }
            )
        } catch Chapter01RealityAssetRepositoryFailure.supersededRequest {
            return
        } catch {
            guard requestedResidencyCell == current else { return }
            if !usesVerifiedRuntimePackageContext {
                installContinuityFallback(current: current)
            }
            assetState = .failed(
                current: current,
                message: String(describing: error)
            )
        }
    }

    private func mount(_ residency: Chapter01RealityAssetResidency) {
        let residentCells = Set(residency.entities.keys)
        for stale in loadedCells.keys where !residentCells.contains(stale) {
            loadedCells[stale]?.removeFromParent()
            loadedCells[stale] = nil
            authoredAssetCells.remove(stale)
        }
        for (cell, entity) in residency.entities {
            if let replaced = loadedCells[cell], replaced !== entity {
                replaced.removeFromParent()
            }
            if entity.parent == nil {
                root.addChild(entity)
            }
            entity.isEnabled = cell == residency.currentCell
            loadedCells[cell] = entity
            authoredAssetCells.insert(cell)
        }
    }

    private func installContinuityFallback(current: Chapter01WorldCell) {
#if DEBUG || NON_SHIPPING_LIVE_TEST
        let cells = Chapter01WorldCell.allCases
        let currentIndex = cells.firstIndex(of: current) ?? 0
        let next = currentIndex + 1 < cells.count ? cells[currentIndex + 1] : nil
        let keep = Set([current, next].compactMap { $0 })
        for stale in loadedCells.keys where !keep.contains(stale) {
            loadedCells[stale]?.removeFromParent()
            loadedCells[stale] = nil
            authoredAssetCells.remove(stale)
        }
        for cell in keep where loadedCells[cell] == nil {
            let entity = build(cell)
            entity.isEnabled = cell == current
            loadedCells[cell] = entity
            root.addChild(entity)
        }
#endif
    }

    private func cellIndex(_ cell: Chapter01WorldCell) -> Int {
        Chapter01WorldCell.allCases.firstIndex(of: cell) ?? .max
    }

    private func build(_ cell: Chapter01WorldCell) -> Entity {
        switch cell {
        case .aegeanPassage: buildAegean()
        case .thessalianHousehold: buildThessaly()
        case .ironGates: buildIronGates()
        case .longhouseGround: buildLonghouse()
        case .settlementLandscape: buildSettlementLandscape()
        }
    }

    private func addWorldLighting() {
        let sun = DirectionalLight()
        sun.name = "low-sun"
        sun.light.color = Chapter01NativeColor(
            red: 0.96,
            green: 0.72,
            blue: 0.44,
            alpha: 1
        )
        sun.light.intensity = 2_400
        sun.look(at: [0, 0, 0], from: [-6, 9, 6], relativeTo: root)
        root.addChild(sun)

        let fill = DirectionalLight()
        fill.name = "cool-fill"
        fill.light.color = Chapter01NativeColor(
            red: 0.22,
            green: 0.32,
            blue: 0.38,
            alpha: 1
        )
        fill.light.intensity = 850
        fill.look(at: [0, 0, 0], from: [5, 4, -5], relativeTo: root)
        root.addChild(fill)
    }

    private func configureTransitionCarrier() {
        transitionCarrier.name = "chapter01-transition-carrier"
        transitionCarrier.isEnabled = false
        transitionCarrier.position = [0, -0.08, -1.18]
        transitionCarrier.addChild(Chapter01RealityPrimitives.pot(
            "carrier-vessel",
            at: .zero,
            scale: 0.42
        ))
        transitionCarrier.addChild(Chapter01RealityPrimitives.sphere(
            "carrier-seed",
            radius: 0.055,
            material: palette.activeGold,
            at: [0, 0.05, 0.16]
        ))
        camera.addChild(transitionCarrier)
    }

    private func updateCarrier(
        from controller: Chapter01ExperienceController,
        reduceMotion: Bool
    ) {
        guard let transition = controller.state.experience.transition else {
            transitionCarrier.isEnabled = false
            return
        }
        let progress = Float(min(max(transition.progress, 0), 1))
        transitionCarrier.isEnabled = true
        transitionCarrier.name = transition.carrierID
        let envelope = sin(progress * .pi)
        transitionCarrier.scale = .one * (0.76 + envelope * 0.84)
        transitionCarrier.position = [0, -0.08, -1.18]
        transitionCarrier.orientation = simd_quatf(angle: 0, axis: [0, 1, 0])
        if !reduceMotion {
            transitionCarrier.orientation = simd_quatf(
                angle: progress * 0.42,
                axis: [0, 1, 0]
            )
            transitionCarrier.position.x = (progress - 0.5) * 0.16
        }
    }

    private func animateLivingWorld(
        _ cell: Entity,
        cell cellID: Chapter01WorldCell,
        elapsedTime: TimeInterval,
        reduceMotion: Bool
    ) {
        let time = Float(elapsedTime)
        let materialPulse = sin(time * 2.1)
        switch cellID {
        case .aegeanPassage:
            for index in 0 ..< 14 {
                guard let current = cell.findEntity(named: "current-\(index)") else { continue }
                current.position.x += sin(time * 0.55 + Float(index)) * 0.0009
                current.scale.x = 0.82 + (sin(time * 1.3 + Float(index)) + 1) * 0.12
            }
            if !reduceMotion, let boat = cell.findEntity(named: "crossing-boat") {
                boat.position.y = 0.12 + sin(time * 1.7) * 0.025
            }
        case .thessalianHousehold:
            if let flame = cell.findEntity(named: "household-hearth-flame") {
                flame.scale = [0.92 + materialPulse * 0.08, 0.88 - materialPulse * 0.06, 0.92 + materialPulse * 0.08]
            }
            if let rain = cell.findEntity(named: "winter-rain"), rain.isEnabled {
                for (index, drop) in rain.children.enumerated() {
                    var y = drop.position.y - 0.018 - Float(index % 3) * 0.002
                    if y < 0.05 { y = 3.6 }
                    drop.position.y = y
                }
            }
        case .ironGates:
            if let line = cell.findEntity(named: "action-landing-line") {
                line.scale.x = 1 + materialPulse * 0.025
            }
        case .longhouseGround:
            if let flame = cell.findEntity(named: "action-hearth-flame"), flame.isEnabled {
                flame.scale = [0.92 + materialPulse * 0.07, 0.9 - materialPulse * 0.05, 0.92 + materialPulse * 0.07]
            }
        case .settlementLandscape:
            if let water = cell.findEntity(named: "valley-water") {
                water.scale.x = 1 + materialPulse * 0.01
            }
        }
    }

    private func configureCamera(
        for cell: Chapter01WorldCell,
        sequenceProgress: Double,
        beatID: String?,
        beatProgress: Double,
        reduceMotion: Bool
    ) {
        if authoredAssetCells.contains(cell),
           configureAuthoredCamera(
               for: cell,
               sequenceProgress: sequenceProgress,
               beatID: beatID,
               beatProgress: beatProgress,
               reduceMotion: reduceMotion
           ) {
            return
        }
        let p = Float(sequenceProgress)
        let position: SIMD3<Float>
        let target: SIMD3<Float>
        switch cell {
        case .aegeanPassage:
            position = reduceMotion ? [0, 2.20, 6.80] : [-0.35 + p * 0.5, 2.05 + p * 0.18, 6.55 - p * 0.35]
            target = [0, 0.75, 0]
        case .thessalianHousehold:
            position = reduceMotion ? [0, 3.20, 7.60] : [0.35 - p * 0.55, 2.85 + p * 0.3, 7.25 - p * 0.45]
            target = [0, 0.55, -0.3]
        case .ironGates:
            position = reduceMotion ? [0, 2.55, 7.30] : [-0.45 + p * 0.65, 2.35, 7.10 - p * 0.40]
            target = [0, 0.72, -0.5]
        case .longhouseGround:
            position = reduceMotion ? [0, 2.95, 8.20] : [0.45 - p * 0.7, 2.75 + p * 0.25, 7.90 - p * 0.35]
            target = [0, 1.05, -0.7]
        case .settlementLandscape:
            let finaleLift = lastBeatID == "continent-condition" || lastBeatID == "eastern-grass"
            position = reduceMotion
                ? [0, finaleLift ? 5.8 : 3.8, finaleLift ? 10.5 : 8.8]
                : [0.4 - p * 0.5, finaleLift ? 5.5 : 3.5 + p * 0.4, finaleLift ? 10.0 : 8.4 - p * 0.4]
            target = [0, finaleLift ? 0.2 : 0.75, -1.3]
        }
        camera.look(at: target, from: position, relativeTo: root)
    }

    private struct AuthoredCameraMoment {
        let anchorName: String
        let focusName: String
    }

    private func configureAuthoredCamera(
        for cell: Chapter01WorldCell,
        sequenceProgress: Double,
        beatID: String?,
        beatProgress: Double,
        reduceMotion: Bool
    ) -> Bool {
        guard let loaded = loadedCells[cell] else { return false }
        let moments = authoredCameraMoments(
            for: cell,
            beatID: beatID,
            reduceMotion: reduceMotion
        )
        guard !moments.isEmpty else { return false }

        let selectedProgress = beatID == nil ? sequenceProgress : beatProgress
        let bounded = Float(min(max(selectedProgress, 0), 1))
        let scaled = bounded * Float(max(moments.count - 1, 0))
        let lowerIndex = min(Int(floor(scaled)), moments.count - 1)
        let upperIndex = reduceMotion
            ? lowerIndex
            : min(lowerIndex + 1, moments.count - 1)
        let blend = reduceMotion ? Float(0) : scaled - Float(lowerIndex)

        guard let lowerAnchor = loaded.findEntity(
                  named: moments[lowerIndex].anchorName
              ),
              let upperAnchor = loaded.findEntity(
                  named: moments[upperIndex].anchorName
              ),
              let lowerFocus = loaded.findEntity(
                  named: moments[lowerIndex].focusName
              ),
              let upperFocus = loaded.findEntity(
                  named: moments[upperIndex].focusName
              ) else {
            return false
        }
        let lowerPosition = lowerAnchor.position(relativeTo: root)
        let upperPosition = upperAnchor.position(relativeTo: root)
        let lowerOrientation = lowerAnchor.orientation(relativeTo: root)
        let upperOrientation = upperAnchor.orientation(relativeTo: root)
        let lowerTarget = lowerFocus.visualBounds(
            recursive: true,
            relativeTo: root,
            excludeInactive: false
        ).center
        let upperTarget = upperFocus.visualBounds(
            recursive: true,
            relativeTo: root,
            excludeInactive: false
        ).center
        let authoredPosition = simd_mix(
            lowerPosition,
            upperPosition,
            SIMD3(repeating: blend)
        )
        let target = simd_mix(lowerTarget, upperTarget, SIMD3(repeating: blend))
        let orientation = simd_slerp(lowerOrientation, upperOrientation, blend)
        // The DCC composition used a wider 3:4 portrait. Move backward on the
        // camera's own optical axis so the narrower iPhone canvas gains
        // context without shifting the authored centre of attention.
        let authoredDistance = simd_length(authoredPosition - target)
        let portraitPullbackFactor: Float = switch cell {
        case .aegeanPassage: 0.05
        case .thessalianHousehold: 0.32
        case .ironGates: 0.14
        case .longhouseGround: 0.18
        case .settlementLandscape: 0.18
        }
        let portraitPullback = orientation.act(
            SIMD3<Float>(
                0,
                0,
                authoredDistance * portraitPullbackFactor
            )
        )
        let position = authoredPosition + portraitPullback
        guard position.x.isFinite, position.y.isFinite, position.z.isFinite,
              target.x.isFinite, target.y.isFinite, target.z.isFinite,
              orientation.vector.x.isFinite,
              orientation.vector.y.isFinite,
              orientation.vector.z.isFinite,
              orientation.vector.w.isFinite else {
            return false
        }
        // The authored anchor owns camera placement. Re-aim at the validated
        // semantic focus after portrait pullback so a narrow device cannot
        // crop the hands or material that carry the current cause.
        camera.look(at: target, from: position, relativeTo: root)
        return true
    }

    private func authoredCameraMoments(
        for cell: Chapter01WorldCell,
        beatID: String?,
        reduceMotion: Bool
    ) -> [AuthoredCameraMoment] {
        switch cell {
        case .aegeanPassage:
            switch beatID {
            case "cross-current":
                return [
                    .init(anchorName: "camera-entry", focusName: "crossing-boat"),
                    .init(anchorName: "camera-action-close", focusName: "action-crossing-line"),
                ]
            case "load-under-tension":
                return [
                    .init(anchorName: "camera-action-close", focusName: "action-crossing-line"),
                    .init(anchorName: "camera-seed-close", focusName: "seed-vessel"),
                ]
            case "dry-bank-transfer":
                return [
                    .init(anchorName: "camera-seed-close", focusName: "seed-vessel"),
                    .init(anchorName: "camera-shore-reveal", focusName: "western-shore"),
                ]
            case "seed-leaves-water":
                return [
                    .init(anchorName: "camera-shore-reveal", focusName: "western-shore"),
                ]
            default:
                return [
                    .init(anchorName: "camera-entry", focusName: "crossing-boat"),
                ]
            }
        case .thessalianHousehold:
            switch beatID {
            case "first-furrow":
                return [
                    .init(anchorName: "camera-spring-sowing", focusName: "action-spring-sow"),
                ]
            case "worked-season":
                return [
                    .init(anchorName: "camera-harvest-overview", focusName: "action-grain-source"),
                ]
            case "finite-harvest":
                return [
                    .init(anchorName: "camera-harvest-overview", focusName: "action-grain-source"),
                    .init(anchorName: "camera-allocation-close", focusName: "action-seed"),
                ]
            case "three-claims", "food-committed", "reserve-raised", "seed-sealed":
                return [
                    .init(anchorName: "camera-allocation-close", focusName: "action-seed"),
                ]
            case "winter-breach":
                return [
                    .init(anchorName: "camera-winter-loss", focusName: "action-store-repair"),
                    .init(anchorName: "camera-repair", focusName: "action-store-repair"),
                ]
            case "spring-return":
                return [
                    .init(anchorName: "camera-spring-sowing", focusName: "action-spring-sow"),
                ]
            default:
                return [
                    .init(anchorName: "camera-harvest-overview", focusName: "action-grain-source"),
                ]
            }
        case .ironGates:
            if reduceMotion {
                return [
                    .init(
                        anchorName: "camera-iron-gates-reduce-motion",
                        focusName: "action-landing-line"
                    ),
                ]
            }
            switch beatID {
            case "later-hands":
                return [.init(anchorName: "camera-iron-gates-entry", focusName: "iron-gates-boat")]
            case "inhabited-bank":
                return [
                    .init(anchorName: "camera-iron-gates-entry", focusName: "iron-gates-boat"),
                    .init(anchorName: "camera-iron-gates-landing", focusName: "action-landing-line"),
                ]
            case "forces-align":
                return [.init(anchorName: "camera-iron-gates-landing", focusName: "action-landing-line")]
            case "two-way-load":
                return [
                    .init(anchorName: "camera-iron-gates-landing", focusName: "action-landing-line"),
                    .init(anchorName: "camera-iron-gates-handoff", focusName: "iron-gates-local-guide"),
                ]
            case "route-inland":
                return [.init(anchorName: "camera-iron-gates-handoff", focusName: "iron-gates-local-guide")]
            default:
                return [.init(anchorName: "camera-iron-gates-entry", focusName: "iron-gates-boat")]
            }
        case .longhouseGround:
            if reduceMotion {
                return [
                    .init(
                        anchorName: "camera-longhouse-reduce-motion",
                        focusName: "longhouse-frame"
                    ),
                ]
            }
            switch beatID {
            case "prepared-ground":
                return [.init(anchorName: "camera-longhouse-approach", focusName: "longhouse-frame")]
            case "frame-rises":
                return [
                    .init(anchorName: "camera-longhouse-approach", focusName: "longhouse-frame"),
                    .init(anchorName: "camera-longhouse-raise", focusName: "longhouse-raising-line"),
                ]
            case "shelter-holds":
                return [
                    .init(anchorName: "camera-longhouse-raise", focusName: "longhouse-raising-line"),
                    .init(anchorName: "camera-longhouse-hearth", focusName: "action-hearth"),
                ]
            case "timber-replaced":
                return [
                    .init(anchorName: "camera-longhouse-hearth", focusName: "action-hearth"),
                    .init(anchorName: "camera-longhouse-repair", focusName: "action-roof"),
                ]
            case "plot-crowds":
                return [.init(anchorName: "camera-longhouse-repair", focusName: "action-roof")]
            default:
                return [.init(anchorName: "camera-longhouse-approach", focusName: "longhouse-frame")]
            }
        case .settlementLandscape:
            if reduceMotion {
                return [
                    .init(
                        anchorName: "camera-expansion-reduce-motion",
                        focusName: "action-final-gate"
                    ),
                ]
            }
            switch beatID {
            case "enclosure-opens", "herd-finds-water":
                return [.init(anchorName: "camera-expansion-herd", focusName: "moving-herd")]
            case "field-edge":
                return [.init(anchorName: "camera-expansion-field-edge", focusName: "daughter-field")]
            case "daughter-clearing", "settlement-grows":
                return [.init(anchorName: "camera-expansion-daughter", focusName: "daughter-settlement")]
            case "hearth-cools", "clearing-regrows":
                return [
                    .init(anchorName: "camera-expansion-daughter", focusName: "daughter-settlement"),
                    .init(anchorName: "camera-expansion-final", focusName: "action-final-gate"),
                ]
            case "basket-relay":
                return [.init(anchorName: "camera-expansion-daughter", focusName: "daughter-settlement")]
            case "coupled-load", "continent-condition", "eastern-grass":
                return [.init(anchorName: "camera-expansion-final", focusName: "action-final-gate")]
            default:
                return [.init(anchorName: "camera-expansion-herd", focusName: "moving-herd")]
            }
        }
    }

    // MARK: Aegean passage

    private func buildAegean() -> Entity {
        let cell = Entity()
        cell.name = Chapter01WorldCell.aegeanPassage.rawValue
        cell.addChild(Chapter01RealityPrimitives.box(
            "aegean-water",
            size: [18, 0.08, 18],
            material: palette.water,
            at: [0, -0.18, -2]
        ))
        for index in 0 ..< 14 {
            let x = Float(index % 7) * 1.6 - 4.8
            let z = Float(index / 7) * -3.0 - 1.0
            let current = Chapter01RealityPrimitives.box(
                "current-\(index)",
                size: [1.05, 0.018, 0.06],
                material: palette.waterHighlight,
                at: [x, -0.10, z]
            )
            current.orientation = simd_quatf(angle: -0.25, axis: [0, 1, 0])
            cell.addChild(current)
        }

        let boat = Entity()
        boat.name = "crossing-boat"
        boat.position = [0, 0.12, 0]
        boat.addChild(Chapter01RealityPrimitives.box(
            "boat-floor",
            size: [2.35, 0.18, 1.05],
            material: palette.oldTimber,
            at: [0, 0, 0],
            cornerRadius: 0.18
        ))
        for side: Float in [-0.54, 0.54] {
            let rail = Chapter01RealityPrimitives.box(
                "boat-rail",
                size: [2.5, 0.30, 0.12],
                material: palette.timber,
                at: [0, 0.22, side],
                cornerRadius: 0.05
            )
            rail.orientation = simd_quatf(angle: side * 0.08, axis: [1, 0, 0])
            boat.addChild(rail)
        }
        boat.addChild(Chapter01RealityPrimitives.person(
            "crossing-adult", at: [-0.68, 0.15, -0.22], scale: 0.92, workingPose: 0.18
        ))
        boat.addChild(Chapter01RealityPrimitives.person(
            "crossing-youth", at: [0.28, 0.14, -0.18], scale: 0.72, tunic: palette.clothLight, workingPose: 0.32
        ))
        boat.addChild(Chapter01RealityPrimitives.cattle(
            "crossing-cattle", at: [-0.15, 0.12, 0.30], scale: 0.58
        ))
        boat.addChild(Chapter01RealityPrimitives.pot(
            "seed-vessel", at: [0.56, 0.54, 0.22], scale: 0.75
        ))
        let line = Chapter01RealityPrimitives.cylinder(
            "action-crossing-line",
            height: 2.2,
            radius: 0.045,
            material: palette.activeGold,
            at: [0.95, 0.78, 0.22],
            rotation: simd_quatf(angle: .pi / 2.7, axis: [0, 0, 1]),
            interactive: true
        )
        boat.addChild(line)
        cell.addChild(boat)

        let farBoat = boat.clone(recursive: true)
        farBoat.name = "household-boat-far"
        farBoat.scale = .one * 0.48
        farBoat.position = [-3.3, 0.03, -4.2]
        farBoat.orientation = simd_quatf(angle: 0.18, axis: [0, 1, 0])
        farBoat.visit { entity in
            entity.components.remove(InputTargetComponent.self)
            entity.components.remove(CollisionComponent.self)
        }
        cell.addChild(farBoat)

        let shore = Chapter01RealityPrimitives.box(
            "western-shore",
            size: [18, 0.7, 7],
            material: palette.earth,
            at: [0, -0.25, -8]
        )
        shore.orientation = simd_quatf(angle: -0.05, axis: [1, 0, 0])
        cell.addChild(shore)
        return cell
    }

    private func updateAegean(_ cell: Entity, progress: Float, transient: Float) {
        guard let boat = cell.findEntity(named: "crossing-boat") else { return }
        let response = min(progress + transient * 0.18, 1)
        boat.orientation = simd_quatf(
            angle: -0.13 + response * 0.16,
            axis: [0, 0, 1]
        )
        boat.position.x = response * 0.35
        if let line = boat.findEntity(named: "action-crossing-line") {
            line.position.y = 0.72 + response * 0.24
            line.scale = [1, 1 + response * 0.06, 1]
        }
        if let pot = boat.findEntity(named: "seed-vessel") {
            pot.position.y = 0.50 + response * 0.27
        }
    }

    // MARK: Thessaly

    private func buildThessaly() -> Entity {
        let cell = Entity()
        cell.name = Chapter01WorldCell.thessalianHousehold.rawValue
        cell.addChild(Chapter01RealityPrimitives.box(
            "thessaly-ground",
            size: [18, 0.35, 18],
            material: palette.earth,
            at: [0, -0.25, -2]
        ))

        let field = Entity()
        field.name = "worked-field"
        field.position = [0, 0, -3.5]
        for row in 0 ..< 7 {
            for stalk in 0 ..< 13 {
                let height = Float(0.30 + Double((row + stalk) % 4) * 0.035)
                field.addChild(Chapter01RealityPrimitives.cylinder(
                    "crop-\(row)-\(stalk)",
                    height: height,
                    radius: 0.014,
                    material: palette.straw,
                    at: [Float(stalk) * 0.31 - 1.86, height / 2, Float(row) * -0.34]
                ))
            }
        }
        cell.addChild(field)

        let grainSource = Chapter01RealityPrimitives.sphere(
            "action-grain-source",
            radius: 0.72,
            material: palette.grain,
            at: [0, 0.55, 0.6],
            interactive: true
        )
        grainSource.scale = [1.45, 0.58, 1]
        cell.addChild(grainSource)

        cell.addChild(Chapter01RealityPrimitives.hearth("household-hearth", at: [-2.0, 0, -0.25]))
        cell.addChild(Chapter01RealityPrimitives.pot("action-food", at: [-1.6, 0.25, 0.55], scale: 0.95, interactive: true))
        cell.addChild(Chapter01RealityPrimitives.pot("action-reserve", at: [0, 1.12, -0.9], scale: 1.05, interactive: true))
        cell.addChild(Chapter01RealityPrimitives.pot("action-seed", at: [1.65, 0.30, 0.52], scale: 0.90, interactive: true))

        for (name, x, material) in [
            ("food-grain", Float(-1.6), palette.grain),
            ("reserve-grain", Float(0), palette.grain),
            ("seed-grain", Float(1.65), palette.grain),
        ] {
            let pile = Chapter01RealityPrimitives.sphere(
                name,
                radius: 0.26,
                material: material,
                at: [x, name == "reserve-grain" ? 1.43 : 0.58, name == "reserve-grain" ? -0.9 : 0.52]
            )
            pile.scale = [1, 0.18, 1]
            cell.addChild(pile)
        }

        cell.addChild(Chapter01RealityPrimitives.person(
            "thessaly-adult", at: [-1.2, 0, -1.1], scale: 0.98, workingPose: 0.32
        ))
        cell.addChild(Chapter01RealityPrimitives.person(
            "thessaly-youth", at: [1.0, 0, -0.7], scale: 0.74, tunic: palette.clothLight, workingPose: 0.38
        ))

        let store = Entity()
        store.name = "raised-store"
        store.position = [0, 0, -1.5]
        for x: Float in [-0.65, 0.65] {
            store.addChild(Chapter01RealityPrimitives.cylinder("store-post", height: 1.5, radius: 0.09, material: palette.timber, at: [x, 0.75, 0]))
        }
        store.addChild(Chapter01RealityPrimitives.box("store-platform", size: [1.7, 0.16, 1.2], material: palette.timber, at: [0, 1.35, 0]))
        cell.addChild(store)

        let rain = Entity()
        rain.name = "winter-rain"
        for index in 0 ..< 38 {
            let x = Float((index * 17) % 31) / 31 * 7 - 3.5
            let z = Float((index * 11) % 29) / 29 * 6 - 3
            rain.addChild(Chapter01RealityPrimitives.cylinder(
                "rain-drop", height: 0.42, radius: 0.006, material: palette.mist,
                at: [x, Float(index % 7) * 0.42 + 1.1, z],
                rotation: simd_quatf(angle: -0.13, axis: [0, 0, 1])
            ))
        }
        rain.isEnabled = false
        cell.addChild(rain)
        return cell
    }

    private func updateThessaly(
        _ cell: Entity,
        controller: Chapter01ExperienceController,
        progress: Float,
        transient: Float
    ) {
        let values = controller.allocationValues
        let total = Float(values.values.reduce(0, +))
        if let source = cell.findEntity(named: "action-grain-source") {
            let remaining = max(0.12, 1 - total / 12)
            source.scale = [1.45 * remaining.squareRoot(), 0.25 + remaining * 0.33, remaining.squareRoot()]
            source.position.y = 0.40 + transient * 0.12
        }
        for (id, entityName) in [
            ("food", "food-grain"),
            ("reserve", "reserve-grain"),
            ("seed", "seed-grain"),
        ] {
            if let pile = cell.findEntity(named: entityName) {
                let amount = Float(values[id, default: 0]) / 4
                pile.scale = [0.45 + amount * 0.75, 0.08 + amount * 0.45, 0.45 + amount * 0.75]
            }
        }
        let winter = ["winter-breach", "spring-return"].contains(controller.currentBeat.visualState)
        cell.findEntity(named: "winter-rain")?.isEnabled = winter && controller.currentBeat.visualState != "spring-return"
        if controller.currentBeat.visualState == "spring-return" {
            cell.findEntity(named: "worked-field")?.children.forEach { child in
                if let model = child as? ModelEntity {
                    model.model?.materials = [palette.spring]
                }
            }
        }
        _ = progress
    }

    // MARK: Iron Gates

    private func buildIronGates() -> Entity {
        let cell = Entity()
        cell.name = Chapter01WorldCell.ironGates.rawValue
        cell.addChild(Chapter01RealityPrimitives.box("gorge-water", size: [7, 0.10, 20], material: palette.water, at: [-0.8, -0.12, -3]))
        for side: Float in [-1, 1] {
            let cliff = Chapter01RealityPrimitives.box(
                "gorge-cliff", size: [5.2, 8, 20], material: palette.stone,
                at: [side * 4.8, 2.2, -4]
            )
            cliff.orientation = simd_quatf(angle: side * 0.10, axis: [0, 0, 1])
            cell.addChild(cliff)
        }
        cell.addChild(Chapter01RealityPrimitives.box("landing-stone", size: [2.1, 0.28, 1.3], material: palette.stone, at: [2.1, 0.05, -0.6], cornerRadius: 0.12))
        let boat = Chapter01RealityPrimitives.box("iron-gates-boat", size: [2.4, 0.26, 0.95], material: palette.oldTimber, at: [-1.15, 0.14, 0.25], cornerRadius: 0.18)
        boat.orientation = simd_quatf(angle: -0.28, axis: [0, 1, 0])
        cell.addChild(boat)
        let line = Chapter01RealityPrimitives.cylinder(
            "action-landing-line", height: 3.6, radius: 0.04, material: palette.activeGold,
            at: [0.55, 0.72, 0.05], rotation: simd_quatf(angle: .pi / 2.35, axis: [0, 0, 1]), interactive: true
        )
        cell.addChild(line)
        let guidePole = Chapter01RealityPrimitives.cylinder(
            "guide-pole", height: 3.1, radius: 0.055, material: palette.timber,
            at: [1.2, 1.15, -0.2], rotation: simd_quatf(angle: 0.35, axis: [0, 0, 1])
        )
        cell.addChild(guidePole)
        cell.addChild(Chapter01RealityPrimitives.person("river-guide", at: [1.65, 0.12, -0.45], scale: 0.96, tunic: palette.clothLight, workingPose: 0.25))
        cell.addChild(Chapter01RealityPrimitives.person("arriving-worker", at: [-1.4, 0.24, 0.15], scale: 0.78, workingPose: 0.28))
        for index in 0 ..< 3 {
            cell.addChild(Chapter01RealityPrimitives.box(
                "river-house-\(index)", size: [1.25, 1.1, 1.05], material: palette.timber,
                at: [2.8 + Float(index) * 1.25, 0.55, -2.4 - Float(index % 2)]
            ))
        }
        for index in 0 ..< 4 {
            cell.addChild(Chapter01RealityPrimitives.cylinder(
                "net-stake-\(index)", height: 1.2, radius: 0.035, material: palette.rope,
                at: [Float(index) * 0.45 - 1.5, 0.42, -1.7]
            ))
        }
        return cell
    }

    private func updateIronGates(_ cell: Entity, progress: Float, transient: Float) {
        let response = min(progress + transient * 0.16, 1)
        if let boat = cell.findEntity(named: "iron-gates-boat") {
            boat.position.x = -1.15 + response * 2.7
            boat.position.z = 0.25 - response * 0.55
            boat.orientation = simd_quatf(angle: -0.28 + response * 0.31, axis: [0, 1, 0])
        }
        if let line = cell.findEntity(named: "action-landing-line") {
            line.orientation = simd_quatf(angle: .pi / 2.35 - response * 0.22, axis: [0, 0, 1])
        }
    }

    // MARK: Longhouse

    private func buildLonghouse() -> Entity {
        let cell = Entity()
        cell.name = Chapter01WorldCell.longhouseGround.rawValue
        cell.addChild(Chapter01RealityPrimitives.box("loess-ground", size: [18, 0.40, 18], material: palette.earth, at: [0, -0.25, -2]))
        let frame = Entity()
        frame.name = "longhouse-frame"
        frame.position = [0, 0, -1]
        for x: Float in [-1.65, 1.65] {
            for zIndex in 0 ..< 5 {
                let z = Float(zIndex) * -1.1 + 1.7
                let post = Chapter01RealityPrimitives.cylinder(
                    "action-posts", height: 2.8, radius: 0.11, material: palette.timber,
                    at: [x, 1.4, z], interactive: zIndex == 0 && x < 0
                )
                frame.addChild(post)
            }
        }
        for x: Float in [-1.65, 1.65] {
            let beam = Chapter01RealityPrimitives.cylinder(
                "roof-beam", height: 5.5, radius: 0.10, material: palette.timber,
                at: [x, 2.75, -0.5], rotation: simd_quatf(angle: .pi / 2, axis: [1, 0, 0])
            )
            frame.addChild(beam)
        }
        let hearth = Chapter01RealityPrimitives.hearth("action-hearth", at: [0, 0.02, 0.4])
        if let flame = hearth.findEntity(named: "action-hearth-flame") as? ModelEntity {
            Chapter01RealityPrimitives.makeInteractive(flame)
        }
        frame.addChild(hearth)
        frame.addChild(Chapter01RealityPrimitives.pot("action-storage", at: [0.85, 0.3, -1.0], scale: 1.2, interactive: true))
        let roof = Chapter01RealityPrimitives.box(
            "action-roof", size: [3.9, 0.18, 5.8], material: palette.straw,
            at: [0, 2.95, -0.6], interactive: true
        )
        roof.orientation = simd_quatf(angle: 0.10, axis: [0, 0, 1])
        frame.addChild(roof)
        cell.addChild(frame)
        cell.addChild(Chapter01RealityPrimitives.person("house-worker-a", at: [-2.0, 0, 0.5], scale: 1, workingPose: 0.42))
        cell.addChild(Chapter01RealityPrimitives.person("house-worker-b", at: [2.0, 0, -1.2], scale: 0.92, tunic: palette.clothLight, workingPose: 0.36))
        for index in 0 ..< 7 {
            let hole = Chapter01RealityPrimitives.cylinder(
                "posthole-\(index)", height: 0.035, radius: 0.13, material: palette.wetEarth,
                at: [Float(index % 2) * 3.3 - 1.65, 0.01, Float(index / 2) * -1.1 + 1.7]
            )
            cell.addChild(hole)
        }
        return cell
    }

    private func updateLonghouse(_ cell: Entity, progress: Float, transient: Float) {
        guard let frame = cell.findEntity(named: "longhouse-frame") else { return }
        let response = min(progress + transient * 0.14, 1)
        frame.position.y = -1.55 + response * 1.55
        frame.orientation = simd_quatf(angle: (1 - response) * -0.20, axis: [0, 0, 1])
        if let roof = frame.findEntity(named: "action-roof") {
            roof.isEnabled = response > 0.70
            roof.position.y = 2.55 + max(0, response - 0.7) * 1.35
        }
        frame.findEntity(named: "action-hearth")?.isEnabled = response > 0.30
        frame.findEntity(named: "action-storage")?.isEnabled = response > 0.48
    }

    // MARK: Settlement landscape and finale

    private func buildSettlementLandscape() -> Entity {
        let cell = Entity()
        cell.name = Chapter01WorldCell.settlementLandscape.rawValue
        cell.addChild(Chapter01RealityPrimitives.box("valley-ground", size: [28, 0.55, 28], material: palette.earth, at: [0, -0.34, -4]))
        let water = Chapter01RealityPrimitives.box("valley-water", size: [3.2, 0.05, 18], material: palette.water, at: [-3.6, -0.02, -3])
        water.orientation = simd_quatf(angle: -0.18, axis: [0, 1, 0])
        cell.addChild(water)
        let route = Chapter01RealityPrimitives.box(
            "action-herd-route", size: [1.15, 0.05, 7.4], material: palette.activeGold,
            at: [0.5, 0.015, -1.4], cornerRadius: 0.14, interactive: true
        )
        route.orientation = simd_quatf(angle: -0.20, axis: [0, 1, 0])
        cell.addChild(route)

        let herd = Entity()
        herd.name = "moving-herd"
        for index in 0 ..< 5 {
            herd.addChild(Chapter01RealityPrimitives.cattle(
                "herd-\(index)", at: [Float(index % 3) * 0.9, 0, Float(index / 3) * 0.8], scale: 0.62 + Float(index % 2) * 0.08
            ))
        }
        herd.position = [1.2, 0, 1.6]
        cell.addChild(herd)
        cell.addChild(Chapter01RealityPrimitives.person("herd-worker", at: [2.3, 0, 1.7], scale: 0.96, workingPose: 0.24))

        let daughter = Entity()
        daughter.name = "daughter-settlement"
        daughter.position = [2.4, 0, -4.2]
        for index in 0 ..< 4 {
            daughter.addChild(Chapter01RealityPrimitives.box(
                "daughter-house-\(index)", size: [1.2, 0.95, 1.6], material: palette.timber,
                at: [Float(index % 2) * 1.6, 0.48, Float(index / 2) * -2.0]
            ))
        }
        daughter.addChild(Chapter01RealityPrimitives.hearth("daughter-hearth", at: [0.8, 0, -0.9]))
        daughter.scale = .one * 0.35
        cell.addChild(daughter)

        let field = Entity()
        field.name = "daughter-field"
        field.position = [-0.4, 0, -4.7]
        for index in 0 ..< 48 {
            field.addChild(Chapter01RealityPrimitives.cylinder(
                "field-stalk", height: 0.30, radius: 0.012, material: palette.field,
                at: [Float(index % 8) * 0.28, 0.15, Float(index / 8) * -0.27]
            ))
        }
        field.scale = .one * 0.1
        cell.addChild(field)

        let gate = Chapter01RealityPrimitives.box(
            "action-final-gate", size: [2.8, 0.18, 0.23], material: palette.activeGold,
            at: [0.15, 0.78, -1.7], cornerRadius: 0.06, interactive: true
        )
        gate.orientation = simd_quatf(angle: -0.55, axis: [0, 1, 0])
        cell.addChild(gate)
        for x: Float in [-1.35, 1.65] {
            cell.addChild(Chapter01RealityPrimitives.cylinder("gate-post", height: 1.8, radius: 0.12, material: palette.timber, at: [x, 0.9, -1.7]))
        }

        for index in 0 ..< 10 {
            let trace = Chapter01RealityPrimitives.box(
                "farming-trace-\(index)", size: [0.6, 0.04, 1.9], material: index % 2 == 0 ? palette.field : palette.spring,
                at: [Float(index % 5) * 2.3 - 4.6, 0.01, Float(index / 5) * -6.0 - 6.2]
            )
            trace.scale = .one * 0.08
            cell.addChild(trace)
        }
        return cell
    }

    private func updateSettlement(
        _ cell: Entity,
        controller: Chapter01ExperienceController,
        progress: Float,
        transient: Float
    ) {
        let response = min(progress + transient * 0.14, 1)
        if controller.currentSequence == .moreMouthsMoreLand {
            if let herd = cell.findEntity(named: "moving-herd") {
                herd.position = [1.2 - response * 4.0, 0, 1.6 - response * 5.5]
            }
            if let daughter = cell.findEntity(named: "daughter-settlement") {
                daughter.scale = .one * (0.35 + response * 0.65)
            }
            if let field = cell.findEntity(named: "daughter-field") {
                field.scale = .one * (0.1 + response * 0.9)
            }
            cell.findEntity(named: "action-final-gate")?.isEnabled = false
            cell.findEntity(named: "action-herd-route")?.isEnabled = true
        } else {
            cell.findEntity(named: "action-final-gate")?.isEnabled = true
            cell.findEntity(named: "action-herd-route")?.isEnabled = false
            if let gate = cell.findEntity(named: "action-final-gate") {
                gate.orientation = simd_quatf(angle: -0.55 + response * 0.55, axis: [0, 1, 0])
                gate.position.y = 0.78 + transient * 0.12
            }
            for index in 0 ..< 10 {
                if let trace = cell.findEntity(named: "farming-trace-\(index)") {
                    let threshold = Float(index + 1) / 10
                    let revealed = min(max((response - threshold + 0.2) * 5, 0), 1)
                    trace.scale = .one * max(0.08, revealed)
                }
            }
        }
    }
}

private extension Entity {
    func visit(_ body: (Entity) -> Void) {
        body(self)
        children.forEach { $0.visit(body) }
    }
}
