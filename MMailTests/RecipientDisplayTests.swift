import Testing
import Foundation
@testable import MMail

/// Unit tests for the PURE, SwiftUI-free `RecipientDisplay` collapse seam
/// (Piece C / SC-003): the (recipient list, limit) → (shown, overflow) mapping
/// the reader header's `To:` / `Cc:` first-N + `+N` expander consumes. No
/// `AppModel` or SwiftUI host is constructed.
///
/// Also covers the additive-`Codable` migration guarantee: a cache entry written
/// before this feature (no `cc` key, single-element `to`) MUST decode with
/// `cc == nil` and the existing `to` preserved — no wipe.
///
/// Mirrors specs/reader-list-polish.md scenarios:
/// - Overflow computed: collapsed(5, limit:3) → 3 shown + overflow 2.
/// - At or under limit: collapsed(≤3, limit:3) → all shown + overflow 0.
/// - Empty: collapsed([], limit:3) → [] + 0.
/// - Pre-feature cache decodes: no `cc` key → cc == nil, to preserved.
@Suite struct RecipientDisplayTests {

    // MARK: - collapsed: overflow computed

    @Test func fiveRecipientsCollapseToThreePlusTwo() {
        let all = ["a@x.com", "b@x.com", "c@x.com", "d@x.com", "e@x.com"]
        let r = RecipientDisplay.collapsed(all, limit: 3)
        #expect(r.shown == ["a@x.com", "b@x.com", "c@x.com"])
        #expect(r.overflow == 2)
    }

    // MARK: - collapsed: at or under limit

    @Test func threeRecipientsShownInFullNoOverflow() {
        let all = ["a@x.com", "b@x.com", "c@x.com"]
        let r = RecipientDisplay.collapsed(all, limit: 3)
        #expect(r.shown == all)
        #expect(r.overflow == 0)
    }

    @Test func underLimitShownInFullNoOverflow() {
        let all = ["a@x.com", "b@x.com"]
        let r = RecipientDisplay.collapsed(all, limit: 3)
        #expect(r.shown == all)
        #expect(r.overflow == 0)
    }

    // MARK: - collapsed: empty

    @Test func emptyListYieldsEmptyShownZeroOverflow() {
        let r = RecipientDisplay.collapsed([], limit: 3)
        #expect(r.shown == [])
        #expect(r.overflow == 0)
    }

    // MARK: - additive Codable: pre-feature cache decodes

    /// An on-disk `Email` serialized BEFORE this feature: it has the existing keys
    /// and a single-element `to`, but NO `cc` key. Decoding must succeed with
    /// `cc == nil` and the `to` preserved (additive-Codable, no wipe).
    private let preFeatureEmailJSON = """
    {
        "id": "acct#inbox#42",
        "account": "acct",
        "from": "alice@example.org",
        "to": ["Bob <bob@example.org>"],
        "subject": "Hello",
        "preview": "Hi there",
        "body": "Hi there, this is the body.",
        "time": "9:30 AM",
        "day": "today",
        "unread": true,
        "starred": false,
        "hasAttachment": false,
        "labels": [],
        "folder": "inbox",
        "bodyLoaded": true,
        "attachments": []
    }
    """

    @Test func preFeatureEmailDecodesWithCcNilAndToPreserved() throws {
        let email = try JSONDecoder().decode(Email.self,
                                             from: Data(preFeatureEmailJSON.utf8))
        #expect(email.cc == nil)
        #expect(email.to == ["Bob <bob@example.org>"])
    }
}
