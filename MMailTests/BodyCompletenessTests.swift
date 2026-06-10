import Testing
@testable import MMail

/// Unit tests for the pure body-completeness decision core (`BodyFetch`), the
/// unit-testable seam of the body-truncation fix (SC-002, SC-004). The live IMAP
/// fetch is manual-exploration; this suite locks the policy that gates whether a
/// prefetched body is complete and whether opening a message must refetch.
@Suite struct BodyCompletenessTests {

    // MARK: - isComplete (SC-004): capped ⇒ returned < cap; uncapped ⇒ always

    @Test func underCapIsComplete() {
        // Server returned fewer bytes than the cap → the whole message fit.
        #expect(BodyFetch.isComplete(returnedBytes: 1_024, byteLimit: 65_536) == true)
    }

    @Test func atCapIsNotComplete() {
        // Returned exactly the cap → possibly truncated → treat as not complete.
        #expect(BodyFetch.isComplete(returnedBytes: 65_536, byteLimit: 65_536) == false)
    }

    @Test func overCapIsNotComplete() {
        // Defensive: a server returning more than asked is still not provably whole.
        #expect(BodyFetch.isComplete(returnedBytes: 70_000, byteLimit: 65_536) == false)
    }

    @Test func uncappedIsAlwaysComplete() {
        // No cap → the whole message was requested → complete regardless of size.
        #expect(BodyFetch.isComplete(returnedBytes: 5_000_000, byteLimit: nil) == true)
    }

    @Test func uncappedZeroBytesStillComplete() {
        // An empty body fetched uncapped is still a complete (empty) body.
        #expect(BodyFetch.isComplete(returnedBytes: 0, byteLimit: nil) == true)
    }

    // MARK: - needsFullFetch (SC-002): fetch unless loaded AND complete

    @Test func absentBodyNeedsFetch() {
        #expect(BodyFetch.needsFullFetch(bodyLoaded: false, bodyComplete: nil) == true)
    }

    @Test func absentBodyEvenIfFlaggedCompleteNeedsFetch() {
        // No body loaded at all → must fetch even if a stale complete flag exists.
        #expect(BodyFetch.needsFullFetch(bodyLoaded: false, bodyComplete: true) == true)
    }

    @Test func loadedButIncompleteNeedsFetch() {
        // The truncated-preview case: loaded but explicitly not complete.
        #expect(BodyFetch.needsFullFetch(bodyLoaded: true, bodyComplete: false) == true)
    }

    @Test func loadedLegacyUnknownNeedsFetch() {
        // Legacy cache (flag absent) → treat as not-complete → fetch on open.
        #expect(BodyFetch.needsFullFetch(bodyLoaded: true, bodyComplete: nil) == true)
    }

    @Test func loadedAndCompleteSkipsFetch() {
        // The warm fast path: loaded AND complete → no refetch.
        #expect(BodyFetch.needsFullFetch(bodyLoaded: true, bodyComplete: true) == false)
    }
}
