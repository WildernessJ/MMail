# reader-proxy-indicator Implementation Plan

**Goal:** Surface, for the currently displayed message, which load path its remote images took — No remote images / Blocked / Proxied / Loaded direct — as a read-only, pure-function-derived indicator in the reader's primary card.

**Architecture:** A new `ReaderImageLoadState` enum plus two pure statics live in `MMail/Mail/ReaderImageLoadState.swift`: `hasRemoteImages(in:)` scans `bodyHTML` for an `<img>` whose `src` OR `srcset` carries an `http(s)` ref (reusing `ImageProxy.imgTagRegex`-style scanning, not WebKit), and `classify(hasRemoteImages:showImages:proxyActive:)` maps the three derived booleans to exactly one state. The classifier consumes ONLY the four decision inputs the render path already uses (`email.bodyHTML`, `model.isImageTrusted(email.fromEmail)`, the reader's `loadImages`, `model.imageProxyConfig`) — no AppModel/WebKit/Keychain access — so it can never disagree with `HTMLMessageView`'s Blocked/Proxied/Direct fork. A small SwiftUI indicator view renders the state (icon + label/tooltip) and is wired into `ReaderView`'s primary-card privacy chrome (`ReaderView.swift:289-319`); the on-screen render is the manual SC-001 check. Tests live in `MMailTests/` (fork-local, never goes upstream).

**Test Methodology:** e2e-first

**Test framework:** **Swift Testing** (`import Testing`, `@Suite struct`, `@Test func`, `#expect`) — matches every existing file in `MMailTests/` (e.g. `ProxySecretStoreTests.swift`, `ImageProxyTests.swift`). Do NOT use XCTest.

**Pre-flight (handled by `/build`, not a task):** cut branch `feat/reader-proxy-indicator` off `main` before editing any `*.swift`. Build runs on an Opus subagent; review is opposite-model (Sonnet).

**Command shorthand:**
- BUILD = `xcodebuild -project MMail.xcodeproj -scheme MMail -configuration Debug build CODE_SIGNING_ALLOWED=NO`
- TEST = `xcodebuild test -project MMail.xcodeproj -scheme MMail -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO`
- `xcodegen generate` runs ONLY in tasks adding a new `.swift` file (T001, T002); the regenerated `MMail.xcodeproj/project.pbxproj` (+ any scheme xcshareddata) is committed deliberately in that task's commit. T003–T005 edit existing files only and MUST NOT run `xcodegen generate` (it dirties the tracked `project.pbxproj` for no reason).

---

- [ ] **T001 (SC: 002, 003, 004, 006): Define `ReaderImageLoadState` types + pure stubs** — Create `MMail/Mail/ReaderImageLoadState.swift` (`import Foundation`):
  - `enum ReaderImageLoadState: Equatable { case noRemoteImages; case blocked; case proxied; case loadedDirect }`.
  - Pure static stub: `static func hasRemoteImages(in bodyHTML: String?) -> Bool` → `false`.
  - Pure static stub: `static func classify(hasRemoteImages: Bool, showImages: Bool, proxyActive: Bool) -> ReaderImageLoadState` → `.noRemoteImages`.
  - No AppModel / WebKit / Keychain imports. `Foundation` only (for `NSRegularExpression`).
  - Doc-comment the input contract: `showImages == isImageTrusted(fromEmail) || loadImages`; `proxyActive == (imageProxyConfig != nil)` — mirroring `ReaderView.swift:290-291, 316-317`. This is the shared-decision-inputs invariant: the indicator derives Blocked/Proxied/Direct from the SAME `!showImages` / `proxyConfig != nil` values passed at `ReaderView.swift:316-317`.
  - Run: `xcodegen generate && BUILD` Expected: `** BUILD SUCCEEDED **`
  - **Files:** `MMail/Mail/ReaderImageLoadState.swift`, `MMail.xcodeproj/project.pbxproj`

- [ ] **T002 (SC: 002, 003, 004, 005, 006): Failing Swift Testing suite** — Create `MMailTests/ReaderImageLoadStateTests.swift` (`import Testing`, `import Foundation`, `@testable import MMail`). Tests assert against the T001 stubs so they FAIL (T001 exposes every symbol, so this compiles). NO AppModel/WebKit/Keychain access anywhere — only injected `String?`/`Bool` values (proving purity, SC-002):
  - **`hasRemoteImages` — No remote images (SC-002):** `nil` → false; `""` → false; `"<p>hi</p>"` (no `<img>`) → false; `"<img src=\"cid:logo\">"` (non-http(s) scheme) → false; `"<img src=\"data:image/png;base64,AAA\">"` (non-http(s) scheme) → false; `"<img src=\"/local.png\">"` → false.
  - **`hasRemoteImages` — remote `src` (SC-002):** `"<img src=\"https://t/x.gif\">"` → true; `"<img src='http://t/x'>"` → true (single-quote); case-insensitive TAG + ATTRIBUTE-NAME tokens (HTML tag/attr names are case-insensitive) `"<IMG SRC=\"https://t/x\">"` → true (value stays quoted).
  - **`hasRemoteImages` — privacy-critical `srcset` (SC-002):** `"<img srcset=\"https://tracker/x.gif\">"` (no `src`) → true; `"<img srcset='http://t/x 2x'>"` → true. (This is the false-negative the spec's "srcset-only" scenario forbids.)
  - **`classify` full truth table — all 8 rows (SC-003, SC-004):** iterate every `(hasRemoteImages, showImages, proxyActive)` in `{false,true}^3` and `#expect` the SC-003 expected state per row:
    | hasRemote | showImages | proxyActive | expected |
    |---|---|---|---|
    | false | false | false | `.noRemoteImages` |
    | false | false | true  | `.noRemoteImages` |
    | false | true  | false | `.noRemoteImages` |
    | false | true  | true  | `.noRemoteImages` |
    | true  | false | false | `.blocked` |
    | true  | false | true  | `.blocked` |
    | true  | true  | true  | `.proxied` |
    | true  | true  | false | `.loadedDirect` |
  - **Exactly-one / totality (SC-004):** the same 8-row loop asserts each call returns a single non-nil `ReaderImageLoadState` case (every tuple maps to one of the four; the `switch`-style enum makes "two states" unrepresentable, so totality is the assertable half — assert membership in the four cases).
  - **Load-images transition (SC-005):** holding `hasRemoteImages = true`, flipping `showImages` false→true re-classifies `.blocked` → `.proxied` when `proxyActive = true`, and `.blocked` → `.loadedDirect` when `proxyActive = false`.
  - Run: `xcodegen generate && TEST` Expected: TEST FAILS (stubs return `false` / `.noRemoteImages`, so the `true`/Blocked/Proxied/Direct rows fail).
  - **Files:** `MMailTests/ReaderImageLoadStateTests.swift`, `MMail.xcodeproj/project.pbxproj`

- [ ] **T003 (SC: 002, 003, 004, 005, 006): Implement `ReaderImageLoadState` statics + commit** — Real bodies in `MMail/Mail/ReaderImageLoadState.swift`:
  - `hasRemoteImages(in:)`: guard non-nil non-empty; enumerate `<img …>` start tags with a private `imgTagRegex` (`"<img\\b[^>]*>"`, `.caseInsensitive`) paralleling `ImageProxy.imgTagRegex` (`ImageProxy.swift:76-79`); for each tag, return `true` if EITHER a `src` value OR a `srcset` value holds an `http://`/`https://` ref. Match attr values with a quote-aware regex (capture group for the value, paralleling `ImageProxy.srcAttrRegex` at `ImageProxy.swift:85-88` but adding a separate `srcset` pattern); for `srcset`, an `http(s)` substring anywhere in the (comma-separated) value is sufficient (the candidate list can hold multiple URLs). Trim + lowercase before the `hasPrefix` check. Return `false` if no tag qualifies. Pure, `Foundation`-only, no I/O.
    - **Scope note:** the scan detects QUOTED http(s) `src`/`srcset` values only — this is intentional and consistent with `ImageProxy.rewriteTag`, which likewise only operates on quoted `src` (real HTML-email image refs are universally quoted; unquoted attribute values are out of scope, matching what the proxy machinery itself can act on, so the indicator stays consistent with the render path).
  - `classify(hasRemoteImages:showImages:proxyActive:)`: `guard hasRemoteImages else { return .noRemoteImages }`; `guard showImages else { return .blocked }`; `return proxyActive ? .proxied : .loadedDirect`. (Exactly mirrors the render fork: block when `!showImages` per `ReaderView.swift:316`/`HTMLMessageView.swift:176-183`; proxied-vs-direct per `HTMLMessageView.swift:157-176`.)
  - Run: `TEST` Expected: PASS (all `ReaderImageLoadStateTests` green). Commit `MMail/Mail/ReaderImageLoadState.swift` only — no new `.swift` files (this task edits the existing file), `project.pbxproj` was already committed in T001/T002, so do NOT run `xcodegen generate` here.
  - **Files:** `MMail/Mail/ReaderImageLoadState.swift`
  - Commit: `git commit -m "feat: pure reader image-load-path classifier (proxy/direct/blocked)"`

- [ ] **T004 (SC: 001): Add the indicator view to the reader's primary card** — In `MMail/Views/ReaderView.swift`, inside the `else if let html = email.bodyHTML, !html.isEmpty` branch (`ReaderView.swift:289-319`), compute the state from the values ALREADY in scope and render an indicator that sits with the existing privacy chrome:
  - Reuse the in-scope locals: `let trusted = model.isImageTrusted(email.fromEmail)` and `let showImages = loadImages || trusted` (already at `ReaderView.swift:290-291`); compute `let imageState = ReaderImageLoadState.classify(hasRemoteImages: ReaderImageLoadState.hasRemoteImages(in: html), showImages: showImages, proxyActive: model.imageProxyConfig != nil)`. Use `model.imageProxyConfig != nil` for `proxyActive` (NOT a second resolve) so the indicator keys off the exact value passed to `HTMLMessageView` at `ReaderView.swift:317`.
  - Add a private `@ViewBuilder` indicator (e.g. `imageLoadIndicator(_ state:)`) rendering icon + label per state, matching the existing chrome style (`Icon(name:size:)` + `Text(.font(.system(size: 12)))` + palette tokens `p.brandBlue`/`p.fg3`, as the block banner does at `ReaderView.swift:294-299`):
    - `.loadedDirect` — distinct WARNING presentation (e.g. `"shield.slash"`/warning icon, palette warning/red token, label like `"Images loaded directly from sender"`), visually distinct from `.proxied` (SC-001 distinctness requirement, spec "Direct-load state is shown distinctly").
    - `.proxied` — privacy-positive presentation (e.g. shield icon + `"Images loaded via privacy proxy"`, optionally naming the proxy host via `model.imageProxyConfig?.baseURL.host`). MUST NOT render any asset URL, the `s=` HMAC param, or the secret (spec "names the proxy without exposing the secret").
    - `.blocked` — neutral; the existing block banner already conveys this. Indicator may stay absent in `.blocked` (the banner at `ReaderView.swift:292-315` covers it) OR show a quiet "Remote images blocked" chip — pick absent-in-`.blocked` to avoid duplicating the banner.
    - `.noRemoteImages` — neutral or absent (spec "neutral or absent"); MUST NOT claim proxied/direct. Pick absent.
  - Placement: render the indicator inside the existing `else if` block so it appears with the primary card's privacy region (`ReaderView.swift:292-318`), WITHOUT obscuring or replacing the `"Load images"` / `"Always"` controls (`ReaderView.swift:301-307`) — e.g. directly above the `HTMLMessageView(...)` at `ReaderView.swift:316`, after the optional block banner. The indicator re-derives every body render, so it tracks the `loadImages` false→true tap (`ReaderView.swift:301`) with no message reselect (SC-005 on-screen). Scope to the primary card only — do NOT touch thread peek-cards (`ReaderView.swift:600-631`).
  - Run: `BUILD` Expected: `** BUILD SUCCEEDED **`
  - Manual (SC-001, not automatable): with the proxy configured+active, open a trusted-sender message with remote images → **Proxied** indicator shows on screen; toggle the proxy off (or clear the base URL) and reopen → **Loaded direct** indicator shows. A plain-text / no-remote-img message shows no proxied/direct claim. Tapping "Load images" on a blocked message flips the indicator to Proxied/Direct without reselecting.
  - **Files:** `MMail/Views/ReaderView.swift`
  - Commit: `git commit -m "feat: reader proxy-vs-direct image-load indicator (display-only)"`

- [ ] **T005 (SC: 001–006): Full suite green + commit** — Run the full automated suite and commit any remaining changes.
  - **Coverage disclosure:** SC-002 (purity), SC-003 (8-row truth table), SC-004 (exactly-one/totality), and SC-005 (Load-images transition) are FULLY automated by the `ReaderImageLoadStateTests` suite (injected values, no AppModel/WebKit/Keychain). SC-001 (on-screen SwiftUI indicator + Proxied↔Direct toggle distinctness) is the MANUAL exploration step in `/verify` — a rendered SwiftUI indicator cannot be asserted by the `MMailTests` target (spec SC-001/SC-006). The known indicator/reality divergence on `WKContentRuleList` compile failure (proxy rule fails → loads direct while indicator says Proxied) is a DISCLOSED, out-of-MVP non-goal (spec Non-Goals) — not handled, not tested. **Detection scope:** `hasRemoteImages` detects QUOTED http(s) `src`/`srcset` values only (the proxy-consistent scope — `ImageProxy.rewriteTag` likewise acts only on quoted `src`); unquoted attribute values are out of scope and intentionally not detected.
  - Run: `TEST` Expected: all automated scenarios PASS (`ReaderImageLoadStateTests` green; existing suites unaffected).
  - **Files:** (commit only — no new edits)
