import Foundation

/// IMAP/SMTP presets so users only need to enter email + (app) password.
struct MailProvider: Identifiable, Equatable {
    let id: String
    let name: String
    let initial: String
    let colorHex: String
    let imapHost: String
    let imapPort: Int
    let imapSecurity: ConnectionSecurity
    let smtpHost: String
    let smtpPort: Int
    let smtpSecurity: ConnectionSecurity
    let domain: String   // used for the email placeholder
    let hint: String     // app-password guidance shown in setup

    var isCustom: Bool { id == "custom" }

    static let gmail = MailProvider(
        id: "gmail", name: "Gmail", initial: "G", colorHex: "EA4335",
        imapHost: "imap.gmail.com", imapPort: 993, imapSecurity: .tls,
        smtpHost: "smtp.gmail.com", smtpPort: 465, smtpSecurity: .tls,
        domain: "gmail.com",
        hint: "Gmail needs an App Password (not your normal password). Turn on 2-Step Verification, then create one at myaccount.google.com → Security → App passwords.")

    static let icloud = MailProvider(
        id: "icloud", name: "iCloud", initial: "iC", colorHex: "3693F3",
        imapHost: "imap.mail.me.com", imapPort: 993, imapSecurity: .tls,
        smtpHost: "smtp.mail.me.com", smtpPort: 587, smtpSecurity: .startTLS,
        domain: "icloud.com",
        hint: "iCloud needs an app-specific password. Create one at appleid.apple.com → Sign-In and Security → App-Specific Passwords.")

    static let outlook = MailProvider(
        id: "outlook", name: "Outlook", initial: "O", colorHex: "0078D4",
        imapHost: "outlook.office365.com", imapPort: 993, imapSecurity: .tls,
        smtpHost: "smtp.office365.com", smtpPort: 587, smtpSecurity: .startTLS,
        domain: "outlook.com",
        hint: "Many Microsoft accounts require OAuth (modern auth) and have password sign-in disabled. If connecting fails, this account needs OAuth, which isn't supported yet.")

    static let yahoo = MailProvider(
        id: "yahoo", name: "Yahoo", initial: "Y!", colorHex: "6001D2",
        imapHost: "imap.mail.yahoo.com", imapPort: 993, imapSecurity: .tls,
        smtpHost: "smtp.mail.yahoo.com", smtpPort: 465, smtpSecurity: .tls,
        domain: "yahoo.com",
        hint: "Yahoo needs an app password. Create one in Account Security → Generate app password.")

    static let fastmail = MailProvider(
        id: "fastmail", name: "Fastmail", initial: "F", colorHex: "0067B9",
        imapHost: "imap.fastmail.com", imapPort: 993, imapSecurity: .tls,
        smtpHost: "smtp.fastmail.com", smtpPort: 465, smtpSecurity: .tls,
        domain: "fastmail.com",
        hint: "Fastmail needs an app password. Create one in Settings → Privacy & Security → App passwords.")

    static let zoho = MailProvider(
        id: "zoho", name: "Zoho Mail", initial: "Z", colorHex: "E42527",
        imapHost: "imap.zoho.com", imapPort: 993, imapSecurity: .tls,
        smtpHost: "smtp.zoho.com", smtpPort: 465, smtpSecurity: .tls,
        domain: "zoho.com",
        hint: "Enable IMAP access in Zoho Mail (Settings → Mail Accounts → IMAP). If you use two-factor auth, create an application-specific password. Note: use your regional server (e.g. imap.zoho.eu / imap.zoho.in) under Server settings if your account isn't on zoho.com.")

    static let purelymail = MailProvider(
        id: "purelymail", name: "PurelyMail", initial: "PM", colorHex: "2E9E6B",
        imapHost: "imap.purelymail.com", imapPort: 993, imapSecurity: .tls,
        smtpHost: "smtp.purelymail.com", smtpPort: 465, smtpSecurity: .tls,
        domain: "purelymail.com",
        hint: "Use your PurelyMail password, or an app password created in the PurelyMail dashboard if you've enabled them.")

    static let custom = MailProvider(
        id: "custom", name: "Other", initial: "@", colorHex: "6B7088",
        imapHost: "", imapPort: 993, imapSecurity: .tls,
        smtpHost: "", smtpPort: 587, smtpSecurity: .startTLS,
        domain: "example.com", hint: "")

    static let all: [MailProvider] = [gmail, icloud, outlook, yahoo, fastmail, zoho, purelymail, custom]
}
