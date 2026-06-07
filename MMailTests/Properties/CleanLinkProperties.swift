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
}
