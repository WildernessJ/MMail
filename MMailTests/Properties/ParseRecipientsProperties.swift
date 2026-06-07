import Testing
@testable import MMail

/// Property tests for `AppModel.parseRecipients`.
@Suite struct ParseRecipientsProperties {

    /// Crash-freedom: an arbitrary recipient field — including display names with
    /// arbitrary `<`/`>` in any order (e.g. a `>` before the first `<`) — must
    /// not trap. Before the T010 safety fix this CRASHES the test process on the
    /// documented backwards-range input; that process death is the expected RED
    /// signal. The generator is deliberately UNCONSTRAINED — do not weaken it to
    /// hide the defect.
    @Test func neverCrashesOnArbitraryField() {
        check("parseRecipients crash-freedom", Gen<String>.unconstrainedRecipientField) { field in
            _ = AppModel.parseRecipients(field)
            return true
        }
    }
}
