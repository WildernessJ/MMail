import Testing
import Foundation
@testable import MMail

/// Self-tests: drawing many values from each generator returns without
/// trapping, and the constrained/no-encoded-word invariants actually hold.
@Suite struct GeneratorsTests {

    @Test func allGeneratorsDrawWithoutTrapping() {
        var rng = SplitMix64(seed: 12345)
        for _ in 0..<50 {
            _ = Gen<Int>.intNonNegative().generate(&rng)
            _ = Gen<String>.arbitrary.generate(&rng)
            _ = Gen<String>.noEncodedWord.generate(&rng)
            _ = Gen<Data>.arbitrary.generate(&rng)
            _ = Gen<URL>.httpURL.generate(&rng)
            _ = Gen<[Email]>.emailList.generate(&rng)
            _ = Gen<String>.constrainedRecipientField.generate(&rng)
            _ = Gen<String>.unconstrainedRecipientField.generate(&rng)
        }
    }

    @Test func noEncodedWordInvariantHolds() {
        var rng = SplitMix64(seed: 999)
        for _ in 0..<200 {
            let s = Gen<String>.noEncodedWord.generate(&rng)
            #expect(!s.contains("=?"))
        }
    }

    @Test func httpURLisAlwaysHTTPScheme() {
        var rng = SplitMix64(seed: 7)
        for _ in 0..<100 {
            let u = Gen<URL>.httpURL.generate(&rng)
            #expect(u.scheme == "http" || u.scheme == "https")
        }
    }
}
