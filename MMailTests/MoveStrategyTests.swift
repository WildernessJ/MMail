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
