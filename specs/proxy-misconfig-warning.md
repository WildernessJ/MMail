# Settings Image-Proxy Misconfiguration Warning Specification

## Purpose

The Settings "Image privacy proxy" section SHALL surface a clear, advisory warning when the proxy toggle is ON but the proxy is **non-functional** — so the user is not silently lulled into a false sense of privacy. Today, when `proxyEnabled == true` but `AppModel.imageProxyConfig` resolves to `nil` (because the base URL is blank, unparseable, or host-less, OR the signing secret is missing/unresolvable), the app silently falls back to **direct** image loading (`HTMLMessageView.swift` direct branch): the user believes remote images are routed through the proxy, but every image leaks their IP to the sender's origin. This feature adds a **display-only** warning, named down to WHICH sub-condition is failing (URL vs secret), at the natural place in the Settings proxy section. It changes NO image-loading behavior, mints no URLs, and reads/writes no settings — it is a pure read of state the app already holds.

## Invariants

- **Warning ⇔ proxy-enabled-but-inert.** The warning MUST be shown EXACTLY when `proxyEnabled == true` AND `imageProxyConfig == nil`, and MUST be hidden otherwise (proxy disabled, OR `imageProxyConfig != nil`). This is the central consistency invariant: the warning MUST NEVER claim a problem while `imageProxyConfig` is non-nil (would falsely alarm a working proxy), and MUST NEVER stay silent while `proxyEnabled && imageProxyConfig == nil` (the very leak this feature exists to flag). The warning is therefore a *re-derivation of the same inert condition* `imageProxyConfig` already encodes — not a second, independently-computed notion of "is the proxy working" that could disagree with it.
- **Single source of truth — no divergent copy of the validity logic.** The implementation MUST NOT maintain a second, independently-edited copy of the URL/secret validity decision that could silently drift from `imageProxyConfig`. The "is this `(proxyEnabled, proxyBaseURL, secretPresent)` config valid" decision MUST have a SINGLE source of truth consumed by BOTH `imageProxyConfig` and the classifier — e.g. a shared pure predicate that both call, or `imageProxyConfig` deriving its validity from the classifier's `.ok` result — so that `imageProxyConfig != nil` and `classify(...) == .ok` cannot disagree *by construction*, not merely by both being tested. (Exact mechanism — shared predicate vs. `imageProxyConfig` consuming the classifier — is a plan decision.) This anti-drift requirement exists precisely BECAUSE this feature was prompted by a silently-misconfigured proxy falling back to direct loading: two hand-maintained copies of the guard logic would reintroduce exactly that class of silent inconsistency, where the warning and the actual load path disagree. NOTE: this single-source constraint is the one allowed touch of `imageProxyConfig`'s internals (refactoring its validity check to share one source); it changes NO observable image-loading behavior — `imageProxyConfig` returns the same value for every input — and is the bounded exception to the "No change to `imageProxyConfig`" non-goal.
- **Pure classifier, no I/O.** The warning state MUST be computed by a PURE classifier over injected inputs — `proxyEnabled: Bool`, the raw `proxyBaseURL: String`, and a `secretPresent: Bool` (whether `loadProxySecret()` would return a non-nil/non-blank value). The classifier MUST perform NO AppModel, WebKit, Keychain, or filesystem access. `Foundation` (`URL`, string trimming) only — mirroring the `ReaderImageLoadState.classify` house pattern (`ReaderImageLoadState.swift:113`). The one impure step (calling `loadProxySecret()` to obtain `secretPresent`) lives at the call site that feeds the classifier, NOT inside it.
- **Classifier sub-condition order MUST mirror the guard short-circuit.** The classifier MUST decompose the inert state using the SAME ordered guard chain as `imageProxyConfig` (`AppModel.swift:934-938`): check `proxyEnabled` first, then the URL chain (blank → unparseable → host-less), then the secret. When a string fails BOTH the URL chain AND the secret is also absent, the classifier MUST report the URL reason (the guard short-circuits on URL first, so the user fixes URL before the secret check is even reached). This guarantees the named reason matches the FIRST thing the user must fix.
- **Display-only.** The warning MUST NEVER trigger a fetch, mint or sign a URL, change `proxyEnabled`, change `proxyBaseURL`, write the secret, or alter any image-load path. It is advisory chrome.
- **No secret disclosure.** The warning MUST NEVER render the signing secret, the secret's presence-or-value beyond a boolean "missing", or any HMAC material. It MAY echo the (user-typed, non-sensitive) base URL string for context, but is not required to.
- **Exactly one state.** For any `(proxyEnabled, proxyBaseURL, secretPresent)` tuple the classifier MUST return exactly one state from the enumeration below — never zero, never two.

## Requirements

### Requirement: Classify the proxy configuration into one named state

A pure classifier SHALL map `(proxyEnabled: Bool, proxyBaseURL: String, secretPresent: Bool)` to exactly one state, decomposing the `imageProxyConfig` guard chain (`AppModel.swift:934-938`) into the user-actionable reason. The states are:

- **disabled** — `proxyEnabled == false`. The proxy toggle is off; direct loading is the user's explicit choice. No warning. (Not-applicable; the other two inputs are don't-care.)
- **ok** — `proxyEnabled == true` AND the base URL trims non-empty AND `URL(string:)` parses it AND `url.host != nil` AND `secretPresent == true`. The proxy is functional (`imageProxyConfig != nil`). No warning.
- **missingURL** — `proxyEnabled == true` AND `proxyBaseURL` is empty or whitespace-only (fails `!trimmed.isEmpty`, `AppModel.swift:936`). Reason: the base URL is missing.
- **invalidURL** — `proxyEnabled == true` AND the trimmed URL is non-empty but `URL(string:)` returns nil (fails `let url = URL(string: trimmed)`, `AppModel.swift:937`). Reason: the base URL can't be parsed. *(Reachable, not merely defensive: in this project's Foundation, a string with an unescaped space in the authority such as `"https://foo bar.com"` makes `URL(string:)` return nil — empirically verified `swift -e 'import Foundation; print(URL(string: "https://foo bar.com") as Any)'` → `nil`. Other inputs, like a leading/embedded space `"a b c"`, instead percent-encode and parse to a non-nil URL with `host == nil`, landing in `urlMissingHost`; the distinguishing factor is whether the space falls in the authority/host position.)*
- **urlMissingHost** — `proxyEnabled == true` AND `URL(string:)` parses but `url.host == nil` (fails `url.host != nil`, `AppModel.swift:937`). Reason: the base URL has no host (e.g. a bare path or scheme-only string). *(Practical note: `URL(string:)` is permissive — most malformed-looking inputs parse but yield `host == nil`, so this is the dominant "bad URL" reason in practice; `invalidURL` is comparatively rare.)*
- **missingSecret** — `proxyEnabled == true` AND the URL chain fully passes (non-empty, parseable, host present) AND `secretPresent == false` (`loadProxySecret()` would return nil/blank — neither Keychain nor fallback file holds a non-blank secret; fails `let secret = loadProxySecret(), !secret.isEmpty`, `AppModel.swift:938`). Reason: the signing secret is missing.

The four warning states are `missingURL`, `invalidURL`, `urlMissingHost`, `missingSecret`. The warning is shown iff the state is one of these four; equivalently iff `proxyEnabled == true && imageProxyConfig == nil`.

#### Scenario: Toggle off is the disabled state, no warning

- **GIVEN** `proxyEnabled == false`
- **WHEN** the classifier runs (any `proxyBaseURL`, any `secretPresent`)
- **THEN** the state is **disabled**
- **AND** no warning is shown

#### Scenario: Fully configured proxy is the ok state, no warning

- **GIVEN** `proxyEnabled == true`
- **AND** `proxyBaseURL == "https://worker.example.workers.dev"` (parses, host present)
- **AND** `secretPresent == true`
- **WHEN** the classifier runs
- **THEN** the state is **ok**
- **AND** no warning is shown
- **AND** the state agrees with `imageProxyConfig != nil` for the same inputs

#### Scenario: Enabled with blank URL warns about the missing URL

- **GIVEN** `proxyEnabled == true`
- **AND** `proxyBaseURL == ""` (or whitespace-only)
- **AND** `secretPresent == true`
- **WHEN** the classifier runs
- **THEN** the state is **missingURL**
- **AND** the warning names the base URL as the missing part

#### Scenario: Enabled with a parseable-but-host-less URL warns about the host

- **GIVEN** `proxyEnabled == true`
- **AND** `proxyBaseURL == "not a url"` (parses under `URL(string:)`, but `host == nil`)
- **AND** `secretPresent == true`
- **WHEN** the classifier runs
- **THEN** the state is **urlMissingHost**
- **AND** the warning names the base URL as the problem

#### Scenario: Enabled with an unparseable URL warns about the invalid URL

- **GIVEN** `proxyEnabled == true`
- **AND** `proxyBaseURL == "https://foo bar.com"` — a string that makes `URL(string:)` return nil (unescaped space in the authority; empirically verified nil in this project's Foundation)
- **AND** `secretPresent == true`
- **WHEN** the classifier runs
- **THEN** the state is **invalidURL**
- **AND** the warning names the base URL as the problem

#### Scenario: Enabled with a valid URL but no secret warns about the secret

- **GIVEN** `proxyEnabled == true`
- **AND** `proxyBaseURL == "https://worker.example.workers.dev"` (parses, host present)
- **AND** `secretPresent == false`
- **WHEN** the classifier runs
- **THEN** the state is **missingSecret**
- **AND** the warning names the signing secret as the missing part

#### Scenario: Edge case: both URL and secret bad reports the URL first

- **GIVEN** `proxyEnabled == true`
- **AND** `proxyBaseURL == ""` (blank)
- **AND** `secretPresent == false`
- **WHEN** the classifier runs
- **THEN** the state is **missingURL** (NOT **missingSecret**)
- **AND** this mirrors the `imageProxyConfig` guard short-circuit, which fails on the URL before the secret guard is reached (`AppModel.swift:936-938`), so the user is told to fix the URL — the first blocker — first

#### Scenario: Edge case: enabled, valid URL, blank-but-present secret string treated as missing

- **GIVEN** `proxyEnabled == true`
- **AND** `proxyBaseURL` is valid with a host
- **AND** the only stored secret is whitespace-only, so `loadProxySecret()` resolves it as nil and `secretPresent == false`
- **WHEN** the classifier runs
- **THEN** the state is **missingSecret**
- **AND** this matches `imageProxyConfig`'s `!secret.isEmpty` guard (`AppModel.swift:938`) and `ProxySecretStore.resolve`'s trim-then-blank-check (`ProxySecretStore.swift:22-30`)

### Requirement: Warning agrees with imageProxyConfig

The warning's shown/hidden decision SHALL be logically equivalent to `proxyEnabled && imageProxyConfig == nil`, derived from the SAME guard inputs `imageProxyConfig` consumes, so the two can never disagree about whether the proxy is inert.

#### Scenario: No warning whenever the proxy config is non-nil

- **GIVEN** any inputs for which `imageProxyConfig != nil` (necessarily `proxyEnabled == true`, valid URL with host, secret present)
- **WHEN** the classifier runs on those same inputs
- **THEN** the state is **ok**
- **AND** no warning is shown

#### Scenario: Warning shown whenever enabled and config is nil

- **GIVEN** any inputs with `proxyEnabled == true` for which `imageProxyConfig == nil`
- **WHEN** the classifier runs on those same inputs
- **THEN** the state is one of the four warning states
- **AND** a warning is shown

#### Scenario: Edge case: practical-not-logical host equivalence

- **GIVEN** the classifier checks `URL(string:)` then `url.host != nil` — the SAME guard as `imageProxyConfig` (`AppModel.swift:937`)
- **WHEN** a (Foundation-practically-unreachable) input yielded a non-nil but empty-string host
- **THEN** `imageProxyConfig` would still treat it as a valid host (it guards `url.host != nil`, NOT `!host.isEmpty`)
- **AND** the classifier MUST use the identical `url.host != nil` check (not `!host.isEmpty`) so it agrees with `imageProxyConfig` rather than the stricter rule-building guard (`HTMLMessageView` proxy-rule path guards `!host.isEmpty`). This subtlety is documented so a reviewer can confirm the classifier mirrors `imageProxyConfig`, not the rule builder — the two are practically but not logically equivalent.

### Requirement: Render the warning in the Settings proxy section

The Settings "Image privacy proxy" section SHALL render a visible advisory warning when the computed state is one of the four warning states, naming which part (base URL vs signing secret) is failing, placed within that section near the relevant field, and styled as a warning/danger affordance (consistent with the existing `proxySecretSaveError` surfacing at `SettingsView.swift:78-82`). The warning MUST be absent in the **disabled** and **ok** states. It MUST NOT obscure or replace the toggle, URL field, secret field, Save button, or the existing `proxySecretSaveError` text.

#### Scenario: Warning appears when the section renders in a warning state

- **GIVEN** the Settings "Image privacy proxy" section is displayed
- **AND** the proxy is enabled but inert (e.g. URL set, no secret → **missingSecret**)
- **WHEN** the section renders
- **THEN** a visible warning communicates that the proxy is enabled but not functional
- **AND** it names the signing secret as the missing part
- **AND** it warns that images will load directly until fixed

#### Scenario: No warning in the ok and disabled states

- **GIVEN** the proxy is either fully configured (**ok**) or toggled off (**disabled**)
- **WHEN** the section renders
- **THEN** no misconfiguration warning is shown

#### Scenario: Warning updates as the user edits the fields

- **GIVEN** the warning is showing **missingURL** (enabled, blank URL)
- **WHEN** the user types a valid `https://…` URL with a host into the base URL field (and a secret is present)
- **THEN** the warning disappears (state becomes **ok**) without leaving the Settings view
- **AND** if instead the URL is fixed while the secret is still missing, the warning switches to name the secret (**missingSecret**)

## Success Criteria

- **SC-001** *(manual)*: With the proxy toggle ON, the on-screen Settings "Image privacy proxy" section shows the misconfiguration warning when (a) the base URL field is cleared and when (b) the URL is valid but no secret is set; the warning names the correct missing part in each case; and the warning disappears once both a valid host URL and a secret are present. This manual exploration ALSO owns the LIVE-property agreement that the automated suite cannot: it confirms the on-screen warning's shown/hidden state matches the actual `AppModel.imageProxyConfig` resolved against the real Keychain and fallback-file secret state (e.g. with a genuinely-stored secret the warning is absent; with the secret removed it appears) — the only point at which the live, impure `imageProxyConfig` (real Keychain + file I/O) is exercised against the warning. This is an on-screen SwiftUI render check — a manual-exploration step, explicitly NOT part of the automated suite (SC-005), since a rendered SwiftUI view and live Keychain/file state cannot be asserted by the test target.
- **SC-002**: A pure classifier maps `(proxyEnabled, proxyBaseURL, secretPresent)` to one of `{disabled, ok, missingURL, invalidURL, urlMissingHost, missingSecret}`, exercised with injected `Bool`/`String` values and NO AppModel / WebKit / Keychain / filesystem access (proving purity — a classifier that touched any of those would fail this test).
- **SC-003**: The classifier is exercised over a representative case for EACH of the six states, asserting: `proxyEnabled == false → disabled`; enabled + valid host URL + secret → **ok**; enabled + blank URL → **missingURL**; enabled + unparseable URL → **invalidURL**; enabled + parseable host-less URL → **urlMissingHost**; enabled + valid URL + no secret → **missingSecret**. The blank-URL case is asserted with `secretPresent == false` as well, confirming **missingURL** wins over **missingSecret** (guard short-circuit order, the central edge case).
- **SC-004** *(automated, pure)*: The warning-shown predicate (state ∈ the four warning states) is logically equivalent to `proxyEnabled && imageProxyConfig == nil` across the asserted inputs: every **ok**/**disabled** input yields no warning, every enabled-but-inert input yields a warning, and the classifier's URL/host check uses `url.host != nil` (matching `imageProxyConfig`, `AppModel.swift:937`). This is verified by asserting that the pure `classify(proxyEnabled:proxyBaseURL:secretPresent:)` agrees, for each injected input, with a PURE reference evaluation of the guard *conditions* — i.e. the boolean `proxyEnabled && !proxyBaseURL.trimmed.isEmpty && URL(string: trimmed) != nil && URL(string: trimmed)?.host != nil && secretPresent`, computed in the test over the same injected `(proxyEnabled, proxyBaseURL, secretPresent)`. The automated test does NOT call the live impure `AppModel.imageProxyConfig` (which invokes `loadProxySecret()` → real Keychain + filesystem I/O and is therefore un-unit-testable in isolation); it asserts against this pure transcription of the guard conditions instead. The classifier's `.ok` state MUST correspond EXACTLY to "all guard conditions pass" — i.e. precisely the inputs that would make `imageProxyConfig` non-nil given the same `(proxyEnabled, proxyBaseURL, secretPresent)`. (Because of the single-source-of-truth invariant, this reference predicate and `imageProxyConfig`'s real check are the same code, so agreement holds by construction, not just on the asserted sample.) Confirming the classifier's `.ok`/non-`.ok` matches the LIVE `imageProxyConfig` against real Keychain/file state is NOT part of this automated test — that live-property agreement is the manual SC-001 exploration.
- **SC-005**: All automated scenarios above pass under the `MMailTests` target using **Swift Testing** (`import Testing`, `@Suite`, `@Test`, `#expect`) — NOT XCTest. SC-001 is excluded (manual on-screen verification).

## Non-Goals

- **Display-only; no behavior change and no remediation affordance.** Decision/assumption: surfacing the misconfiguration is the whole MVP. This feature adds NO "fix it for me" button, does not auto-disable the toggle when inert, does not auto-populate a URL, and does not change any image-load path. The user reads the warning and edits the existing fields themselves. (A reviewer may challenge whether an auto-disable or a one-tap remediation is warranted; the assumption here is that silently flipping the user's toggle is worse than an advisory.)
- **Not the reader proxy-vs-direct indicator (feature B, already shipped).** That indicator reports the realized load path of the **current message** in the reader; this warning diagnoses, in **Settings**, *why the proxy is inert*. They are distinct surfaces. This spec adds nothing to `ReaderImageLoadState` or the reader.
- **Not trusted-sender management (feature D, future).** No viewing/adding/removing of trusted-image senders.
- **No network probe / liveness check.** Decision/assumption: "functional" means *configured correctly* (`imageProxyConfig != nil`), NOT *the Worker is reachable and the secret is accepted*. The warning does NOT issue a request to the proxy URL to confirm it responds or that the secret matches `PROXY_SECRET`. A correctly-configured-but-down or wrong-secret Worker is out of scope (it would surface as proxy 4xx/5xx at image-load time, not here). (Reviewer may challenge whether a reachability check adds enough value to justify the network call and latency in Settings.)
- **No collapsing of the distinct URL reasons.** Decision/assumption: `missingURL`, `invalidURL`, and `urlMissingHost` are kept as separate classifier states because the guard chain genuinely distinguishes them, even though the on-screen copy MAY collapse all three into a single "the base URL is missing or invalid" message. The classifier preserves the distinction for testability; the UI copy granularity is a presentation choice, not a behavioral contract. (Reviewer may argue for fewer states if the UI never differentiates them.)
- **No *behavioral* change** to `imageProxyConfig`, `ProxySecretStore`, `Keychain`, `ImageProxy`, the URL-signing contract, or the Cloudflare Worker. The warning is a strictly additive read. The ONE permitted exception is the anti-drift refactor in the Invariants (extracting `imageProxyConfig`'s URL/secret validity check into a single source of truth shared with the classifier): this is a non-behavioral refactor — `imageProxyConfig` MUST return the identical value for every input — added solely so the warning and the config cannot silently diverge. No other edit to these components is in scope.
- **No persistence or telemetry.** The state is computed for display and never stored, logged, or transmitted.
