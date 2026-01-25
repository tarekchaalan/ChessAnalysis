import Foundation
import Security

enum KeychainHelper {
    private static let serviceName = "com.chessanalysis.credentials"

    enum KeychainError: Error {
        case itemNotFound
        case duplicateItem
        case unexpectedStatus(OSStatus)
        case encodingFailed
    }

    static func save(key: String, value: String) throws {
        guard let data = value.data(using: .utf8) else {
            throw KeychainError.encodingFailed
        }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key,
            kSecValueData as String: data
        ]

        // First try to delete any existing item
        SecItemDelete(query as CFDictionary)

        // Then add the new item
        let status = SecItemAdd(query as CFDictionary, nil)

        guard status == errSecSuccess else {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    static func load(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let string = String(data: data, encoding: .utf8) else {
            return nil
        }

        return string
    }

    static func delete(key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key
        ]

        SecItemDelete(query as CFDictionary)
    }

    /// Migrate a value from UserDefaults to Keychain if it exists
    static func migrateFromUserDefaults(userDefaultsKey: String, keychainKey: String) {
        // Check if already migrated (value exists in Keychain)
        if load(key: keychainKey) != nil {
            // Already migrated, clean up UserDefaults
            UserDefaults.standard.removeObject(forKey: userDefaultsKey)
            return
        }

        // Get value from UserDefaults
        guard let value = UserDefaults.standard.string(forKey: userDefaultsKey),
              !value.isEmpty else {
            return
        }

        // Save to Keychain
        do {
            try save(key: keychainKey, value: value)
            // Remove from UserDefaults after successful migration
            UserDefaults.standard.removeObject(forKey: userDefaultsKey)
        } catch {
            // Migration failed, keep in UserDefaults for now
            print("[KeychainHelper] Migration failed for \(keychainKey): \(error)")
        }
    }
}
