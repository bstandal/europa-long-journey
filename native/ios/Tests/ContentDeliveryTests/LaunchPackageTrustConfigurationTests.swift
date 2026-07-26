@testable import ContentDelivery
import CryptoKit
import Foundation
import XCTest

final class LaunchPackageTrustConfigurationTests: XCTestCase {
    func testAcceptsOnlyPinnedP256PublicKeysAndBuildsLatestRequiredContext() throws {
        let first = P256.Signing.PrivateKey().publicKey.x963Representation
        let second = P256.Signing.PrivateKey().publicKey.x963Representation
        let configuration = try LaunchPackageTrustConfiguration(data: try document(keys: [
            ("launch-2026-a", first),
            ("launch-2027-b", second),
        ]))

        XCTAssertEqual(configuration.schemaVersion, 1)
        XCTAssertEqual(configuration.trustedPublicKeys, [
            "launch-2026-a": first,
            "launch-2027-b": second,
        ])
        let context = configuration.installationContext()
        XCTAssertEqual(context.trustedPublicKeys, configuration.trustedPublicKeys)
        XCTAssertEqual(context.supportedSchema, .init(major: 1))
        XCTAssertEqual(context.runtimeVersion, .init(major: 1))
        XCTAssertTrue(context.requireLatestVersion)
    }

    func testRejectsEmptyDuplicateUnstableAndInvalidKeyRecords() throws {
        let valid = P256.Signing.PrivateKey().publicKey.x963Representation
        let cases: [(Data, LaunchPackageTrustConfigurationError)] = [
            (try document(keys: []), .emptyKeySet),
            (
                try document(keys: [("launch-key", valid), ("launch-key", valid)]),
                .duplicateKeyIdentifier("launch-key")
            ),
            (
                try document(keys: [("Development_Key", valid)]),
                .invalidKeyIdentifier("Development_Key")
            ),
            (
                try document(keys: [("launch-test-key", valid)]),
                .invalidKeyIdentifier("launch-test-key")
            ),
            (
                try document(keys: [("launch-key", Data(repeating: 0, count: 65))]),
                .invalidPublicKeyEncoding("launch-key")
            ),
        ]

        for (bytes, expected) in cases {
            XCTAssertThrowsError(try LaunchPackageTrustConfiguration(data: bytes)) {
                XCTAssertEqual($0 as? LaunchPackageTrustConfigurationError, expected)
            }
        }
    }

    func testRejectsPrivateMaterialAndEveryUnknownFieldBeforeDecoding() throws {
        let privateKey = P256.Signing.PrivateKey()
        let object: [String: Any] = [
            "schemaVersion": 1,
            "keys": [[
                "id": "launch-key",
                "x963PublicKeyBase64": privateKey.publicKey.x963Representation.base64EncodedString(),
                "privateKeyBase64": privateKey.rawRepresentation.base64EncodedString(),
            ]],
        ]
        let bytes = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])

        XCTAssertThrowsError(try LaunchPackageTrustConfiguration(data: bytes)) {
            XCTAssertEqual(
                $0 as? LaunchPackageTrustConfigurationError,
                .unexpectedField("privateKeyBase64")
            )
        }
    }

    func testRejectsUnknownRootFieldFutureSchemaAndMalformedDocument() throws {
        let publicKey = P256.Signing.PrivateKey().publicKey.x963Representation
        let unknownRoot = try JSONSerialization.data(withJSONObject: [
            "schemaVersion": 1,
            "keys": [[
                "id": "launch-key",
                "x963PublicKeyBase64": publicKey.base64EncodedString(),
            ]],
            "privateKeys": [],
        ], options: [.sortedKeys, .withoutEscapingSlashes])
        XCTAssertThrowsError(try LaunchPackageTrustConfiguration(data: unknownRoot)) {
            XCTAssertEqual(
                $0 as? LaunchPackageTrustConfigurationError,
                .unexpectedField("privateKeys")
            )
        }

        let future = try JSONSerialization.data(withJSONObject: [
            "schemaVersion": 2,
            "keys": [[
                "id": "launch-key",
                "x963PublicKeyBase64": publicKey.base64EncodedString(),
            ]],
        ], options: [.sortedKeys, .withoutEscapingSlashes])
        XCTAssertThrowsError(try LaunchPackageTrustConfiguration(data: future)) {
            XCTAssertEqual(
                $0 as? LaunchPackageTrustConfigurationError,
                .unsupportedSchemaVersion(2)
            )
        }

        XCTAssertThrowsError(
            try LaunchPackageTrustConfiguration(data: Data("not-json".utf8))
        ) {
            XCTAssertEqual(
                $0 as? LaunchPackageTrustConfigurationError,
                .malformedDocument
            )
        }
    }

    func testRejectsDuplicateMembersAndAnyNoncanonicalSerialization() throws {
        let publicKey = P256.Signing.PrivateKey().publicKey.x963Representation
        let base64 = publicKey.base64EncodedString()
        let duplicate = Data(
            "{\"keys\":[{\"id\":\"launch-key\",\"x963PublicKeyBase64\":\"\(base64)\"}],\"schemaVersion\":1,\"schemaVersion\":1}"
                .utf8
        )
        XCTAssertThrowsError(try LaunchPackageTrustConfiguration(data: duplicate)) {
            XCTAssertEqual(
                $0 as? LaunchPackageTrustConfigurationError,
                .nonCanonicalDocument
            )
        }

        let canonical = try document(keys: [("launch-key", publicKey)])
        XCTAssertThrowsError(
            try LaunchPackageTrustConfiguration(data: canonical + Data("\n".utf8))
        ) {
            XCTAssertEqual(
                $0 as? LaunchPackageTrustConfigurationError,
                .nonCanonicalDocument
            )
        }
    }

    private func document(keys: [(String, Data)]) throws -> Data {
        try JSONSerialization.data(withJSONObject: [
            "schemaVersion": 1,
            "keys": keys.map { id, bytes in
                [
                    "id": id,
                    "x963PublicKeyBase64": bytes.base64EncodedString(),
                ]
            },
        ], options: [.sortedKeys, .withoutEscapingSlashes])
    }
}
