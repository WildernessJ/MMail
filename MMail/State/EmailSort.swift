import Foundation

/// Pure, SwiftUI-free sort seam for the mail list. Maps a (key, direction) pair
/// to a comparator over `Email`, a group-by-day flag, and the ordered day-bucket
/// keys, with no SwiftUI or `AppModel` dependency so every decision is
/// unit-testable in isolation (mirrors `AppModel.orderNewerFirst` / `LayoutSizing`).

/// The sort key the mail list orders on.
enum SortKey: String, CaseIterable {
    case date
    case sender
    case subject
}

/// The sort direction. `forward` is the "natural" direction for the key
/// (Date: newest-first; Sender/Subject: A–Z); `reverse` is its negation.
enum SortDirection: String, CaseIterable {
    case forward
    case reverse
}

/// A unified, persisted list-sort selection (key + direction). String-
/// `RawRepresentable` for UserDefaults persistence using a `"<key>.<direction>"`
/// encoding. `ListSort.default` (= Date/forward) reproduces the pre-feature
/// newest-first behavior exactly.
struct ListSort: RawRepresentable, Equatable {
    var key: SortKey
    var direction: SortDirection

    init(_ key: SortKey, _ direction: SortDirection) {
        self.key = key
        self.direction = direction
    }

    /// The pre-feature default: Date, newest-first. A missing or unparseable
    /// persisted value resolves to this (see `init?(rawValue:)`), so the inbox
    /// renders exactly as it did before the sort control existed.
    static let `default` = ListSort(.date, .forward)

    var rawValue: String { "\(key.rawValue).\(direction.rawValue)" }

    init?(rawValue: String) {
        let parts = rawValue.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2,
              let k = SortKey(rawValue: String(parts[0])),
              let d = SortDirection(rawValue: String(parts[1])) else { return nil }
        self.key = k
        self.direction = d
    }
}

/// Pure sort decisions for the mail list. All `static`, SwiftUI-free.
enum EmailSort {

    // MARK: - Derived keys (pure, from `Email` fields only)

    /// The sender sort key: the sender's display name if non-empty, else the
    /// from-address, else the empty string — lowercased for case-insensitive
    /// comparison. Derived purely from `Email.fromName`/`fromEmail` (NOT
    /// `resolvedSender`, which pulls in `SampleData`).
    static func senderKey(_ e: Email) -> String {
        let name = e.fromName.map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
        if !name.isEmpty { return name.lowercased() }
        let addr = e.fromEmail.map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
        return addr.lowercased()
    }

    /// The subject sort key: the subject lowercased, with a single leading
    /// `Re:` / `Fwd:` (any case, optional surrounding whitespace) stripped, so
    /// a reply groups with its original.
    static func subjectKey(_ e: Email) -> String {
        var s = e.subject.trimmingCharacters(in: .whitespaces)
        for prefix in ["re:", "fwd:"] {
            if s.lowercased().hasPrefix(prefix) {
                s = String(s.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
                break
            }
        }
        return s.lowercased()
    }

    // MARK: - Comparator

    /// The comparator over `Email` for the given sort. A valid strict weak
    /// ordering for every (key, direction): the primary key is total via the
    /// `Date?`→`.distantPast` / `nil`-string handling, and `uid` then `id`
    /// give a deterministic, total tie-break so `sort` never traps.
    static func comparator(for sort: ListSort) -> (Email, Email) -> Bool {
        switch sort.key {
        case .date:
            switch sort.direction {
            case .forward:
                // Byte-identical to the pre-feature newest-first order.
                return AppModel.isNewerFirst
            case .reverse:
                // Negated: oldest-first WITHIN a section. Swap operands so the
                // primary (date) axis flips, while the uid/id tie-breaks still
                // resolve deterministically (also flipped, but total).
                return { a, b in AppModel.isNewerFirst(b, a) }
            }
        case .sender:
            return keyedComparator(direction: sort.direction, key: senderKey)
        case .subject:
            return keyedComparator(direction: sort.direction, key: subjectKey)
        }
    }

    /// A strict-weak-ordering comparator on a derived `String` key, with `uid`
    /// then `id` as deterministic tie-breaks. `reverse` negates the key
    /// comparison only; the tie-breaks stay deterministic (forward) so equal-key
    /// elements always order identically regardless of direction, keeping the
    /// relation a valid strict weak ordering.
    private static func keyedComparator(direction: SortDirection,
                                        key: @escaping (Email) -> String) -> (Email, Email) -> Bool {
        return { a, b in
            let ka = key(a), kb = key(b)
            if ka != kb {
                return direction == .forward ? (ka < kb) : (ka > kb)
            }
            let ua = a.uid ?? 0, ub = b.uid ?? 0
            if ua != ub { return ua > ub }
            return a.id < b.id
        }
    }

    // MARK: - Grouping decisions

    /// Whether the result groups by day-section headers. True only for Date;
    /// Sender and Subject render a flat list.
    static func groupsByDay(for sort: ListSort) -> Bool {
        sort.key == .date
    }

    /// The day-bucket keys in render order. The fixed
    /// `["today","yesterday","earlier","snoozed"]` for everything EXCEPT
    /// Date/reverse, which reverses the date timeline (`earlier → yesterday →
    /// today`) while keeping `snoozed` pinned last (snoozed is excluded from the
    /// date timeline in both directions). This seam OWNS bucket order; the
    /// comparator OWNS within-section order — independent axes, no double-reverse.
    static func orderedSections(for sort: ListSort) -> [String] {
        let dateTimeline = ["today", "yesterday", "earlier"]
        let snoozed = "snoozed"
        if sort.key == .date && sort.direction == .reverse {
            return dateTimeline.reversed() + [snoozed]
        }
        return dateTimeline + [snoozed]
    }
}
