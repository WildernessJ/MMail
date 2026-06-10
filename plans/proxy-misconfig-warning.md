# proxy-misconfig-warning Implementation Plan

**Goal:** Surface a display-only advisory warning in the Settings "Image privacy proxy" section when the proxy toggle is ON but `imageProxyConfig` is inert, naming which sub-condition (base URL vs signing secret) is failing — so a silently-misconfigured proxy can never lull the user into a false sense of privacy.

**Architecture:** A new `ProxyConfigState` enum plus a pure `classify(proxyEnabled:proxyBaseURL:secretPresent:)` static live in `MMail/Mail/ProxyConfigState.swift`. The classifier decomposes the `imageProxyConfig` guard chain (`AppModel.swift:934-938`) into one of six states `{disabled, ok, missingURL, invalidURL, urlMissingHost, missingSecret}`, using `Foundation` (`URL`, string trimming) only — no AppModel/WebKit/Keychain/filesystem access. To make the warning and the actual load path single-source-of-truth, `imageProxyConfig` is REFACTORED to derive its validity from `ProxyConfigState.classify(...) == .ok` (computing `secretPresent` via `loadProxySecret()` at the call site, then constructing `ImageProxyConfig` only on `.ok`) — so `imageProxyConfig != nil ⇔ classify(...) == .ok` holds BY CONSTRUCTION, not by two hand-maintained guard copies. This refactor is strictly value-preserving: `imageProxyConfig` returns the identical value for every input. A small SwiftUI warning view in the Settings proxy section renders the non-`.ok` reason; the on-screen render + live-Keychain agreement is the manual SC-001 check. Tests live in `MMailTests/` (fork-local, never goes upstream).

**Test Methodology:** e2e-first

**Test framework:** **Swift Testing** (`import Testing`, `@Suite struct`, `@Test func`, `#expect`) — matches every existing file in `MMailTests/` (e.g. `ReaderImageLoadStateTests.swift`, `ProxySecretStoreTests.swift`). Do NOT use XCTest.

**Pre-flight (handled by `/build`, not a task):** cut branch `feat/proxy-misconfig-warning` off `main` before editing any `*.swift`. Build runs on an Opus subagent; review is opposite-model (Sonnet).

**Command shorthand:**
- BUILD = `xcodebuild -project MMail.xcodeproj -scheme MMail -configuration Debug build CODE_SIGNING_ALLOWED=NO`
- TEST = `xcodebuild test -project MMail.xcodeproj -scheme MMail -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO`
- `xcodegen generate` runs ONLY in tasks adding a new `.swift` file (T001, T002); the regenerated `MMail.xcodeproj/project.pbxproj` (+ any scheme xcshareddata) is committed deliberately in that task's commit. T003–T005 edit existing files only and MUST NOT run `xcodegen generate` (it dirties the tracked `project.pbxproj` for no reason).

---

- [ ] **T001 (SC: 002, 003, 004): Define `ProxyConfigState` types + pure stub** — Create `MMail/Mail/ProxyConfigState.swift` (`import Foundation`):
  - `enum ProxyConfigState: Equatable { case disabled; case ok; case missingURL; case invalidURL; case urlMissingHost; case missingSecret }`.
  - Pure static stub: `static func classify(proxyEnabled: Bool, proxyBaseURL: String, secretPresent: Bool) -> ProxyConfigState` → return `.disabled` (stub; real body in T003).
  - Add a computed convenience the warning view consumes (stub or final — it is a pure derivation off the enum, safe to write now): `var isWarning: Bool { switch self { case .disabled, .ok: return false; default: return true } }`. This is the single "show the warning?" predicate; `isWarning == (state ∈ {missingURL, invalidURL, urlMissingHost, missingSecret})`.
  - No AppModel / WebKit / Keychain imports. `Foundation` only (for `URL`, string trimming).
  - Doc-comment the input contract + the single-source-of-truth role: `secretPresent == (loadProxySecret() != nil)` resolved impurely at the call site (`AppModel.swift:906`); `.ok ⇔ all of imageProxyConfig's guards pass` (`AppModel.swift:934-938`); `imageProxyConfig` will DERIVE its validity from `classify(...) == .ok` (T004), so the two cannot disagree by construction. Sub-condition order MUST mirror the guard short-circuit: `proxyEnabled` → blank URL → unparseable URL → host-less URL → secret.
  - Run: `xcodegen generate && BUILD` Expected: `** BUILD SUCCEEDED **`
  - **Files:** `MMail/Mail/ProxyConfigState.swift`, `MMail.xcodeproj/project.pbxproj`
  - Commit: `git commit -m "feat: ProxyConfigState enum + pure classify stub"`

- [ ] **T002 (SC: 002, 003, 004, 005): Failing Swift Testing suite** — Create `MMailTests/ProxyConfigStateTests.swift` (`import Testing`, `import Foundation`, `@testable import MMail`). Tests assert against the T001 stub so they FAIL (T001 exposes every symbol, so this compiles). NO AppModel/WebKit/Keychain/filesystem access anywhere — only injected `Bool`/`String` values (proving purity, SC-002):
  - **Six-state representatives (SC-003) — one `@Test` per state, asserting the exact case:**
    - `classify(proxyEnabled: false, proxyBaseURL: "anything", secretPresent: true) == .disabled` — toggle off; also assert disabled holds with `proxyBaseURL: ""` / `secretPresent: false` (don't-care inputs).
    - `classify(proxyEnabled: true, proxyBaseURL: "https://worker.example.workers.dev", secretPresent: true) == .ok`.
    - `classify(proxyEnabled: true, proxyBaseURL: "", secretPresent: true) == .missingURL`; also `"   "` (whitespace-only) `== .missingURL`.
    - `classify(proxyEnabled: true, proxyBaseURL: "https://foo bar.com", secretPresent: true) == .invalidURL` — unescaped space in the authority makes `URL(string:)` return nil in this project's Foundation (spec line 26/70). **Test-writing tip (reviewer):** bind `let parsed = URL(string: "https://foo bar.com")` to a LOCAL and `#expect(parsed == nil)` as a sanity precondition so the double-evaluation of `URL(string:)` doesn't silently change semantics; the production classifier likewise evaluates `URL(string:)` ONCE (see T003).
    - `classify(proxyEnabled: true, proxyBaseURL: "not a url", secretPresent: true) == .urlMissingHost` — parses under `URL(string:)` (the embedded space percent-encodes) but `host == nil`.
    - `classify(proxyEnabled: true, proxyBaseURL: "https://worker.example.workers.dev", secretPresent: false) == .missingSecret`.
  - **Short-circuit precedence — URL wins over secret (SC-003 central edge case):** `classify(proxyEnabled: true, proxyBaseURL: "", secretPresent: false) == .missingURL` (NOT `.missingSecret`). Mirrors the guard short-circuiting on URL before the secret guard (`AppModel.swift:936-938`).
  - **Blank-but-present secret treated as missing (spec scenario, line 94):** the classifier takes `secretPresent: Bool`; assert `classify(proxyEnabled: true, proxyBaseURL: validHostURL, secretPresent: false) == .missingSecret` — the blank-secret → `secretPresent == false` resolution is `ProxySecretStore.resolve`'s job at the call site, exercised in `ProxySecretStoreTests`; here we only assert the classifier honors the injected `false`.
  - **SC-004 — pure equivalence to the guard-condition transcription (the anti-drift contract):** iterate a representative input matrix and assert `classify(...).isWarning == (proxyEnabled && !okRef)` AND `(classify(...) == .ok) == okRef`, where `okRef` is a PURE reference transcription of the guard *conditions* computed in the test over the same injected `(proxyEnabled, proxyBaseURL, secretPresent)`:
    ```
    let trimmed = proxyBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
    let parsed = URL(string: trimmed)            // bind to a LOCAL — evaluate URL(string:) ONCE
    let okRef = proxyEnabled
        && !trimmed.isEmpty
        && parsed != nil
        && parsed?.host != nil                    // host != nil (NOT !host.isEmpty) — matches AppModel.swift:937
        && secretPresent
    ```
    Matrix: cross `proxyEnabled ∈ {false, true}` with `proxyBaseURL ∈ {"", "   ", "https://foo bar.com", "not a url", "https://worker.example.workers.dev"}` and `secretPresent ∈ {false, true}` (20 rows). For each row `#expect((classify(...) == .ok) == okRef)` and `#expect(classify(...).isWarning == (proxyEnabled && !okRef))`. This is the SC-004 transcription: the classifier's `.ok` MUST correspond EXACTLY to "all guard conditions pass" — i.e. precisely the inputs that make `imageProxyConfig` non-nil. (Because T004 makes `imageProxyConfig` derive from `classify`, this reference predicate and `imageProxyConfig`'s real check become the same code, so agreement holds by construction.) NOTE: the test does NOT call the live impure `AppModel.imageProxyConfig` (it invokes `loadProxySecret()` → real Keychain + file I/O, un-unit-testable in isolation) — it asserts against this pure transcription instead, per SC-004.
  - **Exactly-one / totality (spec Invariant "Exactly one state"):** the same matrix asserts each call returns a single `ProxyConfigState` case (the `enum`/`switch` makes "two states" unrepresentable; assert membership in the six cases / non-crash for every tuple).
  - Run: `xcodegen generate && TEST` Expected: TEST FAILS (stub returns `.disabled`, so every `proxyEnabled: true` row fails its expected non-disabled state).
  - **Files:** `MMailTests/ProxyConfigStateTests.swift`, `MMail.xcodeproj/project.pbxproj`
  - Commit: `git commit -m "test: failing ProxyConfigState suite (6-state + SC-004 equivalence)"`

- [ ] **T003 (SC: 002, 003, 004, 005): Implement `classify` + commit** — Real body in `MMail/Mail/ProxyConfigState.swift`. Decompose the guard chain in the SAME order as `imageProxyConfig` (`AppModel.swift:934-938`), evaluating `URL(string:)` exactly ONCE:
  ```
  static func classify(proxyEnabled: Bool, proxyBaseURL: String, secretPresent: Bool) -> ProxyConfigState {
      guard proxyEnabled else { return .disabled }
      let trimmed = proxyBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !trimmed.isEmpty else { return .missingURL }
      guard let url = URL(string: trimmed) else { return .invalidURL }
      guard url.host != nil else { return .urlMissingHost }   // host != nil, NOT !host.isEmpty (mirror AppModel.swift:937)
      guard secretPresent else { return .missingSecret }
      return .ok
  }
  ```
  - Use `url.host != nil` (NOT `!host.isEmpty`) so the classifier agrees with `imageProxyConfig` rather than the stricter rule-builder guard (spec line 121-126: practical-not-logical host equivalence). Use `.trimmingCharacters(in: .whitespacesAndNewlines)` (no `.trimmed` helper exists in this codebase).
  - Run: `TEST` Expected: PASS (all `ProxyConfigStateTests` green). Commit `MMail/Mail/ProxyConfigState.swift` only — no new `.swift` files (this edits the existing file); `project.pbxproj` was already committed in T001/T002, so do NOT run `xcodegen generate` here.
  - **Files:** `MMail/Mail/ProxyConfigState.swift`
  - Commit: `git commit -m "feat: implement ProxyConfigState.classify (6-state guard transcription)"`

- [ ] **T004 (SC: 004): Refactor `imageProxyConfig` to derive validity from `classify` (single source of truth, value-preserving)** — In `MMail/State/AppModel.swift`, rewrite the `imageProxyConfig` computed property (`AppModel.swift:933-940`) so its `nil`-vs-non-`nil` decision is delegated to `ProxyConfigState.classify(...) == .ok` — eliminating the second hand-maintained copy of the guard logic. Keep it strictly value-preserving (identical return for every input):
  ```
  var imageProxyConfig: ImageProxyConfig? {
      let secret = loadProxySecret()                              // impure resolve at the call site
      let trimmed = proxyBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
      guard ProxyConfigState.classify(
          proxyEnabled: proxyEnabled,
          proxyBaseURL: proxyBaseURL,
          secretPresent: secret != nil
      ) == .ok else { return nil }
      // .ok guarantees: proxyEnabled, trimmed non-empty, URL parses, host present, secret non-nil.
      // Re-read the same values to BUILD the config (force-unwrap is safe BY the .ok contract).
      return ImageProxyConfig(baseURL: URL(string: trimmed)!, signingSecret: secret!)
  }
  ```
  - **Single-source-of-truth note (load-bearing — do NOT reintroduce a second guard):** the `nil` decision now lives ONLY in `classify`. The force-unwraps are justified by the `.ok` contract (which checks `!trimmed.isEmpty`, `URL(string: trimmed) != nil`, `url.host != nil`, and `secretPresent`). `secretPresent: secret != nil` must match `ProxySecretStore.resolve`'s blank-as-nil semantics: `loadProxySecret()` already returns nil for a blank/whitespace-only secret (`ProxySecretStore.swift:22-30`, `AppModel.swift:906`), so `secret != nil` is exactly the old `let secret = loadProxySecret(), !secret.isEmpty` guard — do NOT add a separate `!secret.isEmpty` check (it would be a redundant second copy; `loadProxySecret` never returns a blank string). Do NOT add any URL/host validity check OUTSIDE `classify`.
  - **Value-preservation is the hard requirement:** for EVERY `(proxyEnabled, proxyBaseURL, secret-state)`, `imageProxyConfig` returns the byte-identical `ImageProxyConfig?` it did before (same `baseURL`, same `signingSecret`, same `nil` cases). The reader (`HTMLMessageView`/`ReaderView`) and the shipped Phase B indicator depend on this — any drift is a regression.
  - Run: `BUILD` Expected: `** BUILD SUCCEEDED **`. Then `TEST` Expected: PASS — the FULL existing suite stays green (`ReaderImageLoadStateTests`, `ProxySecretStoreTests`, `ImageProxyTests`, `ClassifyTests`, etc. exercise `imageProxyConfig`-dependent paths indirectly); green here is the value-preservation guard. The `ProxyConfigStateTests` SC-004 matrix (T002) is the explicit assertion that `classify == .ok` matches the guard-condition transcription that `imageProxyConfig` now consumes.
  - **Files:** `MMail/State/AppModel.swift`
  - Commit: `git commit -m "refactor: imageProxyConfig derives validity from ProxyConfigState.classify (single source of truth, value-preserving)"`

- [ ] **T005 (SC: 001): Render the misconfiguration warning in the Settings proxy section** — In `MMail/Views/SettingsView.swift` "Image privacy proxy" section (`SettingsView.swift:41-85`), compute the state from values already in scope and render an advisory warning when it is one of the four warning states. The view already has `@Environment(\.palette) private var p` (`SettingsView.swift:5`) and `@ObservedObject`/`@EnvironmentObject model` access:
  - Compute the state once: `let proxyState = ProxyConfigState.classify(proxyEnabled: model.proxyEnabled, proxyBaseURL: model.proxyBaseURL, secretPresent: model.hasProxySecret)`. Use `model.hasProxySecret` (= `loadProxySecret() != nil`, `AppModel.swift:925-927`) for `secretPresent` so the warning keys off the SAME resolved secret state `imageProxyConfig` consumes (NOT a second resolve). Because the section re-renders on `model` changes, the warning re-derives as the user edits the URL field (`SettingsView.swift:47-49`) or saves a secret (`SettingsView.swift:69-71`) — SC-001 live-update.
  - When `proxyState.isWarning`, render a visible advisory below the secret field, styled like the existing `proxySecretSaveError` surfacing (`SettingsView.swift:78-82`): warning/danger color `p.danger`, small font, optionally an `Icon(name: "alert", size: ...)` (the `"alert"` icon exists; `p.danger` = the project's danger token, `Theme.swift:65/96`). Message names the failing part and warns images load directly until fixed, e.g.:
    - `.missingURL` / `.invalidURL` / `.urlMissingHost` → "Proxy is on but the base URL is missing or invalid — remote images will load directly (leaking your IP) until you set a valid `https://…` URL." (Copy MAY collapse the three URL states into one message — that's a presentation choice, spec Non-Goal line 168; the classifier keeps them distinct for testability.)
    - `.missingSecret` → "Proxy is on but the signing secret is missing — remote images will load directly (leaking your IP) until you paste the secret and Save."
  - MUST NOT render the secret, its value/presence beyond "missing", or any HMAC material (spec "No secret disclosure"). MAY echo the user-typed base URL for context but is not required to. MUST be absent in `.disabled` and `.ok`. MUST NOT obscure or replace the toggle, URL field, secret field, Save button, or the existing `proxySecretSaveError` text (`SettingsView.swift:78-82`) — render it as an ADDITIONAL line, e.g. directly under the secret-field `VStack` (after `SettingsView.swift:84`) or just below the URL field.
  - **Display-only:** the view MUST NEVER call `setProxyEnabled`, `setProxyBaseURL`, `setProxySecret`, mint/sign a URL, or trigger a fetch — it is a pure read of `model.proxyEnabled` / `model.proxyBaseURL` / `model.hasProxySecret` (spec "Display-only").
  - Run: `BUILD` Expected: `** BUILD SUCCEEDED **`
  - **Manual (SC-001, not automatable):** with the proxy toggle ON — (a) clear the base URL field → the warning appears naming the base URL; (b) set a valid `https://…` host URL but no secret → the warning switches to name the signing secret; (c) with both a valid host URL AND a secret present → no warning. The warning updates live as fields are edited (no Settings reopen). This manual step ALSO owns the live-property agreement the automated suite cannot: confirm the on-screen warning's shown/hidden state matches the LIVE `AppModel.imageProxyConfig` resolved against the real Keychain + fallback-file secret (with a genuinely-stored secret the warning is absent; with the secret removed it appears).
  - **Files:** `MMail/Views/SettingsView.swift`
  - Commit: `git commit -m "feat: Settings image-proxy misconfiguration warning (display-only)"`

- [ ] **T006 (SC: 001–005): Full suite green + commit** — Run the full automated suite and commit any remaining changes.
  - **Coverage disclosure:** SC-002 (purity — injected `Bool`/`String`, no AppModel/WebKit/Keychain/filesystem), SC-003 (six-state representatives + short-circuit precedence), SC-004 (pure equivalence: `classify == .ok` matches the guard-condition transcription, and `isWarning` matches `proxyEnabled && imageProxyConfig == nil`'s logical shape over the matrix), and SC-005 (Swift Testing target) are FULLY automated by `ProxyConfigStateTests`. The value-preservation of the `imageProxyConfig` refactor (T004) is protected by the FULL existing suite staying green plus the SC-004 matrix (`classify == .ok` ⇔ the exact guard conditions `imageProxyConfig` now consumes). SC-001 (on-screen SwiftUI warning + live Keychain/file agreement) is the MANUAL exploration step in `/verify` — a rendered SwiftUI view and live Keychain/file state cannot be asserted by the `MMailTests` target (spec SC-001). The single-source-of-truth invariant means there is exactly ONE guard copy (`ProxyConfigState.classify`); `imageProxyConfig` derives `nil`-vs-non-`nil` from `classify == .ok`, so the warning and the load path cannot silently diverge — confirmed structurally (one classifier) and by the SC-004 equivalence assertion.
  - Run: `TEST` Expected: all automated scenarios PASS (`ProxyConfigStateTests` green; existing suites unaffected — value-preservation confirmed).
  - **Files:** (commit only — no new edits)
