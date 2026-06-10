import Testing
import Foundation
@testable import MMail

/// Unit tests for `TrustedSenders`: the PURE core that owns ONE canonical address
/// normalization shared by ADD, CONTAINS, REMOVE, and LISTING over an injected
/// `Set<String>`. Everything is exercised with injected `Set<String>` / `String`
/// values and NO AppModel / UserDefaults / Keychain / WebKit access, proving purity
/// (SC-002). Asserted here: `normalize`'s canonical form (SC-002), add/contains/remove
/// agreement on raw inputs + the in-session-vs-relaunch regression (SC-003), `add`
/// idempotence/de-dup + non-address rejection and `remove` totality (SC-004), and
/// `list`'s lexicographic-ascending + empty-set determinism (SC-005). SC-001 (on-screen
/// Settings list/remove + reader re-block) is manual, not assertable by this target.
@Suite struct TrustedSendersTests {

    /// The representative raw inputs that all normalize to the canonical `"a@b.com"`.
    private static let raws = ["a@b.com", "A@B.COM", "  a@b.com  ", "<a@b.com>", "<A@B.com >"]

    // MARK: - normalize: canonical form (SC-002)

    @Test func normalizeProducesCanonicalForm() {
        #expect(TrustedSenders.normalize("a@b.com") == "a@b.com")
        #expect(TrustedSenders.normalize("A@B.COM") == "a@b.com")
        #expect(TrustedSenders.normalize("  a@b.com  ") == "a@b.com")
        #expect(TrustedSenders.normalize("<a@b.com>") == "a@b.com")
        #expect(TrustedSenders.normalize("<A@B.com >") == "a@b.com")
    }

    @Test func normalizeYieldsNilForEmptyish() {
        #expect(TrustedSenders.normalize(nil) == nil)
        #expect(TrustedSenders.normalize("   ") == nil)
        #expect(TrustedSenders.normalize("<>") == nil)
        #expect(TrustedSenders.normalize("") == nil)
    }

    /// Value-safety basis for T005: for a clean `mailbox@host`, `normalize` is just
    /// `lowercased()` — trim/`<>`-strip are no-ops — so `isImageTrusted`'s membership
    /// test stays byte-identical to the old `lowercased()`-only lookup.
    @Test func normalizeParityWithLowercasedForCleanAddress() {
        for clean in ["mailbox@host", "Mailbox@Host", "news@shop.com", "a@b.com"] {
            #expect(TrustedSenders.normalize(clean) == clean.lowercased())
        }
    }

    // MARK: - add / contains agree on raw input (SC-003 central edge case)

    @Test func addThenContainsAgreeOnSameRaw() {
        for raw in Self.raws {
            #expect(TrustedSenders.contains(TrustedSenders.add([], raw), raw) == true,
                    "add then contains should agree for raw \"\(raw)\"")
        }
    }

    // MARK: - remove revokes by raw input (SC-003)

    @Test func removeRevokesBySameRaw() {
        for raw in Self.raws {
            let added = TrustedSenders.add([], raw)
            #expect(TrustedSenders.contains(TrustedSenders.remove(added, raw), raw) == false,
                    "remove of the same raw should revoke for raw \"\(raw)\"")
        }
    }

    // MARK: - SC-003 regression: in-session-vs-relaunch divergence closed

    /// Simulate the persisted-reload canonicalization (`AppModel.swift:267-268` maps
    /// stored strings through `normalizeAddress`): hold a set of ONLY the reloaded
    /// canonical member, then assert `contains` still honors the ORIGINAL raw input.
    /// Crash-safe: never force-unwrap `normalize` against the T001 stub — a `nil`
    /// canonical produces a CLEAN expected-FAIL via `#expect(canonical != nil)`.
    @Test func postRelaunchCanonicalStillMatchesOriginalRaw() {
        let canonical = TrustedSenders.normalize("<A@B.com >")
        #expect(canonical != nil)
        if let c = canonical {
            #expect(TrustedSenders.contains([c], "<A@B.com >") == true)
        }
    }

    // MARK: - add idempotent / de-duplicating (SC-004)

    @Test func addIsIdempotentAndDeDuplicating() {
        let s1 = TrustedSenders.add(TrustedSenders.add([], "a@b.com"), "A@B.COM")
        #expect(s1 == ["a@b.com"])
        let s2 = TrustedSenders.add(TrustedSenders.add([], "a@b.com"), " a@b.com ")
        #expect(s2 == ["a@b.com"])
    }

    @Test func addRejectsNonAddresses() {
        #expect(TrustedSenders.add([], "not-an-email") == [])
        #expect(TrustedSenders.add([], "   ") == [])
        #expect(TrustedSenders.add([], "<>") == [])
    }

    // MARK: - remove total (SC-004)

    @Test func removeIsTotal() {
        #expect(TrustedSenders.remove(["a@b.com"], "x@y.com") == ["a@b.com"]) // absent → no-op
        #expect(TrustedSenders.remove(["a@b.com"], "A@B.COM") == [])          // variant removes
        #expect(TrustedSenders.remove(["a@b.com"], "a@b.com") == [])          // sole member → empty
    }

    // MARK: - list deterministic (SC-005)

    @Test func listIsSortedAscending() {
        #expect(TrustedSenders.list(["c@x.com", "a@x.com", "b@x.com"])
                == ["a@x.com", "b@x.com", "c@x.com"])
    }

    @Test func listOfEmptySetIsEmpty() {
        #expect(TrustedSenders.list([]) == [])
    }
}
