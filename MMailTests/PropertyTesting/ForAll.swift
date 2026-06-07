import Testing
import Foundation
@testable import MMail

/// The outcome of a property run. Returning a value (rather than only firing a
/// `#expect`) is what makes the harness itself testable: the self-tests in
/// `ForAllTests` assert on `.passed` / `.failed` directly.
enum PropertyResult: Equatable {
    case passed
    /// A failing run: the (shrunk) counterexample rendered as text, and the seed
    /// that reproduces it.
    case failed(counterexample: String, seed: UInt64)
}

/// Default iteration count for a property run.
let defaultPropertyIterations = 200

/// Run `property` against `count` values drawn from `gen`, seeded by `seed`
/// (default: a value derived from the wall clock so successive unseeded runs
/// vary). On the first input for which `property` returns `false`, shrink that
/// input toward a minimal still-failing case and return it together with `seed`.
///
/// A `property` that throws or otherwise fails to evaluate is NOT caught here:
/// crash-freedom is asserted by the property simply *running* to completion, so
/// a trap in the function under test surfaces as a crashed test process (the
/// spec's accepted signal for crash-freedom regressions).
func forAll<T>(
    _ gen: Gen<T>,
    count: Int = defaultPropertyIterations,
    seed: UInt64? = nil,
    _ property: (T) -> Bool
) -> PropertyResult {
    let actualSeed = seed ?? UInt64.random(in: UInt64.min...UInt64.max)
    var rng = SplitMix64(seed: actualSeed)
    for _ in 0..<count {
        let value = gen.generate(&rng)
        if !property(value) {
            let minimal = shrinkToMinimal(value, gen: gen, property: property)
            return .failed(counterexample: "\(minimal)", seed: actualSeed)
        }
    }
    return .passed
}

/// Greedily shrink `value` using the generator's `shrink`, repeatedly replacing
/// the current failing value with the first strictly-simpler candidate that
/// still fails, until no candidate fails. Bounded so a pathological `shrink`
/// cannot loop forever.
private func shrinkToMinimal<T>(_ value: T, gen: Gen<T>, property: (T) -> Bool) -> T {
    var current = value
    var steps = 0
    let maxSteps = 10_000
    while steps < maxSteps {
        steps += 1
        guard let smaller = gen.shrink(current).first(where: { !property($0) }) else {
            break
        }
        current = smaller
    }
    return current
}

/// Thin wrapper that runs a property and turns a `.failed` result into a
/// `swift-testing` failure whose message carries the counterexample AND the
/// replay seed, satisfying the spec's "every failure is reproducible" invariant.
@discardableResult
func check<T>(
    _ description: String = "property",
    _ gen: Gen<T>,
    count: Int = defaultPropertyIterations,
    seed: UInt64? = nil,
    sourceLocation: SourceLocation = #_sourceLocation,
    _ property: (T) -> Bool
) -> PropertyResult {
    let result = forAll(gen, count: count, seed: seed, property)
    if case let .failed(counterexample, usedSeed) = result {
        Issue.record(
            "\(description) FAILED — counterexample: \(counterexample) | replay seed: \(usedSeed)",
            sourceLocation: sourceLocation
        )
    }
    return result
}
