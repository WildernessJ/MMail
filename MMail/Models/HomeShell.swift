import Foundation

/// The six toggleable Home widgets. The `date` case names the top-left "your day"
/// slot, NOT the literal date content, so sub-feature #3 (Date → Calendar) reuses
/// the same visibility key without a migration. See specs/home-shell.md Non-Goals.
enum HomeWidget: String, CaseIterable {
    case date, weather, inboxGlance, people, journal, todo

    /// The namespaced `UserDefaults` key backing this widget's visibility, e.g.
    /// `mmail.home.show.inboxGlance`. Namespacing keeps these additive alongside
    /// the existing `mmail.*` layout keys.
    var defaultsKey: String { "mmail.home.show.\(rawValue)" }
}

/// Per-widget Home visibility, persisted additively. Each flag defaults ON when its
/// key is absent (the `object(forKey:) as? Bool ?? true` pattern at
/// `LayoutSizing.swift:96`), so a fresh or upgraded install shows every widget.
struct HomeWidgetVisibility: Equatable {
    var date: Bool
    var weather: Bool
    var inboxGlance: Bool
    var people: Bool
    var journal: Bool
    var todo: Bool

    /// STUB (T001): returns all-on; real absent-key-defaults-ON load lands in T003.
    static func load(_ d: UserDefaults) -> HomeWidgetVisibility {
        HomeWidgetVisibility(date: true, weather: true, inboxGlance: true,
                             people: true, journal: true, todo: true)
    }

    /// STUB (T001): no-op; real persistence lands in T003.
    func persist(_ d: UserDefaults) {}

    /// STUB (T001): ergonomic access by widget; real get/set lands in T003.
    subscript(_ w: HomeWidget) -> Bool {
        get { true }
        set {}
    }
}

/// The pure projection an Inbox-glance view renders: the unread total, a "new today"
/// subset count, and the ≤5 newest unread messages to peek at.
struct InboxGlanceResult: Equatable {
    let unread: Int
    let newToday: Int
    let peek: [Email]

    static func == (lhs: InboxGlanceResult, rhs: InboxGlanceResult) -> Bool {
        lhs.unread == rhs.unread && lhs.newToday == rhs.newToday
            && lhs.peek.map(\.id) == rhs.peek.map(\.id)
    }
}

/// A pure, deterministic read-only projection over `[Email]` for the Inbox-glance
/// widget. `now` is injected so the "new today" computation is testable without the
/// device clock.
enum InboxGlance {
    /// STUB (T001): returns zero-value result; real projection lands in T005.
    static func project(emails: [Email], account: String, now: Date) -> InboxGlanceResult {
        InboxGlanceResult(unread: 0, newToday: 0, peek: [])
    }
}
