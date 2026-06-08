import Testing
import Foundation
@testable import MMail

/// Property tests for `Privacy.cleanLink` over http(s) URLs only.
@Suite struct CleanLinkProperties {

    private func trackingKeysIn(_ url: URL) -> Set<String> {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        return Set(items.map { $0.name.lowercased() }.filter { Privacy.trackingParams.contains($0) })
    }

    private func nonTrackingItems(_ url: URL) -> [URLQueryItem] {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        return items.filter { !Privacy.trackingParams.contains($0.name.lowercased()) }
    }

    /// Idempotence: cleaning twice equals cleaning once. Per the spec, the
    /// second application short-circuits (no tracking params remain) and returns
    /// its input unchanged, so this is not exposed to re-serialization drift.
    @Test func idempotence() {
        check("cleanLink idempotence", Gen<URL>.httpURL) { url in
            let once = Privacy.cleanLink(url)
            let twice = Privacy.cleanLink(once)
            return once == twice
        }
    }

    /// All known tracking keys are removed. If any survive, fail loudly — do not
    /// weaken the generator.
    @Test func trackingKeysRemoved() {
        check("cleanLink removes tracking keys", Gen<URL>.httpURL) { url in
            let cleaned = Privacy.cleanLink(url)
            return self.trackingKeysIn(cleaned).isEmpty
        }
    }

    /// Every non-tracking query item is retained, and scheme/host/path are
    /// unchanged.
    @Test func nonTrackingAndStructurePreserved() {
        check("cleanLink preserves structure", Gen<URL>.httpURL) { url in
            let cleaned = Privacy.cleanLink(url)
            let beforeC = URLComponents(url: url, resolvingAgainstBaseURL: false)
            let afterC = URLComponents(url: cleaned, resolvingAgainstBaseURL: false)
            guard beforeC?.scheme == afterC?.scheme,
                  beforeC?.host == afterC?.host,
                  beforeC?.path == afterC?.path else { return false }
            // Every non-tracking item from the original must remain.
            let kept = Set((afterC?.queryItems ?? []).map { "\($0.name)=\($0.value ?? "")" })
            for item in self.nonTrackingItems(url) {
                if !kept.contains("\(item.name)=\(item.value ?? "")") { return false }
            }
            return true
        }
    }

    /// Spec "Edge case: components cannot re-serialize".
    ///
    /// The `comps.url ?? url` fallback at `HTMLMessageView.swift:40` is defensive
    /// code that is UNREACHABLE for valid http(s) URLs — removing query items from
    /// a parseable http(s) URL always yields components that re-serialize, so
    /// `comps.url` is never nil and the fallback never fires. We therefore cannot
    /// drive that branch from real input. Instead this locks down the trickiest
    /// *reachable* http(s) shapes (fragments, percent-encoding, all-tracking →
    /// empty query, no query, duplicate tracking keys): cleanLink must not trap,
    /// must strip every tracking key, and must keep every non-tracking item.
    @Test func trickyReachableUrlsAndNilFallbackNote() {
        let cases = [
            "https://example.com",                                   // no query at all
            "https://example.com/p%20s?q=a%20b&utm_source=x",        // percent-encoded path + value
            "https://example.com/path?utm_source=x&fbclid=y",        // all-tracking → empty query result
            "https://example.com?a=1#frag",                          // fragment, no tracking
            "https://example.com?utm_source=x&utm_source=y&q=1#sec", // duplicate tracking keys + fragment
            "http://sub.domain.co.uk/a/b/c?gclid=z&keep=1"
        ]
        for raw in cases {
            guard let url = URL(string: raw) else { Issue.record("bad test URL: \(raw)"); continue }
            let cleaned = Privacy.cleanLink(url) // must not trap
            #expect(trackingKeysIn(cleaned).isEmpty, "tracking key survived in \(raw)")
            let after = URLComponents(url: cleaned, resolvingAgainstBaseURL: false)?.queryItems ?? []
            for item in nonTrackingItems(url) {
                #expect(after.contains { $0.name == item.name && $0.value == item.value },
                        "non-tracking item \(item.name) dropped from \(raw)")
            }
        }
    }
}
