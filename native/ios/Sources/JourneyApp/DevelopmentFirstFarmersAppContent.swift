#if DEBUG
import Foundation
import JourneyContent

enum DevelopmentFirstFarmersAppContent {
    static let payloadResource = "first-farmers.content-package"
    static let receiptResource = "first-farmers.payload-receipt"

    static func load(
        bundle: Bundle = .main,
        arguments: [String] = ProcessInfo.processInfo.arguments
    ) throws -> DevelopmentFirstFarmersEnvelope {
        let payloadURL = bundle.url(forResource: payloadResource, withExtension: "json")
        let receiptURL = bundle.url(forResource: receiptResource, withExtension: "json")

        var payloadData: Data?
        if !arguments.contains("--ui-testing-missing-development-payload"),
           let payloadURL {
            payloadData = try Data(contentsOf: payloadURL)
        }
        if arguments.contains("--ui-testing-forged-development-payload"),
           var forged = payloadData,
           !forged.isEmpty {
            forged[forged.startIndex] ^= 0x01
            payloadData = forged
        }

        let receiptData: Data?
        if let receiptURL {
            receiptData = try Data(contentsOf: receiptURL)
        } else {
            receiptData = nil
        }
        return try DevelopmentFirstFarmersEnvelopeLoader.load(
            payloadData: payloadData,
            receiptData: receiptData,
            resourceRootURL: bundle.bundleURL
        )
    }
}
#endif
