import Foundation

enum ConnectionSecurity: String, Codable, CaseIterable, Identifiable {
    case tls        // implicit TLS/SSL (e.g. IMAP 993, SMTP 465)
    case startTLS   // upgrade plaintext to TLS (e.g. SMTP 587, IMAP 143)
    case none       // plaintext (discouraged)
    var id: String { rawValue }
    var label: String {
        switch self {
        case .tls: return "SSL / TLS"
        case .startTLS: return "STARTTLS"
        case .none: return "None"
        }
    }
}

// Connection settings for a manually-configured IMAP/SMTP account.
// The password(s) live in the Keychain, keyed by the ids below.
struct MailAccountConfig: Codable, Identifiable {
    var id: String
    var displayName: String
    var email: String

    var imapHost: String
    var imapPort: Int
    var imapSecurity: ConnectionSecurity
    var imapUsername: String

    var smtpHost: String
    var smtpPort: Int
    var smtpSecurity: ConnectionSecurity
    var smtpUsername: String

    var avatarColorHex: String? = nil
    var hasCustomAvatar: Bool? = nil

    var imapPasswordKey: String { "\(id).imap" }
    var smtpPasswordKey: String { "\(id).smtp" }

    var imapPassword: String? { Keychain.password(account: imapPasswordKey) }
    var smtpPassword: String? { Keychain.password(account: smtpPasswordKey) }
}
