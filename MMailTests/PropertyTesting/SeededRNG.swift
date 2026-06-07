import Foundation

/// A deterministic, seedable random number generator.
///
/// Swift's `SystemRandomNumberGenerator` is not seedable, so property-test
/// replay (the spec's "reproduce a failure from a printed seed" requirement)
/// is impossible with it. SplitMix64 is a tiny public-domain algorithm
/// (Steele, Lea & Flood, 2014) that produces a well-distributed 64-bit
/// sequence from a single 64-bit seed, with no third-party dependency.
struct SplitMix64: RandomNumberGenerator {
    /// The initial seed, retained so callers can report it for replay.
    let seed: UInt64
    private var state: UInt64

    init(seed: UInt64) {
        self.seed = seed
        self.state = seed
    }

    mutating func next() -> UInt64 {
        state = state &+ 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}
