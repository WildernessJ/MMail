import Testing
@testable import MMail

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
}
