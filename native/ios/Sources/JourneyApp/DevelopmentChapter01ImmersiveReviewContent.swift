#if DEBUG || NON_SHIPPING_LIVE_TEST
import ContentKit
import Foundation
import ImmersiveRuntime

@MainActor
enum DevelopmentChapter01ImmersiveReviewContent {
    struct Resources {
        let runtimePackageContext: Chapter01RuntimePackageContext
        let sensoryCatalog: Chapter01AuthoredSampleCatalog
        let sensoryResolver: Chapter01OfflineSampleResolver
        let manifestDigest: String
        let storageURL: URL?
    }

    struct TrustReceipt: Decodable {
        let packageID: String
        let keyID: String
        let manifestDigest: String
        let shippingState: String
        let trustedPublicKeyX963Base64: String
    }

    enum Failure: Error {
        case missingPackage
        case missingTrustReceipt
        case invalidTrustReceipt
        case shippingReviewKey
        case manifestDigestMismatch
        case resumePreparationFailed
    }

    static let result: Result<Resources, Error> = Result {
        try makeResources()
    }

    private static func makeResources() throws -> Resources {
        guard let packageRoot = Bundle.main.url(
            forResource: "first-farmers-3d-review-v1",
            withExtension: "runtimefixture"
        ) else {
            throw Failure.missingPackage
        }
        guard let receiptURL = Bundle.main.url(
            forResource: "review-trust-receipt",
            withExtension: "json"
        ) else {
            throw Failure.missingTrustReceipt
        }
        let receipt = try JSONDecoder().decode(
            TrustReceipt.self,
            from: Data(contentsOf: receiptURL)
        )
        guard receipt.packageID == Chapter01ExperienceScript.packageID,
              let publicKey = Data(
                  base64Encoded: receipt.trustedPublicKeyX963Base64
              ) else {
            throw Failure.invalidTrustReceipt
        }
        guard receipt.shippingState == "PROHIBITED" else {
            throw Failure.shippingReviewKey
        }

        let expectedPackage = ContentPackageSpec(
            id: PackageID(Chapter01ExperienceScript.packageID),
            version: SchemaVersion(major: 1),
            chapterIDs: [ChapterID("first-farmers")],
            maximumInstalledBytes: 200_000_000,
            minimumRuntime: SchemaVersion(major: 2),
            isEssentialInstall: false
        )
        let verified = try ContentPackageVerifier
            .admitImmersiveV2PackageAtRuntime(
                at: packageRoot,
                expectedPackage: expectedPackage,
                trustedPublicKeys: [receipt.keyID: publicKey],
                supportedSchema: SchemaVersion(major: 2),
                runtimeVersion: SchemaVersion(major: 2)
            )
        guard verified.manifest.manifestDigest == receipt.manifestDigest else {
            throw Failure.manifestDigestMismatch
        }

        let runtimePackageContext = try Chapter01RuntimePackageContext(
            verifiedPackage: verified,
            openEdgeResolver: { path in
                try ContentPackageVerifier.verifyImmersiveV2Asset(
                    path: path,
                    in: verified,
                    packageRoot: packageRoot
                )
            }
        )

        let declaredAudioPaths = Set(
            verified.payload.assets
                .filter { $0.kind == .audio }
                .map(\.path)
        )
        let resolver = try Chapter01OfflineSampleResolver(
            packageRootURL: packageRoot,
            declaredPaths: declaredAudioPaths,
            authoritativeResolver: { path in
                try ContentPackageVerifier.verifyImmersiveV2Asset(
                    path: path,
                    in: verified,
                    packageRoot: packageRoot
                )
            }
        )
        let catalog = try Chapter01AuthoredSampleCatalog(
            bindings: Chapter01Sequence.allCases.enumerated().flatMap {
                index, sequence in
                Chapter01SensoryEvent.allCases.map { event in
                    let family = event == .transition
                        ? "transition"
                        : "mechanism"
                    return Chapter01AuthoredSampleBinding(
                        sequence: sequence,
                        event: event,
                        packageRelativePath:
                            "immersive/first-farmers/audio/"
                            + "\(family)-\(String(format: "%02d", index + 1)).m4a",
                        gain: event == .resistance ? 0.82 : 0.72,
                        maximumDuration: event == .transition ? 3 : 1.4
                    )
                }
            }
        )
        return Resources(
            runtimePackageContext: runtimePackageContext,
            sensoryCatalog: catalog,
            sensoryResolver: resolver,
            manifestDigest: verified.manifest.manifestDigest,
            storageURL: try preparedReviewStorageURL()
        )
    }

    /// The editor can launch the same signed experience at the canonical
    /// opening or at the approved natural stop before spring sowing. The
    /// alternate entry is prepared entirely through the reducer and durable
    /// save path; it is never a renderer shortcut or a visible developer UI.
    private static func preparedReviewStorageURL() throws -> URL? {
        guard ProcessInfo.processInfo.arguments.contains(
            "--chapter01-immersive-review-resume-spring"
        ) else {
            return nil
        }

        let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
        let storageURL = applicationSupport
            .appendingPathComponent("chapter01-immersive-v2", isDirectory: true)
            .appendingPathComponent("state.json", isDirectory: false)
        let controller = Chapter01ExperienceController(storageURL: storageURL)
        guard controller.prepareNonShippingSpringResume() else {
            throw Failure.resumePreparationFailed
        }
        return storageURL
    }
}
#endif
