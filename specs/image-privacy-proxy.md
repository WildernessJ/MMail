# Image Privacy Proxy Specification

## Purpose

MMail SHALL route remote images for *chosen* senders (trusted senders, or messages the user explicitly loads) through a caching privacy proxy — a Cloudflare Worker backed by R2 — so the sender's origin server sees a request only from the proxy's IP (never the user's), and at most once per asset across repeated opens. Senders that are neither trusted nor explicitly loaded SHALL continue to generate zero network activity, exactly as the current block-by-default build does. The proxy is the *transport* used whenever images are loaded; it is never a reason to load images that would otherwise be blocked.

## Invariants

- The proxy MUST NEVER be invoked for a message whose sender is not trusted and which the user has not explicitly chosen to load. Untrusted, un-clicked messages MUST produce zero outbound network requests (proxied or direct).
- When proxying is active for a message, the reader MUST install a `WKContentRuleList` that blocks every remote resource type and then `ignore-previous-rules` (allows) ONLY the proxy origin, and MUST NOT load the message until that rule is compiled and installed (no race — the same deferred-load pattern the existing block path uses at `HTMLMessageView.swift:99-104`). Consequently, any remote resource that is not a rewritten `<img src>` proxy URL — scripts, iframes, fonts, external stylesheets, CSS `url()`, and `srcset`/image sources on non-proxy origins — MUST be blocked. **Excluding a resource type from rewriting is therefore a visual limitation only, NEVER a network leak.**
- Rewriting MUST occur at display time from the original message body. Rewritten HTML MUST NEVER be persisted (e.g. to `MailCache`), and signed URLs MUST be minted fresh on each render — so a stored body can never carry an expired signature.
- When the proxy toggle is off OR the proxy base URL is empty, behavior MUST be identical to the pre-feature build: trusted/clicked → direct load, untrusted → blocked.
- The HTML rewrite function MUST be pure: no I/O, deterministic given an injected clock, and MUST NEVER alter anything it does not rewrite (already-proxied URLs, `cid:`/`data:` images, relative URLs, and all non-`<img>` markup are left byte-for-byte unchanged).
- A signed proxy URL minted by the MMail client MUST verify under the Worker's HMAC check — both sides use the same secret and the identical signing payload `"<expiry>:<assetURL>"`, with the message hashed as UTF-8 bytes and the signature base64url-encoded without padding.
- The Worker MUST NEVER fetch an origin asset for a request whose signature is invalid or expired.
- The Worker is a **single-tenant** deployment (the user's own Cloudflare account, gated by a secret only the user's build holds). There are no other users; "cache leak across users" is out of scope by construction.

## Requirements

### Requirement: Block untrusted senders with zero network

The reader SHALL NOT issue any network request — proxied or direct — for a message whose sender is not in the trusted-sender list and for which the user has not clicked "Load images".

#### Scenario: Untrusted sender stays fully blocked

- **GIVEN** proxying is enabled with a valid proxy base URL
- **AND** the message's sender is not trusted
- **AND** the user has not clicked "Load images"
- **WHEN** the message is opened in the reader
- **THEN** no remote request is made to the sender's origin or to the proxy
- **AND** the existing "Blocked N trackers / Load images / Always" banner is shown

### Requirement: Proxy-route images for chosen senders

When proxying is enabled and a message is shown-with-images (sender trusted, or the user clicked "Load images"), the reader SHALL render the message with every remote `<img src>` rewritten to a signed proxy URL and SHALL permit remote loads only from the proxy origin.

#### Scenario: Trusted sender auto-loads through the proxy

- **GIVEN** proxying is enabled with a valid proxy base URL
- **AND** the message's sender is trusted
- **WHEN** the message is opened in the reader
- **THEN** images load automatically with no banner and no click
- **AND** every remote `<img src>` is fetched from the proxy origin
- **AND** the sender's origin server sees the request from the proxy IP, not the user's IP

#### Scenario: One-off "Load images" routes through the proxy

- **GIVEN** proxying is enabled with a valid proxy base URL
- **AND** the message's sender is not trusted
- **WHEN** the user clicks "Load images" on that message
- **THEN** that message's `<img src>` URLs load via the proxy origin for this view
- **AND** no remote resource other than the proxy origin loads

#### Scenario: Non-image and non-rewritten remote resources are blocked, not leaked

- **GIVEN** a shown-with-images message containing a remote `<script>`, `<iframe>`, web font, external `<link rel=stylesheet>`, a CSS `background-image: url(...)`, and an `<img srcset="https://other-origin/p.gif 1x">` (no `src`)
- **WHEN** the message renders through the proxy
- **THEN** none of those resources load — the proxy-origin allow-rule blocks every non-proxy origin
- **AND** only the rewritten `<img src>` proxy URLs load
- **AND** the unloaded srcset/CSS images are a visual gap only — no request reaches their origin

#### Scenario: Allow-rule is installed before the message loads

- **GIVEN** proxying is enabled and a message is shown-with-images
- **WHEN** the reader prepares to render
- **THEN** the block-all-except-proxy-origin content rule is compiled and installed BEFORE `loadHTMLString` is called
- **AND** no remote request can fire before the rule is in place

#### Scenario: Edge case: proxy setting changed while a message is open

- **GIVEN** a message is currently rendered in the reader
- **WHEN** the user toggles proxying or changes the proxy base URL
- **THEN** the open message re-renders under the new setting (rewrite + allow-rule recompiled for the new origin, or reverted to direct/blocked)
- **AND** any in-flight rule compilation for the previous origin is discarded before the new compile/load is initiated (its completion handler MUST NOT install a stale rule or load stale HTML)
- **AND** the stale rendering is not left in place

### Requirement: Pure HTML rewrite seam (img src only)

A pure function SHALL transform email HTML into HTML in which each remote (`http`/`https`) `<img src>` is replaced by a signed proxy URL, leaving all other content unchanged. It SHALL accept an injected clock so its output is deterministic under test.

#### Scenario: Single remote img is rewritten

- **WHEN** the rewriter is given HTML containing `<img src="https://track.example/p.gif?id=ME">`
- **THEN** that `src` is replaced by `<proxy-base>/proxy?u=<encoded asset>&e=<expiry>&s=<sig>`
- **AND** the rest of the HTML is unchanged

#### Scenario: Non-image and non-remote sources are left untouched

- **GIVEN** HTML containing a remote `<script src>`, a remote `<iframe src>`, a `<link href>`, an `<img src="cid:abc">`, an `<img src="data:image/png;base64,...">`, and an `<img src="/relative.png">`
- **WHEN** the rewriter runs
- **THEN** none of those `src`/`href` values are modified

#### Scenario: Rewriting is idempotent for already-proxied URLs

- **GIVEN** HTML whose `<img src>` already points at the proxy origin
- **WHEN** the rewriter runs
- **THEN** that `src` is not re-wrapped or otherwise changed

#### Scenario: srcset and CSS url() are out of scope

- **GIVEN** HTML containing `<img srcset="https://x/a.jpg 1x">` and `<div style="background-image:url(https://x/b.jpg)">`
- **WHEN** the rewriter runs
- **THEN** neither the `srcset` nor the CSS `url()` is rewritten

#### Scenario: Edge case: no images

- **WHEN** the rewriter is given HTML with no remote `<img>` tags
- **THEN** the output equals the input

#### Scenario: Edge case: empty or malformed src

- **GIVEN** HTML containing `<img src="">` and `<img>`
- **WHEN** the rewriter runs
- **THEN** neither tag is rewritten and no signed URL is produced for them

### Requirement: Signed proxy URL contract (matches the Worker)

The signer SHALL produce a URL of the form `<base>/proxy?u=<percent-encoded assetURL>&e=<unix-seconds-expiry>&s=<signature>`, where `assetURL` is the HTML-entity-decoded `src` value (e.g. `&amp;`→`&`) so client and Worker share one canonical form, `signature = base64url( HMAC-SHA256( key = raw secret bytes, message = UTF-8 bytes of "<e>:<assetURL>" ) )` with `+`→`-`, `/`→`_`, and `=` padding stripped, and `e = floor(now) + 300`.

#### Scenario: Pinned cross-language HMAC vector

- **GIVEN** a single fixed test vector `(K, e, A) → S` documented in both the Swift test and the Worker test (concrete byte values pinned, not computed at test time), where `A` deliberately contains a space and an `&` so the vector exercises encoding edge cases
- **WHEN** the Swift signer runs with `(K, A)` and injected clock yielding `e`
- **THEN** it emits exactly `S`
- **AND** the `u` parameter percent-encodes the space as `%20` (RFC 3986), NOT form-encoded `+`
- **AND** the Worker's verifier, given the same `(K, e, A)`, accepts `S` and rejects `S` with any single byte flipped
- **AND** this guarantees the two implementations agree on encoding (UTF-8 message, raw-byte key, padding-stripped base64url, RFC-3986 percent-encoding)

#### Scenario: Edge case: expired signature

- **GIVEN** a URL minted at clock `T` (so `e = floor(T)+300`)
- **WHEN** the Worker receives it at a time later than `e`
- **THEN** the request is rejected before any origin fetch

### Requirement: Proxy disabled or unconfigured falls back to current behavior

When the proxy toggle is off OR the configured base URL is empty, the reader SHALL behave identically to the pre-feature build.

#### Scenario: Toggle off → direct load for chosen senders

- **GIVEN** the proxy toggle is off
- **AND** the message's sender is trusted
- **WHEN** the message is opened
- **THEN** images load directly (no rewriting, no proxy)
- **AND** an untrusted sender's images remain blocked

### Requirement: Settings expose the proxy toggle and endpoint

Settings SHALL provide a toggle labeled "Route remote images through privacy proxy" defaulting to ON, and a field for the proxy base URL. Proxying is **active only when the toggle is ON AND the base URL is non-empty**; in any other combination behavior falls back to the pre-feature build (direct for chosen senders, blocked otherwise). Clearing the URL makes proxying inert without changing the toggle state (the toggle is never auto-flipped). The HMAC signing secret SHALL be stored in the macOS Keychain, never in UserDefaults or the build.

#### Scenario: Toggle and URL persist; secret in Keychain

- **WHEN** the user enables the toggle and sets a base URL
- **THEN** both values persist across app relaunch
- **AND** the signing secret is read from and written to the Keychain
- **AND** the signing secret is never written to UserDefaults

### Requirement: Worker verifies, fetches once, caches, and streams

The Worker SHALL first **percent-decode the `u` query parameter** to recover the canonical `assetURL` (the exact value the client signed), use that decoded value to reconstruct the HMAC payload `"<e>:<assetURL>"` for verification, and use that same decoded value as the cache-key input. The Worker SHALL reject any request whose signature is invalid or whose `e` is in the past; otherwise it SHALL fetch the asset (stripping inbound cookies, sending a neutral user-agent, enforcing a size cap — recommended 10 MB — and an origin timeout — recommended 10 s — both tunable via wrangler config), store the response body and content-type in R2 keyed by `SHA-256(decoded assetURL)` with NO further normalization (so two distinct URLs always map to distinct keys and no asset can be served in place of another), and stream it back. A request for an asset already in R2 SHALL be served from R2 without re-fetching the origin. Cache entries SHALL have no expiry by design (origin-hit-once is the goal; staleness of email images is acceptable).

#### Scenario: Cache miss fetches origin exactly once

- **GIVEN** a validly signed request for an asset not yet in R2
- **WHEN** the Worker handles it
- **THEN** the origin is fetched once
- **AND** the body + content-type are stored in R2 under the asset URL's SHA-256
- **AND** the asset is streamed back to the client

#### Scenario: Cache hit never re-fetches the origin

- **GIVEN** the same asset has already been stored in R2
- **WHEN** a second validly signed request for it arrives
- **THEN** the asset is served from R2
- **AND** the origin server receives no request

#### Scenario: Expired or invalid signature is rejected without fetching

- **GIVEN** a request whose `e` is earlier than now, OR whose `s` does not match
- **WHEN** the Worker handles it
- **THEN** it responds with a 4xx status
- **AND** no origin fetch occurs

#### Scenario: Edge case: oversize or failing origin

- **GIVEN** a validly signed request whose origin asset exceeds the size cap or errors
- **WHEN** the Worker handles it
- **THEN** it responds with an error status
- **AND** nothing is stored in R2 for that asset

## Success Criteria

- **SC-001**: Opening a message from an untrusted, un-clicked sender produces zero outbound network requests (confirmed by observing no WKWebView resource loads / network capture).
- **SC-002**: For a trusted sender with proxying on, the sender's origin receives requests only from the proxy IP — never the user's IP — and at most once per asset across repeated opens (R2 cache; verified by re-opening and inspecting Worker/R2).
- **SC-003**: One pinned cross-language HMAC test vector `(K, e, A) → S` is asserted by BOTH a Swift unit test and a Worker test; AND, in live-verify, a fresh signed URL minted by MMail and fetched against the deployed Worker returns HTTP 200 with the origin image's content-type and body (a tampered or expired URL returns 4xx). Live-verify is a manual developer step, not a CI gate.
- **SC-004**: With the proxy toggle off, reader behavior is identical to the pre-feature build for trusted, untrusted, and clicked cases.
- **SC-005**: The pure-seam unit tests (rewrite seam + signing known-vector) pass under the project's `xcodebuild` test action, and `verify.type_check_command` builds clean.
- **SC-006**: In proxy mode, opening a message that contains a non-proxy `<script>`, `<iframe>`, and `srcset` image produces remote requests to the proxy origin ONLY — no request reaches any other origin (confirmed by observing WKWebView resource loads / network capture).

## Non-Goals

- No `srcset` or CSS `background-image` rewriting — `<img src>` only. Verified against the user's real mailbox: `srcset` appears in 0 messages, CSS background-images in 5% of messages, and every such message also has normal `<img>` content, so img-only renders ~100% of visible images. Because the proxy-origin allow-rule blocks everything not rewritten, excluded resources are a *visual* gap only — never a network leak. CSS-background rewriting is a deferred fast-follow.
- No pre-fetch-at-sync and no open-event decoupling — this is Tier 3 (on-open). Tier 4 (Apple-style pre-fetch) is a separate future feature.
- **No protection against open-detection via the asset URL itself.** A tracking pixel's URL may be a per-recipient token (e.g. `?id=<you>`); the Worker fetches that exact URL from the origin, so on first load the origin still learns the message was opened (identity confirmed) — and with per-recipient URLs the "cached after first fetch" property means the origin is told *once*, which is enough to confirm receipt. Tier 3 hides the user's **IP, location, and repeat-open timing**, NOT the *fact* of opening. Per-recipient query parameters are deliberately NOT stripped — tracking vs. functional parameters cannot be reliably distinguished, and stripping the wrong one breaks the image.
- No special UI for proxy fetch failures — an expired/oversized/errored image renders as WebKit's default broken-image glyph in v1.
- No R2 eviction or TTL — entries persist by design; R2 growth is bounded by the user's own image volume, well under the free tier.
- No proxying of scripts, iframes, web fonts, or external stylesheets — these remain blocked in all modes.
- No client-side (local) image cache — caching lives in R2 at the proxy.
- No per-account or multiple proxy endpoints — a single global proxy configuration.
- No automatic Worker provisioning — the user deploys the Worker and creates the R2 bucket via `wrangler`.
