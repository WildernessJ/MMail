import Testing
@testable import MMail

/// Minimal T004 smoke: a trivially-true property run through `check` passes and
/// returns `.passed`. (The full forAll scenario coverage lives in ForAllTests.)
@Suite struct ForAllSmokeTests {
    @Test func trivialTruePropertyPasses() {
        let r = check("always true", Gen<Int>.intNonNegative()) { _ in true }
        #expect(r == .passed)
    }
}
