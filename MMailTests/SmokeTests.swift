import Testing
@testable import MMail

/// Smoke test: proves the MMailTests bundle is wired into the scheme and that
/// `@testable import MMail` resolves. If this does not execute, the scheme's
/// test target wiring is wrong (a green run with zero tests is a failure here).
@Suite struct Smoke {
    @Test func ok() {
        #expect(Bool(true))
    }
}
