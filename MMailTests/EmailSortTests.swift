import Testing
import Foundation
@testable import MMail

/// Unit tests for the PURE, SwiftUI-free `EmailSort` seam (Piece B / SC-002, SC-004):
/// the (key, direction) → comparator / group-by-day flag / ordered-sections mapping,
/// plus `ListSort` persistence parsing. No `AppModel` or SwiftUI host is constructed.
///
/// Mirrors specs/reader-list-polish.md scenarios:
/// - Date/forward == the pre-feature `orderNewerFirst` (sortDate desc, uid desc, id asc).
/// - Date/reverse == the negation (oldest-first within section, deterministic tie-breaks).
/// - Missing / garbage persisted rawValue → `ListSort.default` (Date/forward), no trap.
/// - Sender key = name (non-empty) else from-address else "" lowercased.
/// - Subject key = subject lowercased with a single leading `Re:` / `Fwd:` stripped.
/// - Comparator is a valid strict weak ordering over equal-key / empty-sender / nil-date.
/// - `groupsByDay` true only for Date; `orderedSections` fixed except Date/reverse.
@Suite struct EmailSortTests {

    // MARK: - Fixtures

    /// A received-mail `Email` varying the fields the sort keys read. `sortDate`
    /// is set post-construction (the hand init omits it, exactly as production does).
    private func email(id: String = "e",
                       fromName: String? = nil,
                       fromEmail: String? = nil,
                       subject: String = "s",
                       uid: UInt32? = nil,
                       sortDate: Date? = nil,
                       day: String = "today") -> Email {
        var e = Email(id: id, account: "acct", from: "f", to: nil,
                      subject: subject, preview: "", body: "", time: "", day: day,
                      folder: "inbox",
                      fromName: fromName, fromEmail: fromEmail, uid: uid)
        e.sortDate = sortDate
        return e
    }

    private let t0 = Date(timeIntervalSince1970: 1_000_000)
    private let t1 = Date(timeIntervalSince1970: 2_000_000)
    private let t2 = Date(timeIntervalSince1970: 3_000_000)

    // MARK: - ListSort persistence parsing

    @Test func defaultIsDateForward() {
        #expect(ListSort.default == ListSort(.date, .forward))
    }

    @Test func rawValueRoundTripsEveryCombination() {
        for k in SortKey.allCases {
            for d in SortDirection.allCases {
                let s = ListSort(k, d)
                #expect(ListSort(rawValue: s.rawValue) == s)
            }
        }
    }

    @Test func garbageRawValueIsNil() {
        #expect(ListSort(rawValue: "") == nil)
        #expect(ListSort(rawValue: "garbage") == nil)
        #expect(ListSort(rawValue: "date") == nil)
        #expect(ListSort(rawValue: "date.sideways") == nil)
        #expect(ListSort(rawValue: "color.forward") == nil)
    }

    /// The load path nil-coalesces a missing / garbage value to the default,
    /// so a fresh install (no key) and a corrupt value both render Date/forward.
    @Test func missingOrGarbageResolvesToDefault() {
        let missing: String? = nil
        let loaded = missing.flatMap { ListSort(rawValue: $0) } ?? .default
        #expect(loaded == ListSort.default)
        let garbage = ListSort(rawValue: "nonsense") ?? .default
        #expect(garbage == ListSort.default)
    }

    // MARK: - Date/forward == orderNewerFirst (byte-identical default)

    @Test func dateForwardMatchesOrderNewerFirst() {
        let a = email(id: "a", uid: 5, sortDate: t1)
        let b = email(id: "b", uid: 3, sortDate: t2)
        let cmp = EmailSort.comparator(for: ListSort(.date, .forward))
        // Every pairing must equal the pre-feature comparator exactly.
        #expect(cmp(a, b) == AppModel.isNewerFirst(a, b))
        #expect(cmp(b, a) == AppModel.isNewerFirst(b, a))
        // Newer sortDate sorts first.
        #expect(cmp(b, a) == true)   // t2 > t1
        #expect(cmp(a, b) == false)
    }

    @Test func dateForwardTieBreaksByUidThenId() {
        // Equal dates → higher uid first.
        let a = email(id: "a", uid: 9, sortDate: t1)
        let b = email(id: "b", uid: 2, sortDate: t1)
        let cmp = EmailSort.comparator(for: ListSort(.date, .forward))
        #expect(cmp(a, b) == true)   // uid 9 > 2
        // Equal date + equal uid → lower id first.
        let c = email(id: "aaa", uid: 4, sortDate: t1)
        let d = email(id: "zzz", uid: 4, sortDate: t1)
        #expect(cmp(c, d) == true)   // "aaa" < "zzz"
    }

    // MARK: - Date/reverse == the negation (oldest-first within section)

    @Test func dateReverseIsOldestFirst() {
        let older = email(id: "old", uid: 1, sortDate: t0)
        let newer = email(id: "new", uid: 2, sortDate: t2)
        let cmp = EmailSort.comparator(for: ListSort(.date, .reverse))
        #expect(cmp(older, newer) == true)    // oldest first
        #expect(cmp(newer, older) == false)
    }

    @Test func dateReverseIsTheNegationOfForward() {
        let a = email(id: "a", uid: 5, sortDate: t1)
        let b = email(id: "b", uid: 3, sortDate: t2)
        let fwd = EmailSort.comparator(for: ListSort(.date, .forward))
        let rev = EmailSort.comparator(for: ListSort(.date, .reverse))
        // reverse(a,b) == forward(b,a) — operands swapped, not the same function.
        #expect(rev(a, b) == fwd(b, a))
        #expect(rev(b, a) == fwd(a, b))
    }

    // MARK: - Sender key derivation

    @Test func senderKeyUsesNameWhenNonEmpty() {
        let e = email(fromName: "Bob Jones", fromEmail: "x@host")
        #expect(EmailSort.senderKey(e) == "bob jones")
    }

    @Test func senderKeyFallsBackToAddressWhenNameEmpty() {
        let blank = email(fromName: "   ", fromEmail: "Alice@Host")
        #expect(EmailSort.senderKey(blank) == "alice@host")
        let nilName = email(fromName: nil, fromEmail: "Carol@Host")
        #expect(EmailSort.senderKey(nilName) == "carol@host")
    }

    @Test func senderKeyEmptyWhenNeitherPresent() {
        let e = email(fromName: nil, fromEmail: nil)
        #expect(EmailSort.senderKey(e) == "")
        let e2 = email(fromName: "", fromEmail: "")
        #expect(EmailSort.senderKey(e2) == "")
    }

    // MARK: - Subject key derivation

    @Test func subjectKeyLowercasesAndStripsRe() {
        #expect(EmailSort.subjectKey(email(subject: "Re: Budget")) == "budget")
        #expect(EmailSort.subjectKey(email(subject: "RE:Budget")) == "budget")
        #expect(EmailSort.subjectKey(email(subject: "  re:   Budget ")) == "budget")
        #expect(EmailSort.subjectKey(email(subject: "Budget review")) == "budget review")
    }

    @Test func subjectKeyStripsFwdAndOnlyOnePrefix() {
        #expect(EmailSort.subjectKey(email(subject: "Fwd: Hello")) == "hello")
        #expect(EmailSort.subjectKey(email(subject: "FWD: Hello")) == "hello")
        // Only a SINGLE leading prefix is stripped.
        #expect(EmailSort.subjectKey(email(subject: "Re: Re: Twice")) == "re: twice")
    }

    @Test func subjectSortGroupsReplyWithOriginal() {
        // "Re: Budget" and "Budget review" both key off "budget…" so they cluster.
        let reBudget = EmailSort.subjectKey(email(subject: "Re: Budget"))
        let budgetReview = EmailSort.subjectKey(email(subject: "Budget review"))
        #expect(reBudget == "budget")
        #expect(budgetReview.hasPrefix("budget"))
    }

    // MARK: - Sender / Subject comparator direction + tie-breaks

    @Test func senderForwardIsAscendingCaseInsensitive() {
        let a = email(id: "a", fromName: "alice", uid: 1)
        let z = email(id: "z", fromName: "Zara", uid: 2)
        let cmp = EmailSort.comparator(for: ListSort(.sender, .forward))
        #expect(cmp(a, z) == true)    // alice < zara
        #expect(cmp(z, a) == false)
    }

    @Test func senderReverseIsDescending() {
        let a = email(id: "a", fromName: "alice", uid: 1)
        let z = email(id: "z", fromName: "Zara", uid: 2)
        let cmp = EmailSort.comparator(for: ListSort(.sender, .reverse))
        #expect(cmp(z, a) == true)    // zara first descending
        #expect(cmp(a, z) == false)
    }

    @Test func keyedComparatorTieBreaksDeterministically() {
        // Equal sender key → uid desc then id asc, SAME in both directions.
        let a = email(id: "aaa", fromName: "same", uid: 9)
        let b = email(id: "bbb", fromName: "same", uid: 2)
        let fwd = EmailSort.comparator(for: ListSort(.sender, .forward))
        let rev = EmailSort.comparator(for: ListSort(.sender, .reverse))
        #expect(fwd(a, b) == true)    // uid 9 > 2
        #expect(rev(a, b) == true)    // tie-break is NOT flipped by direction
    }

    // MARK: - Strict weak ordering (no comparator-contract trap)

    /// A deliberately pathological list: equal keys, empty senders, nil sortDate,
    /// nil uid. `sort(by:)` must complete for every (key, direction) without a
    /// "comparator violates its contract" runtime fault.
    private func pathologicalList() -> [Email] {
        [
            email(id: "1", fromName: nil, fromEmail: nil, subject: "Re: x", uid: nil, sortDate: nil),
            email(id: "2", fromName: "", fromEmail: "", subject: "x", uid: 5, sortDate: t1),
            email(id: "3", fromName: "Bob", fromEmail: "b@h", subject: "Re: X", uid: 5, sortDate: t1),
            email(id: "4", fromName: "bob", fromEmail: "b@h", subject: "y", uid: nil, sortDate: t2),
            email(id: "5", fromName: nil, fromEmail: "a@h", subject: "", uid: 0, sortDate: nil),
            email(id: "6", fromName: "Bob", fromEmail: "b@h", subject: "Re: X", uid: 5, sortDate: t1),
        ]
    }

    /// Brute-force the strict-weak-ordering axioms over the comparator: irreflexive,
    /// asymmetric, and transitive. A violation is what would make `sort` trap.
    private func assertStrictWeakOrdering(_ list: [Email], _ less: (Email, Email) -> Bool) {
        for x in list {
            #expect(less(x, x) == false)                       // irreflexive
            for y in list {
                if less(x, y) { #expect(less(y, x) == false) } // asymmetric
            }
        }
        // Transitivity of the derived equivalence + the order.
        for x in list {
            for y in list {
                for z in list {
                    if less(x, y) && less(y, z) {
                        #expect(less(x, z))
                    }
                }
            }
        }
    }

    @Test func everyComparatorIsAStrictWeakOrdering() {
        let list = pathologicalList()
        for k in SortKey.allCases {
            for d in SortDirection.allCases {
                let cmp = EmailSort.comparator(for: ListSort(k, d))
                assertStrictWeakOrdering(list, cmp)
                // And the actual sort must not trap.
                _ = list.sorted(by: cmp)
            }
        }
    }

    // MARK: - groupsByDay

    @Test func groupsByDayTrueOnlyForDate() {
        #expect(EmailSort.groupsByDay(for: ListSort(.date, .forward)) == true)
        #expect(EmailSort.groupsByDay(for: ListSort(.date, .reverse)) == true)
        #expect(EmailSort.groupsByDay(for: ListSort(.sender, .forward)) == false)
        #expect(EmailSort.groupsByDay(for: ListSort(.sender, .reverse)) == false)
        #expect(EmailSort.groupsByDay(for: ListSort(.subject, .forward)) == false)
        #expect(EmailSort.groupsByDay(for: ListSort(.subject, .reverse)) == false)
    }

    // MARK: - orderedSections

    @Test func orderedSectionsFixedForDateForwardAndAllNonDate() {
        let fixed = ["today", "yesterday", "earlier", "snoozed"]
        #expect(EmailSort.orderedSections(for: ListSort(.date, .forward)) == fixed)
        #expect(EmailSort.orderedSections(for: ListSort(.sender, .forward)) == fixed)
        #expect(EmailSort.orderedSections(for: ListSort(.sender, .reverse)) == fixed)
        #expect(EmailSort.orderedSections(for: ListSort(.subject, .forward)) == fixed)
        #expect(EmailSort.orderedSections(for: ListSort(.subject, .reverse)) == fixed)
    }

    @Test func orderedSectionsReversedForDateReverseSnoozedLast() {
        #expect(EmailSort.orderedSections(for: ListSort(.date, .reverse))
                == ["earlier", "yesterday", "today", "snoozed"])
    }
}
