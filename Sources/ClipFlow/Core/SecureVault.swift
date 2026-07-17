import CryptoKit
import Foundation
import Security

enum SecureVaultError: LocalizedError {
    case keychain(OSStatus)
    case invalidKey
    case invalidCiphertext

    var errorDescription: String? {
        switch self {
        case .keychain(let status): return "Keychain operation failed (\(status))."
        case .invalidKey: return "The encryption key is invalid."
        case .invalidCiphertext: return "The encrypted clipboard data is invalid."
        }
    }
}

final class SecureVault {
    private let key: SymmetricKey

    init(service: String = "com.clipflow.local", account: String = "database-key") throws {
        if let existing = try Self.readKey(service: service, account: account) {
            guard existing.count == 32 else { throw SecureVaultError.invalidKey }
            key = SymmetricKey(data: existing)
            return
        }

        let newKey = SymmetricKey(size: .bits256)
        let data = newKey.withUnsafeBytes { Data($0) }
        try Self.storeKey(data, service: service, account: account)
        key = newKey
    }

    init(keyData: Data) throws {
        guard keyData.count == 32 else { throw SecureVaultError.invalidKey }
        key = SymmetricKey(data: keyData)
    }

    func seal(_ data: Data) throws -> Data {
        let box = try AES.GCM.seal(data, using: key)
        guard let combined = box.combined else { throw SecureVaultError.invalidCiphertext }
        return combined
    }

    func open(_ data: Data) throws -> Data {
        let box = try AES.GCM.SealedBox(combined: data)
        return try AES.GCM.open(box, using: key)
    }

    private static func readKey(service: String, account: String) throws -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw SecureVaultError.keychain(status) }
        return item as? Data
    }

    private static func storeKey(_ data: Data, service: String, account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecValueData as String: data
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw SecureVaultError.keychain(status) }
    }
}
