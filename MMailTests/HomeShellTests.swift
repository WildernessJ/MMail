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
