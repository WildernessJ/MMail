import Testing
@testable import MMail

/// Unit tests for the two pure display seams on `AppModel`:
/// `recipientLine(for:account:)` (the reader's delivered-to "to …" line, SC-001/SC-004)
/// and `isNewerFirst(_:_:)` (the within-day newest-first comparator, SC-003/SC-004).
/// Both are static, so no `AppModel` / SwiftUI host is required.
@Suite struct DisplayFormattingTests {

    // MARK: - Fixtures

    /// Minimal received-mail `Email`, varying only `to`, `folder`, `uid`, and `id`.
    private func email(_ id: String = "e", account: String = "acct",
                       to: [String]? = nil, folder: String = "inbox",
                       uid: UInt32? = nil) -> Email {
        Email(id: id, account: account, from: "f", to: to,
              subject: "s", preview: "", body: "", time: "", day: "today",
              folder: folder, uid: uid)
    }

    private func account(_ email: String) -> Account {
        Account(id: "acct", name: "Acct", email: email, initials: "A",
                gradient: ["111111", "222222"], colorHex: "333333", provider: "imap")
    }

    // MARK: - Recipient line (SC-001)

    /// Scenario (a): received mail shows the alias it was delivered to,
    /// NOT the active account's canonical address. This is the RED signal
    /// against the T001 stub (which returns the account address).
    @Test func receivedMailShowsDeliveredAlias() {
        let e = email(to: ["hiltl@sl.holdy.org"], folder: "inbox")
        let line = AppModel.recipientLine(for: e, account: account("j_holdy@mailbox.org"))
        #expect(line.contains("hiltl@sl.holdy.org"))
        #expect(!line.contains("j_holdy@mailbox.org"))
    }

    /// Scenario (b): received mail with empty/absent `to` falls back to the
    /// account address — and `me` when no account is present.
    @Test func receivedMailWithNoRecipientFallsBackToAccount() {
        let e = email(to: nil, folder: "inbox")
        #expect(AppModel.recipientLine(for: e, account: account("j_holdy@mailbox.org"))
                == "to j_holdy@mailbox.org")
    }

    @Test func receivedMailWithEmptyRecipientArrayFallsBackToAccount() {
        let e = email(to: [], folder: "inbox")
        #expect(AppModel.recipientLine(for: e, account: account("j_holdy@mailbox.org"))
                == "to j_holdy@mailbox.org")
    }

    @Test func receivedMailWithNoAccountShowsMe() {
        let e = email(to: nil, folder: "inbox")
        #expect(AppModel.recipientLine(for: e, account: nil) == "to me")
    }

    // MARK: - Sent-folder recipient display is unchanged (SC-001)

    @Test func sentFolderShowsItsRecipients() {
        let e = email(to: ["bob@example.com", "carol@example.com"], folder: "sent")
        #expect(AppModel.recipientLine(for: e, account: account("j_holdy@mailbox.org"))
                == "to bob@example.com, carol@example.com")
    }

    @Test func sentFolderWithNoRecipientShowsPlaceholder() {
        let e = email(to: [], folder: "sent")
        #expect(AppModel.recipientLine(for: e, account: account("j_holdy@mailbox.org"))
                == "to (no recipient)")
    }
}
