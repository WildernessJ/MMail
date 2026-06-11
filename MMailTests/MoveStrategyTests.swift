import Foundation
import Testing
@testable import MMail

/// Unit tests for the pure `AppModel.orderNewerFirst(aDate:aUID:aID:…)` seam:
/// the date-first message comparator that fixes the unified "All inboxes"
/// mis-ordering (UID is per-mailbox, so it cannot order across accounts).
/// Orders newest-first by `sortDate` desc, then `uid` desc, then `id` asc; a
/// `nil` date is treated as `.distantPast`. Reference dates are built from a
/// fixed epoch offset (never `Date()`) so the suite is deterministic.
/// SC-002/003/004.
@Suite struct DateSortOrdering {
    // Fixed reference instants (no `Date()`): t0 < t1 < t2.
    static let t0 = Date(timeIntervalSince1970: 1_700_000_000) // earlier
    static let t1 = Date(timeIntervalSince1970: 1_750_000_000) // later
    static let t2 = Date(timeIntervalSince1970: 1_760_000_000) // latest

    /// Cross-account: a far-lower UID with the newer date still sorts first —
    /// date beats UID across the per-mailbox UID ranges (the core bug).
    @Test func crossAccountOrdersByDateNotUID() {
        #expect(AppModel.orderNewerFirst(
            aDate: Self.t1, aUID: 7800, aID: "m#INBOX#7800",
            bDate: Self.t0, bUID: 130000, bID: "g#INBOX#130000") == true)
    }

    /// Single-account normal delivery: date increases with UID, so the result
    /// matches the prior UID-descending order.
    @Test func singleAccountNormalMatchesUIDDescending() {
        #expect(AppModel.orderNewerFirst(
            aDate: Self.t1, aUID: 20, aID: "m#INBOX#20",
            bDate: Self.t0, bUID: 10, bID: "m#INBOX#10") == true)
    }

    /// Single-account moved/delayed: A has the higher UID but the OLDER date;
    /// B (lower UID, newer date) must sort first → orderNewerFirst(A,B) == false.
    @Test func movedDelayedSingleAccountSortsByDate() {
        #expect(AppModel.orderNewerFirst(
            aDate: Self.t0, aUID: 7900, aID: "m#INBOX#7900",
            bDate: Self.t1, bUID: 7800, bID: "m#INBOX#7800") == false)
    }

    /// A `nil` date sinks below any dated mail regardless of UID.
    @Test func nilDateSinksBelowDated() {
        #expect(AppModel.orderNewerFirst(
            aDate: Self.t1, aUID: 7800, aID: "m#INBOX#7800",
            bDate: nil, bUID: 131000, bID: "g#INBOX#131000") == true)
    }

    /// Equal dates → tiebreak by UID descending.
    @Test func equalDateTiebreaksByUID() {
        #expect(AppModel.orderNewerFirst(
            aDate: Self.t1, aUID: 50, aID: "m#INBOX#50",
            bDate: Self.t1, bUID: 40, bID: "m#INBOX#40") == true)
    }

    /// Equal date AND equal UID → tiebreak by id ascending.
    @Test func equalDateAndUIDTiebreaksByID() {
        #expect(AppModel.orderNewerFirst(
            aDate: Self.t1, aUID: 50, aID: "a",
            bDate: Self.t1, bUID: 50, bID: "b") == true)
    }

    /// Strict weak ordering over a mixed set (dated + nil-date, two disjoint UID
    /// ranges): sorting completes without trapping and is deterministic across
    /// repeated sorts.
    @Test func strictWeakOrderingDeterministic() {
        let items: [(Date?, UInt32?, String)] = [
            (Self.t2, 7800, "m#INBOX#7800"),
            (Self.t0, 130000, "g#INBOX#130000"),
            (nil, 131000, "g#INBOX#131000"),
            (Self.t1, 7801, "m#INBOX#7801"),
            (Self.t1, 98000, "g#INBOX#98000"),
            (nil, 7500, "m#INBOX#7500"),
            (Self.t0, 7799, "m#INBOX#7799"),
        ]
        let cmp: ((Date?, UInt32?, String), (Date?, UInt32?, String)) -> Bool = {
            AppModel.orderNewerFirst(aDate: $0.0, aUID: $0.1, aID: $0.2,
                                     bDate: $1.0, bUID: $1.1, bID: $1.2)
        }
        let first = items.sorted(by: cmp)
        let second = items.sorted(by: cmp)
        // Correct order: date desc (t2 > t1 > t0 > nil/distantPast), then uid
        // desc within equal dates, then id asc. This exercises cross-account
        // interleave, nil-date sink, and both tiebreaks at once.
        let expected = ["m#INBOX#7800",   // t2
                        "g#INBOX#98000", "m#INBOX#7801",     // t1, uid desc
                        "g#INBOX#130000", "m#INBOX#7799",    // t0, uid desc
                        "g#INBOX#131000", "m#INBOX#7500"]    // nil → distantPast, uid desc
        #expect(first.map { $0.2 } == expected)
        #expect(first.map { $0.2 } == second.map { $0.2 })  // deterministic / stable
    }
}

/// Unit tests for the pure `IMAPService.moveStrategy(capabilities:)` decision
/// function — the only unit-testable seam of the IMAP MOVE fallback (SC-002,
/// SC-004). Live COPY/EXPUNGE network behaviour and capability capture are
/// manual-exploration; this suite locks the policy that gates them.
@Suite struct MoveStrategyTests {
    @Test func nativeMoveWhenMovePresent() {
        #expect(IMAPService.moveStrategy(capabilities: ["MOVE"]) == .nativeMove)
    }

    @Test func copyFallbackWhenUidplusPresentAndMoveAbsent() {
        #expect(IMAPService.moveStrategy(capabilities: ["UIDPLUS"]) == .copyThenUidExpunge)
    }

    @Test func nativeMoveWinsWhenBothPresent() {
        #expect(IMAPService.moveStrategy(capabilities: ["MOVE", "UIDPLUS"]) == .nativeMove)
    }

    @Test func unsupportedWhenEmpty() {
        #expect(IMAPService.moveStrategy(capabilities: []) == .unsupported)
    }

    @Test func unsupportedWhenNeitherPresent() {
        #expect(IMAPService.moveStrategy(capabilities: ["IDLE"]) == .unsupported)
    }

    @Test func caseInsensitiveLowercaseMove() {
        #expect(IMAPService.moveStrategy(capabilities: ["move"]) == .nativeMove)
    }

    @Test func caseInsensitiveMixedCaseUidplus() {
        #expect(IMAPService.moveStrategy(capabilities: ["Uidplus"]) == .copyThenUidExpunge)
    }

    @Test func caseInsensitiveMixedCombined() {
        #expect(IMAPService.moveStrategy(capabilities: ["move", "UIDPLUS"]) == .nativeMove)
    }
}

/// Unit tests for the pure `AppModel.expungedWindowUIDs(loaded:present:range:)`
/// seam: the policy that decides which locally-loaded UIDs an incremental sync
/// must drop because the server's FLAGS response over the queried range no
/// longer returned them (expunged / moved out of the folder externally).
/// Live merge wiring in `mergeIncremental` is manual-exploration; this suite
/// locks the reconciliation policy that gates it. Backlog #11.
@Suite struct ExpungeReconciliation {

    /// The core bug: a UID inside the queried range that the server no longer
    /// returns has been expunged externally → it must be dropped locally.
    @Test func dropsUIDInRangeAbsentFromServer() {
        let expunged = AppModel.expungedWindowUIDs(
            loaded: [10, 11, 12], present: [10, 12], range: 10...12)
        #expect(expunged == [11])
    }

    /// UIDs the server still reports are retained.
    @Test func keepsUIDsStillPresent() {
        let expunged = AppModel.expungedWindowUIDs(
            loaded: [10, 11, 12], present: [10, 11, 12], range: 10...12)
        #expect(expunged.isEmpty)
    }

    /// A freshly-appended message above the queried flag range was never part
    /// of the FLAGS query, so its absence from `present` must NOT drop it.
    /// (Guards against deleting just-arrived mail.)
    @Test func keepsNewUIDAboveRange() {
        let expunged = AppModel.expungedWindowUIDs(
            loaded: [10, 11, 99], present: [10, 11], range: 10...11)
        #expect(expunged.isEmpty)
    }

    /// Whole-window deletion: if the server returns nothing in range, every
    /// in-range UID is expunged. (Caller only invokes this when a flag query
    /// actually ran, so an empty `present` means real deletions, not a no-op.)
    @Test func dropsAllWhenServerReturnsNoneInRange() {
        let expunged = AppModel.expungedWindowUIDs(
            loaded: [10, 11, 12], present: [], range: 10...12)
        #expect(expunged == [10, 11, 12])
    }
}

/// Unit tests for the pure `AppModel.backfillWindowUIDs(loaded:present:range:limit:)`
/// seam: the inverse of `expungedWindowUIDs`. It decides which server-present
/// UIDs inside the loaded window are missing locally and must be re-fetched
/// (the holes), newest-first and capped per cycle. Live merge wiring in
/// `insertBackfill`/`fetchWindowBackfill` is manual-exploration; this suite
/// locks the pure selection policy. Backfill feature (backlog #1 follow-up).
@Suite struct BackfillReconciliation {

    /// The core case: a hole inside the window is selected, present − loaded,
    /// newest-first; no loaded UID appears in the result.
    @Test func holeInsideWindowSelectedNewestFirst() {
        let backfill = AppModel.backfillWindowUIDs(
            loaded: [7866, 7830, 7524],
            present: [7524, 7600, 7700, 7830, 7866],
            range: 7524...7866, limit: 10)
        #expect(backfill == [7700, 7600])
        let loaded: Set<UInt32> = [7866, 7830, 7524]
        #expect(Set(backfill).isDisjoint(with: loaded))
    }

    /// The cap truncates the result to the newest missing UIDs.
    @Test func capTruncatesToNewestMissing() {
        let backfill = AppModel.backfillWindowUIDs(
            loaded: [7866],
            present: [7000, 7100, 7200, 7300, 7866],
            range: 7000...7866, limit: 2)
        #expect(backfill == [7300, 7200])
        #expect(backfill.count == 2)
    }

    /// Nothing missing → empty result (idempotent at the seam).
    @Test func nothingMissingIsEmpty() {
        let backfill = AppModel.backfillWindowUIDs(
            loaded: [7866, 7830, 7524],
            present: [7524, 7830, 7866],
            range: 7524...7866, limit: 10)
        #expect(backfill.isEmpty)
    }

    /// A present UID above the range top is ignored (it belongs to the
    /// new-message path, not backfill); an in-range hole is still returned.
    /// NOTE: the spec/plan's literal data (`present:[7400, 7900]`, `range:
    /// 7524...7866` ⇒ `[7400]`) is internally inconsistent — `7400 < 7524` is
    /// BELOW the range bottom, so `range.contains(7400)` is false and the
    /// plan's own impl body excludes it; that also violates the spec invariant
    /// "backfill MUST NEVER fetch UIDs older than oldest loaded" (oldest loaded
    /// here is 7866). The in-range present UID is moved to `7600` (clearly
    /// inside `7524...7866`) so the case actually exercises its stated intent:
    /// above-range `7900` ignored, in-range hole `7600` backfilled.
    @Test func presentUIDAboveRangeIgnored() {
        let backfill = AppModel.backfillWindowUIDs(
            loaded: [7866],
            present: [7600, 7900],
            range: 7524...7866, limit: 10)
        #expect(backfill == [7600])
        #expect(!backfill.contains(7900))
    }

    /// A hole entirely below `oldestLoaded` is not backfilled — that is the job
    /// of load-older / full reload, not backfill.
    @Test func holeBelowWindowNotSelected() {
        let backfill = AppModel.backfillWindowUIDs(
            loaded: [7800, 7866],
            present: [7500, 7800, 7866],
            range: 7800...7866, limit: 10)
        #expect(backfill.isEmpty)
    }

    /// Backfill (present − loaded) and expunge (loaded − present) over the same
    /// window are disjoint by construction: a UID is never both fetched and
    /// dropped in the same cycle. `7524` is expunged (loaded, gone on server),
    /// `7600` is backfilled (server-present, missing locally).
    @Test func backfillAndExpungeAreDisjoint() {
        let loaded: [UInt32] = [7524, 7700, 7866]
        let present: Set<UInt32> = [7600, 7700, 7866]
        let range: ClosedRange<UInt32> = 7524...7866
        let backfill = AppModel.backfillWindowUIDs(
            loaded: loaded, present: present, range: range, limit: 10)
        let expunged = AppModel.expungedWindowUIDs(
            loaded: loaded, present: present, range: range)
        #expect(backfill == [7600])
        #expect(expunged == [7524])
        #expect(Set(backfill).isDisjoint(with: expunged))
    }

    // MARK: - newMailHighWater (high-water scoped to new arrivals)

    /// A cycle that backfills historical mail (no new arrivals) does NOT
    /// advance the high-water mark — the high-water is computed from the
    /// new-arrival channel only, which is empty here.
    @Test func backfillDoesNotAdvanceHighWater() {
        #expect(AppModel.newMailHighWater(current: 7866, newArrivalUIDs: []) == 7866)
    }

    /// A genuine new arrival above the current mark advances the high-water.
    @Test func newArrivalAdvancesHighWater() {
        #expect(AppModel.newMailHighWater(current: 7866, newArrivalUIDs: [7900]) == 7900)
    }

    /// New arrivals strictly below the current mark never move it (max
    /// semantics): only a UID above current advances. This is the property that
    /// keeps a backfilled (always-below-afterUID) UID from advancing the mark —
    /// even if it were ever mis-routed into the new-arrival list.
    @Test func newArrivalsBelowCurrentDoNotAdvance() {
        #expect(AppModel.newMailHighWater(current: 7866, newArrivalUIDs: [7000, 7100]) == 7866)
    }

    /// Steady-state idempotence at the seam level: when the cache already
    /// equals the server window and no new mail arrived, backfill adds nothing
    /// and the high-water does not move.
    @Test func steadyStateCycleIsNoOp() {
        let backfill = AppModel.backfillWindowUIDs(
            loaded: [7700, 7830, 7866],
            present: [7700, 7830, 7866],
            range: 7700...7866, limit: 200)
        #expect(backfill.isEmpty)
        #expect(AppModel.newMailHighWater(current: 7866, newArrivalUIDs: []) == 7866)
    }
}
