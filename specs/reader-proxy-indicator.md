# Reader Proxy-vs-Direct Indicator Specification

## Purpose

The reader SHALL surface, for the **currently displayed** message, which load path its remote images took — **proxied** (rewritten to signed Cloudflare-Worker URLs), **loaded direct** (fetched straight from the sender's origin, leaking the user's IP and an open-signal), or **no remote images / blocked** (nothing was fetched from a remote origin) — so the user can read the per-message privacy posture at a glance. This is a **read-only** indicator: it reflects the decision already made by the existing render path (`ReaderView` → `HTMLMessageView` → `ImageProxy`); it changes no load behavior, mints no URLs, and toggles no settings.

## Invariants

- The indicator MUST be a **pure function of its four inputs** — `email.bodyHTML`, `model.isImageTrusted(email.fromEmail)`, the reader's local `loadImages` state, and `model.imageProxyConfig`. These are exactly the **decision inputs** the render path consumes to pick a load path, so the indicator can never *disagree* with `HTMLMessageView` about Blocked vs Proxied vs Direct. The invariant is **shared decision inputs**, NOT identical computation: the indicator derives `hasRemoteImages` from `bodyHTML` (one of its inputs) via a static HTML scan that the render path does NOT itself perform — `ReaderView.swift:289` instantiates `HTMLMessageView` for ANY non-empty `bodyHTML` with no has-remote-images gate. The indicator MUST NOT introduce a second, independently-computed notion of "is this proxied" that could disagree with what `HTMLMessageView` actually rendered: it MUST derive Blocked/Proxied/Direct from the same `blockRemote` (`= !showImages`) / `proxyConfig` values passed in at `ReaderView.swift:316-317`. (Today the proxied-vs-direct fork lives at `HTMLMessageView.swift:157-176`.)
- The indicator MUST classify into exactly one of the four mutually-exclusive states defined below for any given (message, settings, load-state) tuple — never zero, never two.
- The indicator MUST NEVER itself trigger a remote fetch, mint a signed URL, rewrite HTML, or read/write the signing secret. It is display-only. (It MAY call `model.imageProxyConfig`, which already resolves the secret as a side-effecting read, but it MUST NOT pass any asset URL to `ImageProxy`.)
- The indicator MUST NEVER display the signing secret, the proxy base URL's query/signature, or any asset URL. The proxy state may name the proxy host (already user-configured, non-sensitive) but MUST NOT reveal the HMAC `s=` parameter.
- The indicator state MUST update when the inputs change within the same message — specifically when the user taps "Load images" (flipping `loadImages` false→true) the state MUST re-evaluate (e.g. Blocked → Proxied or Blocked → Direct) without a message reselect.
- The indicator MUST be scoped to the **primary** message card only (the `bodyHTML` rendered at `ReaderView.swift:289-318`). Thread peek-cards do not render remote HTML and are out of scope.

## Requirements

### Requirement: Four mutually-exclusive load-path states

The reader SHALL compute exactly one of four states for the displayed message's primary body, from the inputs the render path already consumes. The states and their decision rule (mirroring `ReaderView.swift:289-318` and `HTMLMessageView.load` at `HTMLMessageView.swift:142-184`) are:

- **No remote images** (`hasRemoteImages == false`) — the body has no remote image reference to load. `hasRemoteImages` is DERIVED purely from `email.bodyHTML`: it is **true** when `bodyHTML` is non-empty AND contains at least one `<img>` tag whose `src` **OR** `srcset` attribute holds a remote (`http://` / `https://`) reference; it is **false** otherwise. So the state is **No remote images** when `bodyHTML` is nil/empty (a plain-text message rendered at `ReaderView.swift:320-328`, where `HTMLMessageView` is never instantiated), OR when `bodyHTML` is non-empty but no `<img>` carries a remote `src`/`srcset`. The `srcset` scan is privacy-critical: in direct-load mode `<img srcset="https://tracker/x.gif">` (with no `src`) actually fetches the remote asset, so classifying it as "No remote images" would be a privacy-DANGEROUS false negative (claiming safe while it leaked). In this state nothing remote is or would be fetched regardless of trust/load settings. *(Caveat — direction of error is SAFE: in **proxy** mode `ImageProxy.rewriteTag` only rewrites `src`, never `srcset` (`ImageProxy.swift:81-88, 173-202`), so srcset images are not proxied — the block-then-allow rule BLOCKS them (the allow-rule only un-blocks the proxy host). A srcset-only message classified **Proxied** therefore slightly over-states proxying, but always toward MORE privacy, never less: blocked > proxied > direct, and the indicator never under-reports a leak. Note also this scan flags more than the existing block-banner `Privacy.trackerCount` (`HTMLMessageView.swift:8`, `<img src>` only) — an intentional err-toward-flagging discrepancy.)*
- **Blocked** — the body has remote images but they were NOT loaded: `showImages == false` (i.e. `!isImageTrusted(fromEmail) && !loadImages`), so `HTMLMessageView` is rendered with `blockRemote == true` and the standalone block-all content rule (`blockRules` at `HTMLMessageView.swift:101-103`, compiled and installed at `HTMLMessageView.swift:177-183`). No remote fetch occurred.
- **Proxied** — images were shown AND a proxy is active: `showImages == true` AND `model.imageProxyConfig != nil`. `HTMLMessageView` rewrites `<img src>` to signed proxy URLs behind the proxy-origin allow-rule (`HTMLMessageView.swift:157-171`). Remote image fetches hit only the proxy host, not the sender's origin.
- **Loaded direct** — images were shown AND no proxy is active: `showImages == true` AND `model.imageProxyConfig == nil`. `HTMLMessageView` loads remote `<img src>` straight from origin (`HTMLMessageView.swift:175-176`). This is the IP/open-signal-leaking path.

The state is a pure classification: given the four inputs it SHALL always pick the one state matching the render path's actual branch.

#### Scenario: Plain-text message has no remote images

- **GIVEN** the selected message's `bodyHTML` is nil (plain-text body only)
- **WHEN** the reader classifies the load path
- **THEN** the state is **No remote images**
- **AND** the state does not depend on trust, `loadImages`, or proxy settings

#### Scenario: HTML message with no remote img references

- **GIVEN** the message's `bodyHTML` is non-empty but no `<img>` tag has a remote `src` OR `srcset` (`http`/`https`)
- **WHEN** the reader classifies the load path
- **THEN** the state is **No remote images**

#### Scenario: srcset-only remote image is NOT classified as No remote images

- **GIVEN** the message's `bodyHTML` contains `<img srcset="https://tracker/x.gif">` with no remote `src`
- **WHEN** the reader classifies the load path
- **THEN** `hasRemoteImages` is true, so the state is NOT **No remote images** (it is Blocked / Proxied / Loaded direct per the other inputs)
- **AND** this prevents the privacy-dangerous false negative where a srcset-only message that fetches remotely in direct-load mode would otherwise read as "No remote images"

#### Scenario: Untrusted sender, images not loaded, is Blocked

- **GIVEN** the message has remote images
- **AND** `isImageTrusted(fromEmail)` is false
- **AND** the user has not tapped "Load images" (`loadImages == false`)
- **WHEN** the reader classifies the load path
- **THEN** the state is **Blocked**
- **AND** the state is **Blocked** regardless of whether a proxy is configured (nothing remote is fetched while blocked)

#### Scenario: Shown images with active proxy is Proxied

- **GIVEN** the message has remote images
- **AND** images are shown (`isImageTrusted(fromEmail)` true OR `loadImages` true)
- **AND** `model.imageProxyConfig` is non-nil (toggle on, valid base URL, secret resolvable)
- **WHEN** the reader classifies the load path
- **THEN** the state is **Proxied**

#### Scenario: Shown images with no active proxy is Loaded direct

- **GIVEN** the message has remote images
- **AND** images are shown (trusted OR `loadImages` true)
- **AND** `model.imageProxyConfig` is nil (proxy disabled, base URL blank/invalid, or no secret)
- **WHEN** the reader classifies the load path
- **THEN** the state is **Loaded direct**

#### Scenario: Edge case: trusted sender auto-shows images and is classified without user action

- **GIVEN** the message has remote images
- **AND** `isImageTrusted(fromEmail)` is true (so `showImages` is true on first render, `loadImages` still false)
- **AND** `model.imageProxyConfig` is non-nil
- **WHEN** the reader classifies the load path on initial display
- **THEN** the state is **Proxied** (matching that trusted senders bypass the block gate at `ReaderView.swift:290-291`)

### Requirement: Indicator re-evaluates when the user loads images

The indicator state SHALL re-derive whenever its inputs change for the same displayed message, so tapping "Load images" (which sets `loadImages = true` at `ReaderView.swift:301`) transitions the indicator out of **Blocked** into **Proxied** or **Loaded direct** without selecting a different message.

#### Scenario: Blocked transitions to Proxied on Load images with proxy active

- **GIVEN** the message is shown in the **Blocked** state (untrusted, not loaded)
- **AND** `model.imageProxyConfig` is non-nil
- **WHEN** the user taps "Load images"
- **THEN** the indicator state becomes **Proxied**

#### Scenario: Blocked transitions to Loaded direct on Load images with no proxy

- **GIVEN** the message is shown in the **Blocked** state
- **AND** `model.imageProxyConfig` is nil
- **WHEN** the user taps "Load images"
- **THEN** the indicator state becomes **Loaded direct**

### Requirement: Indicator is visible and labels the privacy posture in the reader

The reader SHALL render a visible per-message indicator in the primary message card whose label/affordance corresponds to the computed state, distinguishing at minimum the privacy-relevant cases: **Loaded direct** (the leaking path) MUST be visually distinct from **Proxied**, and both MUST be distinguishable from **Blocked** and **No remote images**. The indicator MUST sit with the existing privacy chrome of the primary card (the block banner / "Load images" row region around `ReaderView.swift:292-318`) and MUST NOT obscure or replace the existing "Load images" / "Always" controls.

#### Scenario: Direct-load state is shown distinctly from proxied

- **GIVEN** a displayed message in the **Loaded direct** state
- **WHEN** the primary card renders
- **THEN** a visible indicator communicates that images were loaded directly from the sender (the IP-leaking path)
- **AND** its presentation is distinguishable from the **Proxied** state's presentation

#### Scenario: Proxied state names the proxy without exposing the secret

- **GIVEN** a displayed message in the **Proxied** state
- **WHEN** the primary card renders
- **THEN** a visible indicator communicates that images loaded through the privacy proxy
- **AND** the indicator MUST NOT contain the HMAC signature, any asset URL, or the signing secret

#### Scenario: Edge case: No-remote-images state shows a neutral or absent indicator

- **GIVEN** a displayed message in the **No remote images** state
- **WHEN** the primary card renders
- **THEN** the indicator either communicates "no remote images" or is absent
- **AND** it does NOT claim the message was proxied or loaded direct

## Success Criteria

- **SC-001** *(manual)*: With the proxy configured and active, opening a trusted-sender message that contains remote images shows the **Proxied** indicator on screen; toggling the proxy off (or clearing the base URL) and reopening the same message shows the **Loaded direct** indicator. This on-screen SwiftUI check is a manual-exploration step, explicitly NOT part of the automated suite (SC-006) — a rendered indicator cannot be asserted by the test target.
- **SC-002**: A pure classifier (the function that maps `hasRemoteImages` — itself derived from `bodyHTML` per the **No remote images** definition, scanning `<img>` `src` AND `srcset` for remote refs — plus `showImages` and `proxyActive` to one of the four states) returns **No remote images** for a nil/empty `bodyHTML`, for non-empty HTML with no remote `<img>` ref, AND (privacy-critical) returns NOT-**No remote images** for a `<img srcset="https://…">`-only body — exercised with injected values and NO AppModel/WebKit/Keychain access (proving purity).
- **SC-003**: The classifier is exercised over EVERY reachable combination of the three input booleans `(hasRemoteImages, showImages, proxyActive)` and asserts the expected state for each. The full enumeration (8 rows; `showImages = isImageTrusted ∨ loadImages`, `proxyActive = imageProxyConfig != nil`):

  | # | `hasRemoteImages` | `showImages` | `proxyActive` | Expected state | Notes |
  |---|---|---|---|---|---|
  | 1 | false | false | false | No remote images | other two inputs don't-care |
  | 2 | false | false | true  | No remote images | other two inputs don't-care |
  | 3 | false | true  | false | No remote images | trusted/loaded sender, HTML body, no remote img |
  | 4 | false | true  | true  | No remote images | proxy on but nothing remote to fetch |
  | 5 | true  | false | false | Blocked | `proxyActive` don't-care while blocked |
  | 6 | true  | false | true  | Blocked | proxy configured but nothing fetched |
  | 7 | true  | true  | true  | Proxied | shown + proxy active |
  | 8 | true  | true  | false | Loaded direct | shown + no proxy (the leaking path) |

  All 8 are reachable as classifier INPUTS; none is excluded. (Rows 1-4 collapse to one state because `hasRemoteImages=false` makes `showImages`/`proxyActive` irrelevant; rows 5-6 collapse because `showImages=false` makes `proxyActive` irrelevant — but each is still a valid, separately-asserted input tuple, so the classifier is proven robust to the don't-care dimensions.)
- **SC-004**: The classifier returns EXACTLY one of the four states for every one of the 8 input tuples above (mutual exclusivity + totality over the full Boolean input space): each tuple yields a non-nil state, and no tuple maps to two states. Asserted by iterating all 8 combinations and checking the result is a single member of the four-case enumeration matching the SC-003 table — so the four states partition the input space with no gap and no overlap.
- **SC-005**: For a message in the **Blocked** state, flipping the `loadImages` input true while holding the other inputs fixed re-classifies to **Proxied** (proxy present) or **Loaded direct** (proxy absent), proving the state tracks the "Load images" transition.
- **SC-006**: All automated scenarios above pass under the `MMailTests` target using **Swift Testing** (`import Testing`, `@Suite`, `@Test`, `#expect`) — NOT XCTest. SC-001 is excluded (manual on-screen verification).

## Non-Goals

- **Read-only; no behavior change.** This feature adds NO new load path and changes NO existing one. It does not add a "load via proxy now" button, does not auto-enable the proxy, and does not alter trust. (Decision/assumption: surfacing posture is the whole MVP; remediation affordances are deferred.)
- **No handling of a `WKContentRuleList` compile failure (known limitation, disclosed not handled).** In proxy mode `HTMLMessageView` asynchronously compiles the proxy allow-rule (`HTMLMessageView.swift:162-169`); if compilation fails the completion still receives `list == nil`, so `if let list { ... add(list) }` installs NO rule yet `web.loadHTMLString` fires anyway (`HTMLMessageView.swift:167-168`) — remote `<img src>` then loads **DIRECT from origin**, while the indicator (keying on `imageProxyConfig != nil && showImages`) still shows **Proxied**. This is a genuine indicator/reality divergence: the indicator reflects the **INTENDED** load path, not a post-hoc verification of what WebKit actually did. Mitigating it would require observing WebKit's compile result and is a rare system-level failure path out of MVP scope. Disclosed here, not handled. (The symmetric **Blocked**-path compile failure is privacy-SAFE — it would load remote content the indicator says is blocked, but Blocked is itself the conservative state, and this same WebKit risk predates and is independent of this indicator.)
- **No trusted-sender management UI** (feature D) — viewing/adding/removing trusted-image senders beyond the existing "Always" button is out of scope.
- **No proxy-misconfiguration warning** (feature C) — e.g. "proxy enabled but base URL blank / secret missing, so images will load direct" is a *separate* queued feature. This indicator only reports the realized state of the **current** message; it does NOT diagnose why the proxy is inert.
- **No per-image or partial-proxy accounting.** Decision/assumption: the indicator reports a single message-level state, not "3 of 5 images proxied." The render path applies one content-rule regime to the whole body, so a single state is faithful. (Caveat documented for the reviewer: a message whose `<img src>` are non-http(s) or already point at the proxy host are left unrewritten by `ImageProxy.rewriteTag`; in the **Proxied** state those specific assets aren't re-proxied, but they also aren't a direct-origin leak — so message-level **Proxied** remains accurate. This is not modeled per-image.)
- **No accounting for non-`<img>` remote resources.** Decision/assumption: scripts, iframes, fonts, external CSS, and CSS `url()` are *always blocked* in the **Blocked** path (the standalone block-all rule, `blockRules` at `HTMLMessageView.swift:101-103`) and in the **Proxied** path (the block-all base of the proxy allow-rule, `HTMLMessageView.swift:137`, whose only `ignore-previous-rules` exception is the proxy host). Only the **Loaded direct** path lifts blocking entirely (`web.loadHTMLString` with no content rule, `HTMLMessageView.swift:175-176`) — but there the user has already accepted direct origin loads, and the indicator's scope is remote **images** only (matching the proxy's scope). CSS-`url()` background images are not proxied in either mode and are not modeled by the indicator.
- **No handling of the (practically unreachable) `proxyAllowRules == nil` branch.** Decision/assumption: `HTMLMessageView` can in principle fall back from proxied to direct when `proxyAllowRules(for:)` returns nil (`HTMLMessageView.swift:130`, which guards `let host = config.baseURL.host, !host.isEmpty`). `imageProxyConfig` guards only `url.host != nil` (`AppModel.swift:937`), NOT non-empty — so the two are **not logically equivalent** (a non-nil but empty-string host would pass the config guard yet fail the rule guard). They are equal only as a **practical** guarantee: Foundation's `URL` never yields a non-nil empty `host` in practice, so a non-nil `imageProxyConfig` reliably yields a non-nil rule. The indicator classifies **Proxied** whenever `imageProxyConfig != nil` and images are shown; it does NOT separately detect this practically-dead branch. (Flagged for the reviewer in case either guard is ever relaxed or `URL`'s behavior changes.)
- **No thread / peek-card indicator.** Only the primary message card renders remote HTML; thread peek-cards (`ReaderView.swift:600-631`) show plain previews and get no indicator.
- **No persistence or telemetry.** The state is computed on display and never stored, logged, or transmitted.
- **No change** to `ImageProxy`, `ProxySecretStore`, the Cloudflare Worker, or the URL-signing contract.
