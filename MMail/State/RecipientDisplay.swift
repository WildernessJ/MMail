import Foundation

/// Pure, SwiftUI-free recipient-collapse seam (Piece C / SC-003). Given a full
/// recipient list and a fixed limit, computes the shown subset and the overflow
/// count for the reader header's `To:` / `Cc:` first-N + `+N` expander. No
/// SwiftUI or model dependency, so the collapse decision is unit-testable in
/// isolation (mirrors `AppModel.orderNewerFirst` / `EmailSort` / `LayoutSizing`).
enum RecipientDisplay {
    /// Splits `all` into the first `limit` recipients (`shown`) and the count of
    /// the remainder (`overflow`). When `all.count <= limit`, `shown == all` and
    /// `overflow == 0`. `limit` is clamped to be non-negative.
    static func collapsed(_ all: [String], limit: Int) -> (shown: [String], overflow: Int) {
        let cap = max(0, limit)
        let shown = Array(all.prefix(cap))
        let overflow = max(0, all.count - cap)
        return (shown: shown, overflow: overflow)
    }
}
