import Testing
import NIOIMAP
@testable import MMail

/// Regression-pins for `IMAPService.classify(name:attributes:)` (SC-002): the
/// special-use IMAP attribute (RFC 6154) MUST take precedence over the
/// name-based heuristic, across all five flags, and the name heuristic MUST
/// still work as the fallback when no flag is present. `classify()` already
/// implements this precedence, so these tests PASS immediately — they lock the
/// contract the `RETURN (SPECIAL-USE)` LIST change depends on so it cannot
/// silently regress.
@Suite struct ClassifyTests {

    // MARK: - Special-use flag wins over a misleading name (all five flags)

    @Test func junkFlagWinsOverNonStandardName() {
        // Localized "Werbung" flagged \Junk → .junk (the flag wins, not the name).
        #expect(IMAPService.classify(name: "Werbung",
                                     attributes: [MailboxInfo.Attribute("\\Junk")]) == .junk)
    }

    @Test func sentFlagWinsOverNonStandardName() {
        #expect(IMAPService.classify(name: "Gesendet",
                                     attributes: [MailboxInfo.Attribute("\\Sent")]) == .sent)
    }

    @Test func draftsFlagWinsOverNonStandardName() {
        #expect(IMAPService.classify(name: "Entwürfe",
                                     attributes: [MailboxInfo.Attribute("\\Drafts")]) == .drafts)
    }

    @Test func trashFlagWinsOverMisleadingName() {
        // "Papierkorb" flagged \Trash → .trash (precedence holds for non-Junk too).
        #expect(IMAPService.classify(name: "Papierkorb",
                                     attributes: [MailboxInfo.Attribute("\\Trash")]) == .trash)
    }

    @Test func archiveFlagWinsOverNonStandardName() {
        #expect(IMAPService.classify(name: "Archiv",
                                     attributes: [MailboxInfo.Attribute("\\Archive")]) == .archive)
    }

    // MARK: - Junk flag with a standard name still resolves to .junk

    @Test func junkFlagWithStandardName() {
        #expect(IMAPService.classify(name: "Spam",
                                     attributes: [MailboxInfo.Attribute("\\Junk")]) == .junk)
    }

    // MARK: - Name fallback when no special-use attribute is present

    @Test func nameFallbackJunkWhenNoFlag() {
        #expect(IMAPService.classify(name: "Spam", attributes: []) == .junk)
    }

    @Test func nameFallbackSentWhenNoFlag() {
        #expect(IMAPService.classify(name: "Sent", attributes: []) == .sent)
    }

    // MARK: - Generic unflagged folder falls through to .other

    @Test func genericUnflaggedFolderIsOther() {
        #expect(IMAPService.classify(name: "Projects", attributes: []) == .other)
    }

    // MARK: - INBOX is always .inbox

    @Test func inboxIsInbox() {
        #expect(IMAPService.classify(name: "INBOX", attributes: []) == .inbox)
    }
}
