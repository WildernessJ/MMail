import Foundation

/// The PURE, injectable core for the trusted-image-sender set: ONE canonical
/// address normalization shared by ADD, CONTAINS, REMOVE, and LISTING, over a
/// caller-supplied `Set<String>`. No stored state (the set is always injected),
/// and `Foundation` only — NO AppModel / UserDefaults / Keychain / WebKit access
/// (purity, SC-002), mirroring the `ProxyConfigState` / `ReaderImageLoadState`
/// house pattern.
///
/// `normalize` IS the single source of truth for the canonical rule: lowercase →
/// trim `.whitespacesAndNewlines` → strip leading/trailing `<>` → re-trim → nil if
/// empty. It is byte-for-byte the body of `AppModel.normalizeAddress`
/// (`AppModel.swift:801-807`); `AppModel.normalizeAddress` DELEGATES here (T004), and
/// `AppModel.isImageTrusted` / `trustImages` / `untrustImages` route their inputs
/// through `contains` / `add` / `remove` (T005). So add / contains / remove /
/// storage agree by construction: the set `isImageTrusted` consults IS the set the
/// Settings list renders and "Stop" removes from.
///
/// `add` requires a non-nil `normalize` result that contains `@` (preserving today's
/// `guard e.contains("@")`, `AppModel.swift:875`); `contains` / `remove` tolerate any
/// case / whitespace / `<>` variant of a stored member. `list` returns the canonical
/// members sorted lexicographic ascending (Swift `Array.sorted()` default `<`) and
/// de-duplicated (the canonical set has no case/whitespace dupes by construction).
enum TrustedSenders {
    /// The canonical normalization rule: lowercase → trim `.whitespacesAndNewlines`
    /// → strip leading/trailing `<>` → re-trim → nil if empty. Byte-for-byte the body
    /// of `AppModel.normalizeAddress` (`AppModel.swift:801-807`).
    static func normalize(_ s: String?) -> String? {
        guard var t = s?.lowercased() else { return nil }
        t = t.trimmingCharacters(in: .whitespacesAndNewlines)
        t = t.trimmingCharacters(in: CharacterSet(charactersIn: "<>"))
        t = t.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }

    /// Insert `raw`'s canonical form. Requires `@` (preserving `AppModel.swift:875`'s
    /// `guard e.contains("@")`); a non-`@` / empty-normalizing input is a no-op.
    /// Returns a NEW set (pure).
    static func add(_ set: Set<String>, _ raw: String) -> Set<String> {
        guard let e = normalize(raw), e.contains("@") else { return set }
        var s = set
        s.insert(e)
        return s
    }

    /// Remove `raw`'s canonical form. Removing an absent / non-normalizing address is
    /// a no-op returning the unchanged set. Returns a NEW set (pure).
    static func remove(_ set: Set<String>, _ raw: String) -> Set<String> {
        guard let e = normalize(raw) else { return set }
        var s = set
        s.remove(e)
        return s
    }

    /// Membership of `raw`'s canonical form. Tolerates any case / whitespace / `<>`
    /// variant of a stored member.
    static func contains(_ set: Set<String>, _ raw: String) -> Bool {
        guard let e = normalize(raw) else { return false }
        return set.contains(e)
    }

    /// Sorted (lexicographic ascending, Swift `Array.sorted()` default `<`),
    /// de-duplicated canonical members. The set is already canonical + de-duplicated
    /// by construction.
    static func list(_ set: Set<String>) -> [String] {
        set.sorted()
    }
}
