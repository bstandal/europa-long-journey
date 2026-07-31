import Foundation
import RealityKit

enum VerificationFailure: Error, CustomStringConvertible {
    case usage
    case missingEntity(String)
    case missingModelComponent(String)
    case wrongMaterialCount(String, Int)
    case wrongMaterialType(String, String)

    var description: String {
        switch self {
        case .usage:
            return "usage: verify_material_carrier.swift <chapter01-material-carrier-v1.usdz>"
        case let .missingEntity(name):
            return "RealityKit did not import expected swatch entity: \(name)"
        case let .missingModelComponent(name):
            return "RealityKit imported \(name) without a ModelComponent"
        case let .wrongMaterialCount(name, count):
            return "RealityKit imported \(name) with \(count) materials; expected exactly one"
        case let .wrongMaterialType(name, type):
            return "RealityKit imported \(name) with \(type); expected PhysicallyBasedMaterial"
        }
    }
}

let expectedSwatches = [
    "Swatch_Soil",
    "Swatch_DarkRock",
    "Swatch_Timber",
    "Swatch_ClothNeutral",
    "Swatch_Thatch",
]

do {
    guard CommandLine.arguments.count == 2 else {
        throw VerificationFailure.usage
    }
    let url = URL(fileURLWithPath: CommandLine.arguments[1]).standardizedFileURL
    let root = try Entity.load(contentsOf: url)
    for name in expectedSwatches {
        guard let entity = root.findEntity(named: name) else {
            throw VerificationFailure.missingEntity(name)
        }
        guard let model = entity.components[ModelComponent.self] else {
            throw VerificationFailure.missingModelComponent(name)
        }
        guard model.materials.count == 1 else {
            throw VerificationFailure.wrongMaterialCount(name, model.materials.count)
        }
        guard model.materials[0] is PhysicallyBasedMaterial else {
            throw VerificationFailure.wrongMaterialType(
                name,
                String(describing: type(of: model.materials[0]))
            )
        }
    }
    print("PASS RealityKit offline import: \(expectedSwatches.count) material swatches")
} catch {
    fputs("FAIL: \(error)\n", stderr)
    exit(1)
}
