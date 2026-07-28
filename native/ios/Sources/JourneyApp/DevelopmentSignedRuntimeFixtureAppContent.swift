#if DEBUG || NON_SHIPPING_LIVE_TEST
import ContentDelivery
import ContentKit
import CryptoKit
import Foundation
import JourneyContent

enum DevelopmentSignedRuntimeFixtureError: Error, Equatable {
    case missingPackage
    case missingTrustReceipt
    case malformedTrustReceipt
    case trustBoundaryMismatch
    case manifestDigestMismatch
    case targetBeatUnavailable
}

enum DevelopmentSignedRuntimeFixtureAppContent {
    static let launchArgument = "--ui-testing-signed-runtime-fixture"
    static let chapterArgumentPrefix =
        "--ui-testing-signed-runtime-fixture-chapter="
    static let beatArgumentPrefix =
        "--ui-testing-signed-runtime-fixture-beat="
    static let legacyCompletedWithoutReviewArgument =
        "--ui-testing-legacy-completed-without-review"
    static let worldReadyArgument =
        "--ui-testing-signed-runtime-fixture-world-ready"

    /// The signed review package is the complete content authority for the
    /// dedicated live-test product. Debug builds retain the explicit launch
    /// argument so ordinary development runs cannot enter the fixture by
    /// accident.
    static var isActive: Bool {
#if NON_SHIPPING_LIVE_TEST
        true
#else
        ProcessInfo.processInfo.arguments.contains(launchArgument)
#endif
    }

    static var usesLegacyCompletedWithoutReviewState: Bool {
        isActive && ProcessInfo.processInfo.arguments.contains(
            legacyCompletedWithoutReviewArgument
        )
    }

    static var usesWorldReadyState: Bool {
        isActive && ProcessInfo.processInfo.arguments.contains(
            worldReadyArgument
        )
    }

    private static let packageID = PackageID("vertical-slice-development-v1")
    private static let keyID = "vertical-slice-development-key-v1"
    private static let trustDomain = "the-long-west-vertical-slice-development-v1"
    private static let receiptKind =
        "long-west-vertical-slice-development-receipt-v1"
    private static let projectionAuthorityKind =
        "DEVELOPMENT_BLUEPRINT_PROJECTION_AUTHORITY"
    private static let projectionAuthorityStatus =
        "CODEX_PROVISIONAL_NON_SHIPPING_BLUEPRINT_PROJECTION"
    private static let shippingState = "PROHIBITED"
    private static let packageResourceName = "vertical-slice-development-v1"
    private static let packageResourceExtension = "runtimefixture"
    private static let trustResourceName =
        "vertical-slice-development-trust-receipt"
    private static let version = SchemaVersion(major: 1)
    private static let chapterIDs = [
        ChapterID("first-farmers"),
        ChapterID("europe-holds-the-line"),
        ChapterID("european-world"),
    ]

    private struct TrustReceipt: Decodable {
        let schemaVersion: Int
        let kind: String
        let trustDomain: String
        let packageID: PackageID
        let keyID: String
        let manifestDigest: String
        let projectionSHA256: String
        let projectionAuthorityKind: String
        let projectionAuthorityStatus: String
        let shippingState: String
        let projectionAuthoritySHA256: String
        let trustedPublicKeyX963Base64: String
        let trustedPublicKeySPKIBase64: String
    }

    static func makeClient(bundle: Bundle = .main) throws -> JourneyContentClient {
        guard let packageRoot = bundle.url(
            forResource: packageResourceName,
            withExtension: packageResourceExtension
        ) else {
            throw DevelopmentSignedRuntimeFixtureError.missingPackage
        }
        guard let trustURL = bundle.url(
            forResource: trustResourceName,
            withExtension: "json"
        ) else {
            throw DevelopmentSignedRuntimeFixtureError.missingTrustReceipt
        }
        let receiptData = try Data(contentsOf: trustURL)
        let receipt = try decodeTrustReceipt(receiptData)
        let expectedPackage = ContentPackageSpec(
            id: packageID,
            version: version,
            chapterIDs: chapterIDs,
            maximumInstalledBytes: 750_000_000,
            minimumRuntime: version,
            isEssentialInstall: true
        )
        let verified = try ContentPackageVerifier.admitPackageAtRuntime(
            at: packageRoot,
            expectedPackage: expectedPackage,
            trustedPublicKeys: [keyID: receipt.trustedPublicKeyData],
            supportedSchema: version,
            runtimeVersion: version
        )
        guard verified.manifest.manifestDigest == receipt.document.manifestDigest else {
            throw DevelopmentSignedRuntimeFixtureError.manifestDigestMismatch
        }
        let repository = try ContentRepository(
            developmentVerticalSlice: verified
        )
        let generation = InstalledPackageGeneration(
            generationID: "vertical-slice-bundled-generation-v1",
            packageID: packageID,
            packageVersion: version,
            manifestDigest: verified.manifest.manifestDigest,
            relativePath: "vertical-slice-development-v1.runtimefixture",
            activationSequence: 1
        )
        let index = InstalledPackageIndex(
            nextActivationSequence: 2,
            generations: [generation],
            activeGenerationByPackage: [packageID: generation.generationID]
        )
        let snapshot = VerifiedJourneyContentSnapshot(
            revision: 1,
            repository: repository,
            reconciledInstalledIndex: index,
            packageRootURLs: [packageID: packageRoot.standardizedFileURL],
            verifiedPackagesByID: [packageID: verified]
        )
        return JourneyContentClient(
            initialSnapshot: snapshot,
            snapshot: { snapshot },
            snapshotUpdates: {
                AsyncStream { continuation in
                    continuation.yield(snapshot)
                    continuation.finish()
                }
            },
            reportAssetFailure: { _, _ in .ignoredDurableAuthority },
            revertSaveMigrationAuthorityChange: { _, _, _ in nil }
        )
    }

    static func targetChapterID(
        arguments: [String] = ProcessInfo.processInfo.arguments
    ) -> ChapterID {
        guard let value = arguments.first(where: {
            $0.hasPrefix(chapterArgumentPrefix)
        })?.dropFirst(chapterArgumentPrefix.count) else {
            return chapterIDs[0]
        }
        let requested = ChapterID(String(value))
        return chapterIDs.contains(requested) ? requested : chapterIDs[0]
    }

    static func targetBeatID(
        arguments: [String] = ProcessInfo.processInfo.arguments
    ) -> BeatID? {
        guard let value = arguments.first(where: {
            $0.hasPrefix(beatArgumentPrefix)
        })?.dropFirst(beatArgumentPrefix.count), !value.isEmpty else {
            return nil
        }
        return BeatID(String(value))
    }

    private struct VerifiedReceipt {
        let document: TrustReceipt
        let trustedPublicKeyData: Data
    }

    private static func decodeTrustReceipt(_ data: Data) throws -> VerifiedReceipt {
        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw DevelopmentSignedRuntimeFixtureError.malformedTrustReceipt
        }
        let requiredFields: Set<String> = [
            "schemaVersion", "kind", "trustDomain", "packageID", "keyID",
            "manifestDigest", "projectionSHA256",
            "projectionAuthorityKind", "projectionAuthorityStatus",
            "shippingState", "projectionAuthoritySHA256",
            "trustedPublicKeyX963Base64", "trustedPublicKeySPKIBase64",
        ]
        guard let dictionary = object as? [String: Any],
              Set(dictionary.keys) == requiredFields,
              let receipt = try? JSONDecoder().decode(TrustReceipt.self, from: data),
              receipt.schemaVersion == 1,
              receipt.kind == receiptKind,
              receipt.trustDomain == trustDomain,
              receipt.packageID == packageID,
              receipt.keyID == keyID,
              receipt.projectionAuthorityKind == projectionAuthorityKind,
              receipt.projectionAuthorityStatus == projectionAuthorityStatus,
              receipt.shippingState == shippingState,
              isSHA256(receipt.manifestDigest),
              isSHA256(receipt.projectionSHA256),
              isSHA256(receipt.projectionAuthoritySHA256),
              let x963 = Data(base64Encoded: receipt.trustedPublicKeyX963Base64),
              let spki = Data(base64Encoded: receipt.trustedPublicKeySPKIBase64),
              let x963Key = try? P256.Signing.PublicKey(x963Representation: x963),
              let spkiKey = try? P256.Signing.PublicKey(derRepresentation: spki),
              x963Key.x963Representation == spkiKey.x963Representation else {
            throw DevelopmentSignedRuntimeFixtureError.trustBoundaryMismatch
        }
        return VerifiedReceipt(document: receipt, trustedPublicKeyData: x963)
    }

    private static func isSHA256(_ value: String) -> Bool {
        value.utf8.count == 64 && value.utf8.allSatisfy {
            ($0 >= 48 && $0 <= 57) || ($0 >= 97 && $0 <= 102)
        }
    }
}
#endif
