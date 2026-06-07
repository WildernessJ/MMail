import Testing
@testable import MMail

/// Property tests for `AppModel.dedupById`.
@Suite struct DedupByIdProperties {

    /// No duplicate ids; first-occurrence order preserved; result is a
    /// subsequence of the input; count equals the number of distinct ids.
    @Test func uniquenessOrderSubsequenceCardinality() {
        check("dedupById uniqueness/order/cardinality", Gen<[Email]>.emailList) { list in
            let out = AppModel.dedupById(list)
            let outIds = out.map { $0.id }

            // No duplicate ids.
            if Set(outIds).count != outIds.count { return false }

            // Cardinality: one entry per distinct input id.
            let distinctInput = Set(list.map { $0.id })
            if outIds.count != distinctInput.count { return false }

            // First-occurrence order: the surviving ids appear in the same order
            // as their first appearance in the input.
            var firstSeen: [String] = []
            var seen = Set<String>()
            for e in list where seen.insert(e.id).inserted { firstSeen.append(e.id) }
            if outIds != firstSeen { return false }

            // Subsequence: result ids are a subsequence of input ids (since they
            // are exactly the first-occurrence order, this holds, but check
            // explicitly that result ids all came from the input).
            return Set(outIds).isSubset(of: distinctInput)
        }
    }

    /// Idempotence: deduping a deduped list is a no-op.
    @Test func idempotence() {
        check("dedupById idempotence", Gen<[Email]>.emailList) { list in
            let once = AppModel.dedupById(list)
            let twice = AppModel.dedupById(once)
            return once.map { $0.id } == twice.map { $0.id }
        }
    }

    /// Edge case: a list where most/all entries share one id returns without
    /// trapping and yields exactly one entry per distinct id.
    @Test func manyDuplicatesDoNotTrap() {
        // Force heavy id collision: a list of N emails all sharing one id.
        let allSame = Gen<[Email]>(
            generate: { rng in
                let n = Int(rng.next() % 30)
                return (0..<n).map { _ in
                    Email(id: "dup", account: "a", from: "you", subject: "s",
                          preview: "p", body: "b", time: "t", day: "today", folder: "inbox")
                }
            }
        )
        check("dedupById many duplicates", allSame) { list in
            let out = AppModel.dedupById(list)
            // Either empty input -> empty, or exactly one "dup".
            return out.count == (list.isEmpty ? 0 : 1)
        }
    }
}
