import Testing
import Foundation
@testable import MMail

/// Unit tests for the two pure Home-shell seams: `HomeWidgetVisibility` (additive,
/// absent-key-defaults-ON load/persist) and `InboxGlance.project` (read-only unread
/// projection over `[Email]`). Both are pure, so no `AppModel` instantiation is needed.

// MARK: - HomeWidgetVisibility (T002/T003 — SC-001/003/006)

@Suite struct HomeWidgetVisibilityTests {

    /// A throwaway `UserDefaults` suite, removed first so the test starts empty
    /// regardless of prior runs. Each test passes a unique name.
    private func freshDefaults(_ name: String) -> UserDefaults {
        let suite = "mmail.test.homeshell.\(name)"
        let d = UserDefaults(suiteName: suite)!
        d.removePersistentDomain(forName: suite)
        return d
    }

    @Test func absentKeysDefaultAllOn() {
        // RED until T003: fresh defaults → every widget ON (absent-key-defaults-ON).
        let d = freshDefaults("absentAllOn")
        let v = HomeWidgetVisibility.load(d)
        #expect(v.date == true)
        #expect(v.weather == true)
        #expect(v.inboxGlance == true)
        #expect(v.people == true)
        #expect(v.journal == true)
        #expect(v.todo == true)
    }

    @Test func roundTripPersistsMixedSet() {
        // RED until T003: persist a mixed set, re-load, expect the same struct back.
        let d = freshDefaults("roundTrip")
        let original = HomeWidgetVisibility(date: false, weather: true, inboxGlance: false,
                                            people: true, journal: false, todo: true)
        original.persist(d)
        let reloaded = HomeWidgetVisibility.load(d)
        #expect(reloaded == original)
    }

    @Test func absentSingleKeyDefaultsOnOthersAsStored() {
        // RED until T003: write five keys explicitly, leave `inboxGlance` absent.
        // The absent one loads ON; the others load exactly as written.
        let d = freshDefaults("absentSingle")
        d.set(false, forKey: HomeWidget.date.defaultsKey)
        d.set(true, forKey: HomeWidget.weather.defaultsKey)
        // inboxGlance: intentionally NOT written → must default ON.
        d.set(false, forKey: HomeWidget.people.defaultsKey)
        d.set(true, forKey: HomeWidget.journal.defaultsKey)
        d.set(false, forKey: HomeWidget.todo.defaultsKey)

        let v = HomeWidgetVisibility.load(d)
        #expect(v.inboxGlance == true)   // absent → ON
        #expect(v.date == false)
        #expect(v.weather == true)
        #expect(v.people == false)
        #expect(v.journal == true)
        #expect(v.todo == false)
    }

    @Test func loaderDoesNotTreatAbsentAsFalse() {
        // RED until T003: explicit guard against the `bool(forKey:)` bug. A widget
        // explicitly stored ON must load ON; an absent widget must ALSO load ON
        // (never the `false` that `bool(forKey:)` returns for a missing key).
        let d = freshDefaults("notBoolForKey")
        d.set(true, forKey: HomeWidget.todo.defaultsKey)   // explicit ON
        let v = HomeWidgetVisibility.load(d)
        #expect(v.todo == true)          // explicit ON survives
        #expect(v.date == true)          // absent → ON, NOT false
        #expect(v.weather == true)       // absent → ON
    }

    @Test func subscriptReadsAndWritesPerWidget() {
        // RED until T003: subscript get/set mutates the matching field.
        var v = HomeWidgetVisibility(date: true, weather: true, inboxGlance: true,
                                     people: true, journal: true, todo: true)
        v[.journal] = false
        #expect(v[.journal] == false)
        #expect(v.journal == false)
        #expect(v[.date] == true)
    }
}

// MARK: - InboxGlance.project (T004/T005 — SC-004/005)

@Suite struct InboxGlanceProjectTests {

    /// Builds an `Email` varying the fields the projection reads. `sortDate`, `uid`,
    /// `unread`, `folder`, `account` are all set post-init (the init takes no `sortDate`).
    private func email(_ id: String, account: String = "A", unread: Bool = true,
                       folder: String = "inbox", sortDate: Date? = nil,
                       uid: UInt32? = nil) -> Email {
        var e = Email(id: id, account: account, from: "f", subject: "s",
                      preview: "", body: "", time: "", day: "today",
                      unread: unread, folder: folder)
        e.sortDate = sortDate
        e.uid = uid
        return e
    }

    /// A fixed reference "now" so the new-today calendar comparison is deterministic.
    private let now = Date(timeIntervalSince1970: 1_700_000_000)  // 2023-11-14 UTC

    @Test func unreadCountsUnreadInboxForAccount() {
        // RED until T005: 3 unread inbox on A → unread == 3 for account "A".
        let emails = [
            email("a1", account: "A", unread: true, folder: "inbox"),
            email("a2", account: "A", unread: true, folder: "inbox"),
            email("a3", account: "A", unread: true, folder: "inbox"),
            email("a4", account: "A", unread: false, folder: "inbox"),  // read
            email("b1", account: "B", unread: true, folder: "inbox"),   // other account
        ]
        let r = InboxGlance.project(emails: emails, account: "A", now: now)
        #expect(r.unread == 3)
    }

    @Test func newTodaySameCalendarDayOnly() {
        // RED until T005: only unread inbox whose sortDate is the SAME calendar day
        // as `now` count as new-today.
        let earlier = now.addingTimeInterval(-86_400 * 3)  // 3 days before
        let emails = [
            email("today1", sortDate: now),
            email("today2", sortDate: now.addingTimeInterval(-3600)),  // same day, 1h earlier
            email("old1", sortDate: earlier),
        ]
        let r = InboxGlance.project(emails: emails, account: "A", now: now)
        #expect(r.unread == 3)
        #expect(r.newToday == 2)
    }

    @Test func nilSortDateCountsUnreadButNotNewToday() {
        // RED until T005: a nil-sortDate unread inbox message counts toward unread
        // but NOT toward newToday.
        let emails = [
            email("today1", sortDate: now),
            email("nodate", sortDate: nil),
        ]
        let r = InboxGlance.project(emails: emails, account: "A", now: now)
        #expect(r.unread == 2)
        #expect(r.newToday == 1)
    }

    @Test func peekIsNewestFirstCappedAtFive() {
        // RED until T005: 8 unread with descending sortDates → peek is exactly the 5
        // newest, in newest-first order (AppModel.isNewerFirst).
        var emails: [Email] = []
        for i in 0..<8 {
            // i=0 is newest (offset 0), i=7 is oldest (offset -7 days).
            emails.append(email("e\(i)", sortDate: now.addingTimeInterval(Double(-86_400 * i))))
        }
        let r = InboxGlance.project(emails: emails, account: "A", now: now)
        #expect(r.peek.count == 5)
        #expect(r.peek.map(\.id) == ["e0", "e1", "e2", "e3", "e4"])
    }

    @Test func allAccountAggregatesSingleAccountFilters() {
        // RED until T005: account == "all" aggregates across accounts; a single
        // account filters to just that account.
        let emails = [
            email("a1", account: "A", folder: "inbox"),
            email("a2", account: "A", folder: "inbox"),
            email("b1", account: "B", folder: "inbox"),
        ]
        let all = InboxGlance.project(emails: emails, account: "all", now: now)
        #expect(all.unread == 3)
        let onlyB = InboxGlance.project(emails: emails, account: "B", now: now)
        #expect(onlyB.unread == 1)
    }

    @Test func inboxZeroIsAllZero() {
        // RED until T005: no unread inbox → (0, 0, []).
        let emails = [
            email("read1", unread: false, folder: "inbox"),
            email("arch1", unread: true, folder: "archive"),
        ]
        let r = InboxGlance.project(emails: emails, account: "A", now: now)
        #expect(r.unread == 0)
        #expect(r.newToday == 0)
        #expect(r.peek.isEmpty)
    }

    @Test func excludesNonInboxAndReadMessages() {
        // RED until T005: messages outside inbox OR already read are excluded entirely.
        let emails = [
            email("i1", unread: true, folder: "inbox", sortDate: now),     // counts
            email("i2", unread: false, folder: "inbox", sortDate: now),    // read → excluded
            email("ar", unread: true, folder: "archive", sortDate: now),   // not inbox → excluded
            email("se", unread: true, folder: "sent", sortDate: now),      // not inbox → excluded
        ]
        let r = InboxGlance.project(emails: emails, account: "A", now: now)
        #expect(r.unread == 1)
        #expect(r.newToday == 1)
        #expect(r.peek.map(\.id) == ["i1"])
    }
}
