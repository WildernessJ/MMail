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

    @Test func draftsFolderShowsItsRecipients() {
        let e = email(to: ["bob@example.com", "carol@example.com"], folder: "drafts")
        #expect(AppModel.recipientLine(for: e, account: account("j_holdy@mailbox.org"))
                == "to bob@example.com, carol@example.com")
    }

    @Test func draftsFolderWithNoRecipientShowsPlaceholder() {
        let e = email(to: [], folder: "drafts")
        #expect(AppModel.recipientLine(for: e, account: account("j_holdy@mailbox.org"))
                == "to (no recipient)")
    }

    @Test func outboxFolderShowsItsRecipients() {
        let e = email(to: ["bob@example.com", "carol@example.com"], folder: "outbox")
        #expect(AppModel.recipientLine(for: e, account: account("j_holdy@mailbox.org"))
                == "to bob@example.com, carol@example.com")
    }

    @Test func outboxFolderWithNoRecipientShowsPlaceholder() {
        let e = email(to: [], folder: "outbox")
        #expect(AppModel.recipientLine(for: e, account: account("j_holdy@mailbox.org"))
                == "to (no recipient)")
    }

    // MARK: - Within-day newest-first comparator (SC-003)

    /// Sorts via the production comparator, mirroring the AppModel seam.
    private func sortedNewestFirst(_ list: [Email]) -> [Email] {
        list.sorted(by: AppModel.isNewerFirst)
    }

    /// (a) Higher `uid` is "newer" → sorts before a lower `uid`.
    @Test func higherUidSortsFirst() {
        let newer = email("a", uid: 200)
        let older = email("b", uid: 100)
        #expect(AppModel.isNewerFirst(newer, older))
        #expect(!AppModel.isNewerFirst(older, newer))
    }

    /// (b) Equal `uid` → deterministic tiebreak by ascending `id`.
    @Test func equalUidBreaksTieById() {
        let lowId = email("aaa", uid: 100)
        let highId = email("zzz", uid: 100)
        #expect(AppModel.isNewerFirst(lowId, highId))
        #expect(!AppModel.isNewerFirst(highId, lowId))
    }

    /// (c) `nil` vs `nil` `uid` → both treated as 0, tiebreak by `id`, stable.
    @Test func nilUidsBreakTieByIdStably() {
        let lowId = email("aaa", uid: nil)
        let highId = email("zzz", uid: nil)
        #expect(AppModel.isNewerFirst(lowId, highId))
        #expect(!AppModel.isNewerFirst(highId, lowId))
    }

    /// `nil` uid is treated as 0 → loses to any present positive uid.
    @Test func nilUidIsOlderThanPresentUid() {
        let present = email("a", uid: 1)
        let missing = email("b", uid: nil)
        #expect(AppModel.isNewerFirst(present, missing))
        #expect(!AppModel.isNewerFirst(missing, present))
    }

    /// Three Today messages arriving 08:00 (uid 10), 10:00 (uid 20), 11:24 (uid 30)
    /// render top-to-bottom as 11:24, 10:00, 08:00 (highest uid first).
    @Test func newestArrivalAppearsAtTop() {
        let m0800 = email("m0800", uid: 10)
        let m1000 = email("m1000", uid: 20)
        let m1124 = email("m1124", uid: 30)
        let sorted = sortedNewestFirst([m0800, m1124, m1000])
        #expect(sorted.map(\.id) == ["m1124", "m1000", "m0800"])
    }

    /// (d) Sorting a mixed list drops/duplicates nothing: count and id-set preserved.
    @Test func sortPreservesEveryMessage() {
        let list = [
            email("a", uid: 5),
            email("b", uid: nil),
            email("c", uid: 5),    // dup uid with a
            email("d", uid: 99),
            email("e", uid: nil),  // dup nil uid with b
        ]
        let sorted = sortedNewestFirst(list)
        #expect(sorted.count == list.count)
        #expect(Set(sorted.map(\.id)) == Set(list.map(\.id)))
    }

    /// Comparator is render-stable: re-sorting an already-sorted list is a fixpoint.
    @Test func reSortingSortedListIsIdempotent() {
        let list = [
            email("a", uid: 5),
            email("c", uid: 5),
            email("b", uid: nil),
            email("e", uid: nil),
            email("d", uid: 99),
        ]
        let once = sortedNewestFirst(list)
        let twice = sortedNewestFirst(once)
        #expect(once.map(\.id) == twice.map(\.id))
    }
}
