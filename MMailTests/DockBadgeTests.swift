import Testing
@testable import MMail

/// Unit tests for the two pure Dock-badge seams on `AppModel`:
/// `dockBadgeLabel(unread:)` (the formatter, SC-003) and
/// `unreadInboxCount(_:)` (the counter, SC-004). Both are static, so no
/// `AppModel` instantiation is required.
@Suite struct DockBadge {

    // MARK: - Formatter (SC-003)

    @Test func positiveCountRendersAsDecimalString() {
        #expect(AppModel.dockBadgeLabel(unread: 5) == "5")
    }

    @Test func singleUnreadRendersAsOne() {
        #expect(AppModel.dockBadgeLabel(unread: 1) == "1")
    }

    @Test func zeroClearsTheBadge() {
        // Empty string clears the badge — never the literal "0".
        #expect(AppModel.dockBadgeLabel(unread: 0) == "")
    }

    @Test func negativeDefendsToEmpty() {
        #expect(AppModel.dockBadgeLabel(unread: -1) == "")
    }

    @Test func largeCountIsNotCapped() {
        #expect(AppModel.dockBadgeLabel(unread: 1234) == "1234")
    }

    // MARK: - Counter (SC-004)

    /// Minimal `Email` constructor varying only `unread` and `folder`.
    private func email(_ id: String, account: String, unread: Bool, folder: String) -> Email {
        Email(id: id, account: account, from: "f", subject: "s",
              preview: "", body: "", time: "", day: "today",
              unread: unread, folder: folder)
    }

    @Test func sumsUnreadInboxAcrossAccounts() {
        // 3 unread inbox on account A + 2 unread inbox on account B → 5.
        let emails = [
            email("a1", account: "A", unread: true, folder: "inbox"),
            email("a2", account: "A", unread: true, folder: "inbox"),
            email("a3", account: "A", unread: true, folder: "inbox"),
            email("b1", account: "B", unread: true, folder: "inbox"),
            email("b2", account: "B", unread: true, folder: "inbox"),
        ]
        #expect(AppModel.unreadInboxCount(emails) == 5)
    }

    @Test func excludesReadAndNonInboxMessages() {
        // 2 unread inbox + 1 read inbox + 4 unread archive → 2.
        let emails = [
            email("i1", account: "A", unread: true, folder: "inbox"),
            email("i2", account: "A", unread: true, folder: "inbox"),
            email("i3", account: "A", unread: false, folder: "inbox"),  // read inbox
            email("ar1", account: "A", unread: true, folder: "archive"),
            email("ar2", account: "A", unread: true, folder: "archive"),
            email("ar3", account: "A", unread: true, folder: "archive"),
            email("ar4", account: "A", unread: true, folder: "archive"),
        ]
        #expect(AppModel.unreadInboxCount(emails) == 2)
    }

    @Test func emptyListIsZero() {
        // Passes against the T001 `0` stub (expected); not the RED signal.
        #expect(AppModel.unreadInboxCount([]) == 0)
    }

    @Test func nonInboxUnreadOnlyIsZero() {
        // Unread messages exist only outside the inbox → 0.
        let emails = [
            email("ar1", account: "A", unread: true, folder: "archive"),
            email("se1", account: "A", unread: true, folder: "sent"),
        ]
        #expect(AppModel.unreadInboxCount(emails) == 0)
    }
}
