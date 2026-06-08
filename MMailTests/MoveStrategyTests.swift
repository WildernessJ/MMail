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
