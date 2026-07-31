import ContentKit
import Foundation
import ImmersiveRuntime

private struct IntegrityInventory: Decodable {
    let assets: [Asset]

    struct Asset: Decodable {
        let path: String
        let sha256: String
        let byteCount: Int64
    }
}

private enum CompilerFailure: Error, CustomStringConvertible {
    case usage
    case duplicateAssetPath(String)
    case incompleteInventory(missing: [String], unexpected: [String])

    var description: String {
        switch self {
        case .usage:
            "usage: immersive-review-payload-compiler <asset-integrity.json> <payload.json>"
        case let .duplicateAssetPath(path):
            "asset-integrity.json contains duplicate path: \(path)"
        case let .incompleteInventory(missing, unexpected):
            "asset inventory does not match Chapter 01 V2 authority; missing=\(missing), unexpected=\(unexpected)"
        }
    }
}

@main
private enum ImmersiveReviewPayloadCompiler {
    static func main() throws {
        guard CommandLine.arguments.count == 3 else { throw CompilerFailure.usage }
        let inventoryURL = URL(fileURLWithPath: CommandLine.arguments[1])
        let outputURL = URL(fileURLWithPath: CommandLine.arguments[2])
        let inventory = try JSONDecoder().decode(
            IntegrityInventory.self,
            from: Data(contentsOf: inventoryURL, options: [.mappedIfSafe])
        )

        var integrityByPath: [String: Chapter01ImmersiveAssetIntegrity] = [:]
        for asset in inventory.assets {
            guard integrityByPath[asset.path] == nil else {
                throw CompilerFailure.duplicateAssetPath(asset.path)
            }
            integrityByPath[asset.path] = Chapter01ImmersiveAssetIntegrity(
                sha256: asset.sha256,
                byteCount: asset.byteCount
            )
        }

        let required = Set(Chapter01ImmersivePayloadFactory.requiredAssetPaths)
        let supplied = Set(integrityByPath.keys)
        guard required == supplied else {
            throw CompilerFailure.incompleteInventory(
                missing: required.subtracting(supplied).sorted(),
                unexpected: supplied.subtracting(required).sorted()
            )
        }

        let payload = try Chapter01ImmersivePayloadFactory.make(
            assetIntegrityByPath: integrityByPath
        )
        let data = try ImmersiveContentDocumentV2.encode(payload)
        try FileManager.default.createDirectory(
            at: outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: outputURL, options: .atomic)
    }
}
