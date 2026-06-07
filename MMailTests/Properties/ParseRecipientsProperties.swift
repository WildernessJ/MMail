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

    /// A generator that yields both the rendered field AND its structured
    /// entries, so the extraction property can assert against the known
    /// addresses and display names.
    private var fieldWithEntries: Gen<(field: String, entries: [RecipientEntry])> {
        Gen<(field: String, entries: [RecipientEntry])>(
            generate: { rng in
                let entries = Gen<String>.constrainedEntries(&rng)
                let field = Gen<String>.joinEntries(entries.map { $0.rendered }, &rng)
                return (field, entries)
            }
        )
    }

    /// Address extraction without display-name leakage: each embedded address
    /// appears in the result; every returned entry contains `@`; and no returned
    /// entry contains its source display-name text.
    @Test func extractsAddressesWithoutLeakingDisplayName() {
        check("parseRecipients extraction", fieldWithEntries) { sample in
            let result = AppModel.parseRecipients(sample.field)

            // Every returned entry contains `@`.
            if !result.allSatisfy({ $0.contains("@") }) { return false }

            // Each embedded address appears in the result.
            for entry in sample.entries {
                if !result.contains(entry.address) { return false }
            }

            // No returned entry contains a non-empty source display-name text.
            for entry in sample.entries where !entry.display.isEmpty {
                if result.contains(where: { $0.contains(entry.display) }) { return false }
            }
            return true
        }
    }
}
