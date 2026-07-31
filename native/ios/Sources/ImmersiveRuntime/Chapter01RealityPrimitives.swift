import RealityKit
import SwiftUI

#if os(iOS)
import UIKit
typealias Chapter01NativeColor = UIColor
#elseif os(macOS)
import AppKit
typealias Chapter01NativeColor = NSColor
#endif

@MainActor
enum Chapter01RealityPrimitives {
    @MainActor
    struct Palette {
        let charcoal = material(0.025, 0.030, 0.029, roughness: 0.93)
        let earth = material(0.19, 0.145, 0.09, roughness: 0.97)
        let wetEarth = material(0.085, 0.075, 0.055, roughness: 0.82)
        let water = material(0.035, 0.12, 0.135, alpha: 0.82, roughness: 0.22)
        let waterHighlight = material(0.10, 0.28, 0.28, alpha: 0.72, roughness: 0.18)
        let timber = material(0.26, 0.15, 0.075, roughness: 0.9)
        let oldTimber = material(0.115, 0.082, 0.052, roughness: 1)
        let rope = material(0.43, 0.31, 0.17, roughness: 0.94)
        let grain = material(0.76, 0.50, 0.19, roughness: 0.78)
        let grainDark = material(0.34, 0.20, 0.08, roughness: 0.94)
        let ceramic = material(0.42, 0.22, 0.12, roughness: 0.8)
        let clayLight = material(0.60, 0.34, 0.18, roughness: 0.83)
        let straw = material(0.50, 0.36, 0.14, roughness: 0.98)
        let field = material(0.30, 0.34, 0.10, roughness: 0.98)
        let spring = material(0.24, 0.45, 0.15, roughness: 0.95)
        let cloth = material(0.30, 0.18, 0.11, roughness: 1)
        let clothLight = material(0.47, 0.34, 0.22, roughness: 1)
        let skin = material(0.48, 0.28, 0.18, roughness: 0.86)
        let stone = material(0.27, 0.28, 0.25, roughness: 1)
        let fire = emissive(0.95, 0.33, 0.05, intensity: 2.2)
        let activeGold = emissive(0.78, 0.47, 0.14, intensity: 1.25)
        let grass = material(0.12, 0.24, 0.085, roughness: 1)
        let mist = material(0.31, 0.36, 0.34, alpha: 0.13, roughness: 1)
    }

    static let palette = Palette()

    static func material(
        _ red: CGFloat,
        _ green: CGFloat,
        _ blue: CGFloat,
        alpha: CGFloat = 1,
        roughness: Float,
        metallic: Bool = false
    ) -> SimpleMaterial {
        SimpleMaterial(
            color: Chapter01NativeColor(
                red: red,
                green: green,
                blue: blue,
                alpha: alpha
            ),
            roughness: .float(roughness),
            isMetallic: metallic
        )
    }

    static func emissive(
        _ red: CGFloat,
        _ green: CGFloat,
        _ blue: CGFloat,
        intensity: Float
    ) -> PhysicallyBasedMaterial {
        var result = PhysicallyBasedMaterial()
        result.baseColor = .init(tint: Chapter01NativeColor(
            red: red * 0.45,
            green: green * 0.45,
            blue: blue * 0.45,
            alpha: 1
        ))
        result.emissiveColor = .init(color: Chapter01NativeColor(
            red: red,
            green: green,
            blue: blue,
            alpha: 1
        ))
        result.emissiveIntensity = intensity
        result.roughness = .init(floatLiteral: 0.75)
        return result
    }

    static func box(
        _ name: String,
        size: SIMD3<Float>,
        material: any RealityKit.Material,
        at position: SIMD3<Float>,
        cornerRadius: Float = 0,
        interactive: Bool = false
    ) -> ModelEntity {
        let entity = ModelEntity(
            mesh: .generateBox(size: size, cornerRadius: cornerRadius),
            materials: [material]
        )
        entity.name = name
        entity.position = position
        if interactive { makeInteractive(entity) }
        return entity
    }

    static func sphere(
        _ name: String,
        radius: Float,
        material: any RealityKit.Material,
        at position: SIMD3<Float>,
        interactive: Bool = false
    ) -> ModelEntity {
        let entity = ModelEntity(
            mesh: .generateSphere(radius: radius),
            materials: [material]
        )
        entity.name = name
        entity.position = position
        if interactive { makeInteractive(entity) }
        return entity
    }

    static func cylinder(
        _ name: String,
        height: Float,
        radius: Float,
        material: any RealityKit.Material,
        at position: SIMD3<Float>,
        rotation: simd_quatf = simd_quatf(angle: 0, axis: [0, 1, 0]),
        interactive: Bool = false
    ) -> ModelEntity {
        let entity = ModelEntity(
            mesh: .generateCylinder(height: height, radius: radius),
            materials: [material]
        )
        entity.name = name
        entity.position = position
        entity.orientation = rotation
        if interactive { makeInteractive(entity) }
        return entity
    }

    static func cone(
        _ name: String,
        height: Float,
        radius: Float,
        material: any RealityKit.Material,
        at position: SIMD3<Float>
    ) -> ModelEntity {
        let entity = ModelEntity(
            mesh: .generateCone(height: height, radius: radius),
            materials: [material]
        )
        entity.name = name
        entity.position = position
        return entity
    }

    static func makeInteractive(_ entity: ModelEntity) {
        entity.components.set(InputTargetComponent(allowedInputTypes: .all))
        entity.generateCollisionShapes(recursive: false)
    }

    static func person(
        _ name: String,
        at position: SIMD3<Float>,
        scale: Float = 1,
        tunic: SimpleMaterial? = nil,
        workingPose: Float = 0
    ) -> Entity {
        let root = Entity()
        root.name = name
        root.position = position
        root.scale = .one * scale
        let clothing = tunic ?? palette.cloth

        root.addChild(sphere("\(name)-head", radius: 0.13, material: palette.skin, at: [0, 1.42, 0]))
        root.addChild(box("\(name)-body", size: [0.34, 0.62, 0.23], material: clothing, at: [0, 0.98, 0], cornerRadius: 0.06))
        root.addChild(cylinder("\(name)-left-leg", height: 0.58, radius: 0.065, material: palette.skin, at: [-0.10, 0.40, 0]))
        root.addChild(cylinder("\(name)-right-leg", height: 0.58, radius: 0.065, material: palette.skin, at: [0.10, 0.40, 0]))
        let armRotation = simd_quatf(angle: .pi / 2 + workingPose, axis: [1, 0, 0])
        root.addChild(cylinder("\(name)-left-arm", height: 0.48, radius: 0.052, material: palette.skin, at: [-0.25, 1.03, 0.10], rotation: armRotation))
        root.addChild(cylinder("\(name)-right-arm", height: 0.48, radius: 0.052, material: palette.skin, at: [0.25, 1.03, 0.10], rotation: armRotation))
        return root
    }

    static func cattle(
        _ name: String,
        at position: SIMD3<Float>,
        scale: Float = 1
    ) -> Entity {
        let root = Entity()
        root.name = name
        root.position = position
        root.scale = .one * scale
        root.addChild(box("\(name)-body", size: [0.80, 0.48, 0.34], material: palette.cloth, at: [0, 0.67, 0], cornerRadius: 0.14))
        root.addChild(box("\(name)-head", size: [0.34, 0.35, 0.30], material: palette.clothLight, at: [0.53, 0.75, 0], cornerRadius: 0.11))
        for x: Float in [-0.27, 0.27] {
            for z: Float in [-0.12, 0.12] {
                root.addChild(cylinder("\(name)-leg", height: 0.52, radius: 0.045, material: palette.cloth, at: [x, 0.30, z]))
            }
        }
        let hornRotation = simd_quatf(angle: .pi / 2, axis: [0, 0, 1])
        root.addChild(cone("\(name)-horn-a", height: 0.20, radius: 0.035, material: palette.stone, at: [0.58, 0.97, -0.14]))
        root.addChild(cone("\(name)-horn-b", height: 0.20, radius: 0.035, material: palette.stone, at: [0.58, 0.97, 0.14]))
        root.children.suffix(2).forEach { $0.orientation = hornRotation }
        return root
    }

    static func pot(
        _ name: String,
        at position: SIMD3<Float>,
        scale: Float = 1,
        interactive: Bool = false
    ) -> Entity {
        let root = Entity()
        root.name = name
        root.position = position
        root.scale = .one * scale
        let body = cylinder("\(name)-body", height: 0.48, radius: 0.24, material: palette.ceramic, at: SIMD3<Float>.zero, interactive: interactive)
        body.scale = [1, 1, 0.85]
        root.addChild(body)
        root.addChild(cylinder("\(name)-neck", height: 0.15, radius: 0.14, material: palette.clayLight, at: [0, 0.30, 0]))
        return root
    }

    static func hearth(_ name: String, at position: SIMD3<Float>) -> Entity {
        let root = Entity()
        root.name = name
        root.position = position
        for index in 0 ..< 8 {
            let angle = Float(index) * .pi / 4
            root.addChild(sphere(
                "\(name)-stone-\(index)",
                radius: 0.105,
                material: palette.stone,
                at: [cos(angle) * 0.28, 0.08, sin(angle) * 0.28]
            ))
        }
        root.addChild(cone("\(name)-flame", height: 0.40, radius: 0.15, material: palette.fire, at: [0, 0.28, 0]))
        return root
    }
}
