import Testing
@testable import MMail

@Suite struct SeededRNGTests {

    /// Same seed produces an identical sequence (the property that makes replay
    /// possible).
    @Test func sameSeedSameSequence() {
        var a = SplitMix64(seed: 0xDEADBEEF)
        var b = SplitMix64(seed: 0xDEADBEEF)
        let seqA = (0..<32).map { _ in a.next() }
        let seqB = (0..<32).map { _ in b.next() }
        #expect(seqA == seqB)
    }

    /// Different seeds produce different sequences (otherwise the seed would be
    /// meaningless for distinguishing runs).
    @Test func differentSeedsDifferentSequences() {
        var a = SplitMix64(seed: 1)
        var b = SplitMix64(seed: 2)
        let seqA = (0..<32).map { _ in a.next() }
        let seqB = (0..<32).map { _ in b.next() }
        #expect(seqA != seqB)
    }

    /// The generator retains its seed for reporting.
    @Test func retainsSeed() {
        let g = SplitMix64(seed: 42)
        #expect(g.seed == 42)
    }
}
