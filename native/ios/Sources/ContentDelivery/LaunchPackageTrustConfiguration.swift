import ContentKit
import CryptoKit
import Foundation

public enum LaunchPackageTrustConfigurationError: Error, Equatable, Sendable {
    case malformedDocument
    case nonCanonicalDocument
    case unsupportedSchemaVersion(Int)
    case emptyKeySet
    case invalidKeyIdentifier(String)
    case duplicateKeyIdentifier(String)
    case invalidPublicKeyEncoding(String)
    case unexpectedField(String)
}

/// Shipping trust roots for signed launch packages. Only public P-256 keys are
/// accepted; private material has no representable field in this schema.
public struct LaunchPackageTrustConfiguration: Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let trustedPublicKeys: [String: Data]

    public init(data: Data) throws {
        let document: TrustDocument
        do {
            let object = try JSONSerialization.jsonObject(with: data)
            try Self.validateFields(in: object)
            let canonical = try JSONSerialization.data(
                withJSONObject: object,
                options: [.sortedKeys, .withoutEscapingSlashes]
            )
            guard canonical == data else {
                throw LaunchPackageTrustConfigurationError.nonCanonicalDocument
            }
            document = try JSONDecoder().decode(TrustDocument.self, from: data)
        } catch let error as LaunchPackageTrustConfigurationError {
            throw error
        } catch {
            throw LaunchPackageTrustConfigurationError.malformedDocument
        }

        guard document.schemaVersion == Self.currentSchemaVersion else {
            throw LaunchPackageTrustConfigurationError.unsupportedSchemaVersion(
                document.schemaVersion
            )
        }
        guard !document.keys.isEmpty else {
            throw LaunchPackageTrustConfigurationError.emptyKeySet
        }

        var publicKeys: [String: Data] = [:]
        for record in document.keys {
            guard Self.isStableKeyIdentifier(record.id) else {
                throw LaunchPackageTrustConfigurationError.invalidKeyIdentifier(record.id)
            }
            guard publicKeys[record.id] == nil else {
                throw LaunchPackageTrustConfigurationError.duplicateKeyIdentifier(record.id)
            }
            guard let bytes = Data(base64Encoded: record.x963PublicKeyBase64),
                  bytes.count == 65,
                  bytes.first == 0x04,
                  (try? P256.Signing.PublicKey(x963Representation: bytes)) != nil else {
                throw LaunchPackageTrustConfigurationError.invalidPublicKeyEncoding(record.id)
            }
            publicKeys[record.id] = bytes
        }

        schemaVersion = document.schemaVersion
        trustedPublicKeys = publicKeys
    }

    public func installationContext(
        supportedSchema: SchemaVersion = SchemaVersion(major: 1),
        runtimeVersion: SchemaVersion = SchemaVersion(major: 1)
    ) -> PackageInstallationContext {
        PackageInstallationContext(
            trustedPublicKeys: trustedPublicKeys,
            supportedSchema: supportedSchema,
            runtimeVersion: runtimeVersion,
            requireLatestVersion: true
        )
    }
}

private extension LaunchPackageTrustConfiguration {
    struct TrustDocument: Decodable {
        let schemaVersion: Int
        let keys: [KeyRecord]
    }

    struct KeyRecord: Decodable {
        let id: String
        let x963PublicKeyBase64: String
    }

    static func validateFields(in object: Any) throws {
        guard let root = object as? [String: Any] else {
            throw LaunchPackageTrustConfigurationError.malformedDocument
        }
        let rootFields = Set(root.keys)
        let allowedRootFields: Set<String> = ["schemaVersion", "keys"]
        if let unexpected = rootFields.subtracting(allowedRootFields).sorted().first {
            throw LaunchPackageTrustConfigurationError.unexpectedField(unexpected)
        }
        guard let keys = root["keys"] as? [[String: Any]] else {
            throw LaunchPackageTrustConfigurationError.malformedDocument
        }
        let allowedKeyFields: Set<String> = ["id", "x963PublicKeyBase64"]
        for key in keys {
            if let unexpected = Set(key.keys).subtracting(allowedKeyFields).sorted().first {
                throw LaunchPackageTrustConfigurationError.unexpectedField(unexpected)
            }
        }
    }

    static func isStableKeyIdentifier(_ value: String) -> Bool {
        guard !value.isEmpty, value.utf8.count <= 64,
              let first = value.utf8.first, (97 ... 122).contains(first),
              let last = value.utf8.last,
              (97 ... 122).contains(last) || (48 ... 57).contains(last) else {
            return false
        }
        var priorWasHyphen = false
        for byte in value.utf8 {
            if byte == 45 {
                if priorWasHyphen { return false }
                priorWasHyphen = true
            } else if (97 ... 122).contains(byte) || (48 ... 57).contains(byte) {
                priorWasHyphen = false
            } else {
                return false
            }
        }
        let forbiddenComponents: Set<Substring> = [
            "debug", "development", "fixture", "local", "test",
        ]
        return forbiddenComponents.isDisjoint(with: value.split(separator: "-"))
    }
}
