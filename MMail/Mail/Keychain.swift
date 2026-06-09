import Foundation
import Security

// Minimal generic-password Keychain wrapper for storing mail credentials.
enum Keychain {
    private static let service = "studio.cobalt.MMail.mail"

    static func setPassword(_ password: String, account: String) {
        let data = Data(password.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
        var add = query
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(add as CFDictionary, nil)
    }

    static func password(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func deletePassword(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }

    // MARK: - Image proxy signing secret

    /// Keychain account used for the image-proxy HMAC signing secret. NOTE: this
    /// must never be used as a UserDefaults key — the secret lives only here.
    static let proxySecretAccount = "mmail.imageProxy.signingSecret"

    /// Store (or clear, when empty) the image-proxy signing secret in the Keychain.
    /// Stub until T016.
    static func storeProxySecret(_ secret: String) {
        // not implemented
    }

    /// Read the image-proxy signing secret from the Keychain, or nil if unset.
    /// Stub until T016.
    static func readProxySecret() -> String? {
        nil
    }
}
