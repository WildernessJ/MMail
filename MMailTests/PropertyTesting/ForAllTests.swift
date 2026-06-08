import Testing
@testable import MMail

/// Self-tests for the forAll harness, asserting on the result-returning API so
/// the harness's own failure/replay/shrink behavior is verified without relying
/// on a swift-testing failure firing.
@Suite struct ForAllTests {

    /// Scenario: All inputs satisfy the property → `.passed`, no failure.
    @Test func alwaysTrueProperty() {
        let r = forAll(Gen<Int>.intNonNegative(), seed: 1) { _ in true }
        #expect(r == .passed)
    }

    /// Scenario: A violated property is reported with a concrete counterexample
    /// and the RNG seed.
    @Test func violatedPropertyReportsCounterexampleAndSeed() {
        // Always-false property: the very first input is a counterexample.
        let r = forAll(Gen<Int>.intNonNegative(), seed: 12345) { _ in false }
        guard case let .failed(counterexample, seed) = r else {
            Issue.record("expected .failed, got \(r)")
            return
        }
        // Always-false ⇒ the reported counterexample shrinks all the way to the
        // simplest value, so assert the minimized value, not just non-empty.
        #expect(counterexample == "0")
        #expect(seed == 12345)
    }

    /// Scenario: Replay by seed reproduces the same first counterexample.
    @Test func replayBySeedReproducesCounterexample() {
        // Property fails for large values; pin the seed so two runs draw the
        // same sequence and shrink to the same minimal failing input.
        let seed: UInt64 = 0xABCDEF
        let p: (Int) -> Bool = { $0 < 100 }
        let r1 = forAll(Gen<Int>.intNonNegative(below: 1000), seed: seed, p)
        let r2 = forAll(Gen<Int>.intNonNegative(below: 1000), seed: seed, p)
        #expect(r1 == r2)
        if case .passed = r1 {
            Issue.record("expected the seeded run to find a failure")
        }
    }

    /// Scenario: Edge case — shrinking reduces a failing input. Property `n < 5`
    /// over non-negative Int must report the minimal counterexample `5`.
    @Test func shrinkingYieldsMinimalCounterexample() {
        let r = forAll(Gen<Int>.intNonNegative(below: 1000), seed: 42) { $0 < 5 }
        guard case let .failed(counterexample, _) = r else {
            Issue.record("expected .failed, got \(r)")
            return
        }
        #expect(counterexample == "5")
    }
}
