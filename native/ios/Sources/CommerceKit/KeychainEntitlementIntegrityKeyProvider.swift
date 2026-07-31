#if canImport(Security)
import Foundation
import Security

public enum EntitlementIntegrityKeyError: Error, Equatable, Sendable {
    case keychain(OSStatus)
    case invalidStoredKey
    case randomGeneration(OSStatus)
}

/// Device-local secret for authenticating the offline entitlement cache. The
/// identifier is intentionally independent of the public franchise and work
/// title, and the key never enters the snapshot files.
public struct KeychainEntitlementIntegrityKeyProvider: EntitlementIntegrityKeyProviding {
    private let service: String
    private let account: String

    public init(
        service: String = "com.thelongwest.journey.entitlement-integrity",
        account: String = "launch-complete-work-v1"
    ) {
        self.service = service
        self.account = account
    }

    public func loadOrCreateKey() throws -> Data {
        if let existing = try readKey() {
            guard existing.count == 32 else {
                throw EntitlementIntegrityKeyError.invalidStoredKey
            }
            return existing
        }

        var bytes = [UInt8](repeating: 0, count: 32)
        let randomStatus = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        guard randomStatus == errSecSuccess else {
            throw EntitlementIntegrityKeyError.randomGeneration(randomStatus)
        }
        let key = Data(bytes)
        let addQuery: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecValueData: key,
        ]
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        if addStatus == errSecDuplicateItem, let racedKey = try readKey() {
            guard racedKey.count == 32 else {
                throw EntitlementIntegrityKeyError.invalidStoredKey
            }
            return racedKey
        }
        guard addStatus == errSecSuccess else {
            throw EntitlementIntegrityKeyError.keychain(addStatus)
        }
        return key
    }

    private func readKey() throws -> Data? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else {
            throw EntitlementIntegrityKeyError.keychain(status)
        }
        guard let data = result as? Data else {
            throw EntitlementIntegrityKeyError.invalidStoredKey
        }
        return data
    }
}
#endif
