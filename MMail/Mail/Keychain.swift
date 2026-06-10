import Foundation
import Security

// Minimal generic-password Keychain wrapper for storing mail credentials.
enum Keychain {
    private static let service = "studio.cobalt.MMail.mail"

    @discardableResult
    static func setPassword(_ password: String, account: String) -> Bool {
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
        return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
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
    /// must never be used as a UserDefaults key — the Keychain is the primary
    /// store; the secret also mirrors to a 0600 fallback file via ProxySecretStore.
    static let proxySecretAccount = "mmail.imageProxy.signingSecret"

    /// Store (or clear, when empty) the image-proxy signing secret in the Keychain.
    /// Reuses the generic-password wrapper; the secret never touches UserDefaults.
    /// Returns whether the store succeeded (the empty→delete branch always returns
    /// true, since clearing is not a failure the caller needs to surface).
    @discardableResult
    static func storeProxySecret(_ secret: String) -> Bool {
        let trimmed = secret.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            deletePassword(account: proxySecretAccount)
            return true
        } else {
            return setPassword(trimmed, account: proxySecretAccount)
        }
    }

    /// Read the image-proxy signing secret from the Keychain, or nil if unset.
    static func readProxySecret() -> String? {
        password(account: proxySecretAccount)
    }
}
