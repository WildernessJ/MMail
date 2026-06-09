# image-privacy-proxy Implementation Plan

**Goal:** Route remote `<img src>` for trusted/explicitly-loaded senders through a single-tenant Cloudflare Worker + R2 cache so the origin sees only the proxy IP (hit once per asset), while untrusted senders stay at zero network.

**Architecture:** A Cloudflare Worker (JS, R2-backed, user-deployed via `wrangler`, NOT harness-gated) verifies HMAC-signed image URLs, percent-decodes `u`, fetches-once + caches in R2 keyed by `SHA-256(decoded assetURL)`, and streams back. MMail (Swift, gated) rewrites `<img src>` to signed URLs at display time via a pure seam, signs with CryptoKit to match the Worker (pinned cross-language vector), and renders behind a block-all-except-proxy-origin `WKContentRuleList` installed before load. A single shared secret lives in the macOS Keychain (MMail) and as a `wrangler secret` (Worker).

**Test Methodology:** e2e-first — adapted to this repo's convention: pure seams (signer, rewriter, Worker crypto, Worker handler) get example-based unit tests against ONE pinned cross-language HMAC vector; WebKit rendering and the deployed Worker are live-verified (manual-exploration). Swift unit/test cue is `xcodebuild test`; Worker cue is `node --test` + `curl`.

**Operational note (XcodeGen):** the project is generated from `project.yml`; `project.pbxproj` is git-tracked. ADDING any new `.swift` file requires `xcodegen generate` + committing the regenerated `project.pbxproj`. EDITING existing `.swift` files does not. Only T008 adds new Swift files.

**Phase boundaries:** A → B → C → D → E. Pause at each boundary for a handoff before continuing (per user convention).

---

## Phase A — Cloudflare Worker + R2 (`proxy-worker/`, not gated)

- [x] **T001 (SC: 003): Scaffold the Worker package** — Create `proxy-worker/` with `package.json` (type: module, `node --test` script), `wrangler.toml` (R2 bucket binding `IMG_CACHE`; secret `PROXY_SECRET` documented as `wrangler secret put`, never committed), and `src/index.js` exporting a `fetch` handler returning 501. Scaffold smoke-check only — no behavior until T003. Run: `node --check proxy-worker/src/index.js` Expected: no syntax error.
  **Files:** `proxy-worker/package.json`, `proxy-worker/wrangler.toml`, `proxy-worker/src/index.js`, `proxy-worker/.gitignore`

- [x] **T002 (SC: 003): Mint the pinned cross-language vector** — Pick `K` = an **ASCII-printable** secret string (so its UTF-8 bytes are unambiguous on every side: CryptoKit `Data(K.utf8)`, Worker `new TextEncoder().encode(K)`, openssl `-hmac "K"`). Pick `A` = an asset URL deliberately containing a space and an `&` (e.g. `https://x.test/a b.gif?u=1&v=2`) and a fixed `e`. Compute `S` via openssl as source-of-truth and write `{K, e, A, S}` to `proxy-worker/test/vector.json`. Run: `printf '%s' "<e>:<A>" | openssl dgst -sha256 -hmac "<K>" -binary | openssl base64 | tr '+/' '-_' | tr -d '='` Expected: prints `S`, committed verbatim.
  **Files:** `proxy-worker/test/vector.json`

- [x] **T003 (SC: 003): Failing crypto test** — Extract a pure `src/crypto.js` (build payload `"<e>:<assetURL>"`, HMAC-SHA256 via `crypto.subtle` with key = UTF-8 bytes of `K`, base64url no-pad). Add `test/crypto.test.js` asserting `verify(vector)` accepts and any single-byte-flipped `S` is rejected. Run: `cd proxy-worker && node --test` Expected: FAIL ("not implemented").
  **Files:** `proxy-worker/src/crypto.js`, `proxy-worker/test/crypto.test.js`

- [x] **T004 (SC: 003): Implement crypto + commit** — Implement `sign`/`verify` until the pinned vector passes and bit-flip rejects. Run: `cd proxy-worker && node --test` Expected: PASS. Commit.
  **Files:** `proxy-worker/src/crypto.js`

- [x] **T005 (SC: 002): Failing handler test (mocked R2 + fetch)** — Add `test/handler.test.js` that drives the `fetch` handler with an **in-memory mock R2** (`get`/`put`) and a **mock `fetch`**, asserting: (a) valid sig + cache miss → origin fetched exactly once, body+content-type stored, streamed back; (b) valid sig + cache hit → served from R2, mock `fetch` NOT called; (c) bad sig → 4xx, no fetch; (d) expired `e` → 4xx, no fetch; (e) oversize/origin-error → error status, nothing stored. Run: `cd proxy-worker && node --test` Expected: FAIL.
  **Files:** `proxy-worker/test/handler.test.js`, `proxy-worker/src/index.js` (export handler testably)

- [x] **T006 (SC: 002): Implement handler + commit** — Implement: parse `u`/`e`/`s`; **percent-decode `u`** to canonical assetURL; verify via `crypto.js`; reject (4xx, no fetch) on bad/expired; R2 `get` by `SHA-256(decoded assetURL)`; on miss `fetch` origin (omit cookies, neutral UA, 10 MB cap, 10 s timeout) → `put` → stream; on hit serve from R2; oversize/error → error, nothing stored. Run: `cd proxy-worker && node --test` Expected: PASS. Commit.
  **Files:** `proxy-worker/src/index.js`

- [x] **T007 (SC: 002, 003): Deploy + curl live-verify (USER STEP — deploy/curl deferred to user; Worker made deploy-READY: wrangler.toml + README.md with deploy + curl steps)** — User runs `wrangler login`, `wrangler r2 bucket create <name>`, `wrangler secret put PROXY_SECRET` (record it — reused in T018), `wrangler deploy`. Then curl-verify. Run: `curl -i "<deployed>/proxy?u=<enc A>&e=<future>&s=<sig>"` (→ 200 + image content-type), tampered `s` (→ 4xx), expired `e` (→ 4xx), valid URL twice (2nd from R2, origin not re-hit — confirm via Worker logs / R2). Expected: 200 / 4xx / 4xx / cache-hit.
  **Files:** `proxy-worker/README.md` (deploy + curl steps)

---

## Phase B — MMail signer + rewriter (gated; pure-seam unit tests)

- [x] **T008 (SC: 003): Types + scaffolding** — Create `MMail/Mail/ImageProxy.swift`: `struct ImageProxyConfig { let baseURL: URL; let signingSecret: String }`, stub `func proxiedURL(forAsset: String, now: Date) -> URL?` (nil), stub `static func rewrite(html: String, config: ImageProxyConfig, now: Date) -> String` (returns html). Create `MMailTests/ImageProxyTests.swift` with imports + an empty test case skeleton (compiles, no assertions yet). Run: `xcodegen generate && xcodebuild -project MMail.xcodeproj -scheme MMail -configuration Debug build CODE_SIGNING_ALLOWED=NO` Expected: BUILD SUCCEEDED. Commit incl. regenerated `project.pbxproj`.
  **Files:** `MMail/Mail/ImageProxy.swift`, `MMailTests/ImageProxyTests.swift`, `MMail.xcodeproj/project.pbxproj`

- [ ] **T009 (SC: 003): Failing signer test (pinned vector)** — Add assertions using the SAME `(K, A, e)` from `proxy-worker/test/vector.json`: `proxiedURL` emits exactly `S`; `e == floor(now)+300`; the space in `A` is `%20` (not `+`) in `u`. The test FAILS because `proxiedURL` is still a stub returning nil. Run: `xcodebuild test -project MMail.xcodeproj -scheme MMail -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO` Expected: FAIL (assertion mismatch).
  **Files:** `MMailTests/ImageProxyTests.swift`

- [ ] **T010 (SC: 003): Implement signer + commit** — CryptoKit `HMAC<SHA256>`, key = `Data(signingSecret.utf8)` (UTF-8 bytes, matching T002's ASCII `K`), UTF-8 message, base64url (`+`→`-`, `/`→`_`, strip `=`), RFC-3986 percent-encoding (space→`%20`), `e = floor(now)+300`. Run: same `xcodebuild test` Expected: PASS. Commit.
  **Files:** `MMail/Mail/ImageProxy.swift`

- [ ] **T011 (SC: 005): Failing rewriter tests** — Add tests: single remote `<img src>` → signed proxy URL; `<script>`/`<iframe>`/`<link>`/`cid:`/`data:`/relative/`srcset`/CSS `url()` untouched; already-proxied URL idempotent; image-free HTML unchanged; `<img src="">` & `<img>` not rewritten; HTML-entity-decoded `src` (`&amp;`→`&`) is the signed value. FAILS because `rewrite` is a stub. Run: `xcodebuild test ...` Expected: FAIL.
  **Files:** `MMailTests/ImageProxyTests.swift`

- [ ] **T012 (SC: 005): Implement rewriter + commit** — Match remote `<img ... src=...>`, HTML-entity-decode the src to canonical assetURL, replace via `proxiedURL`; leave all else byte-for-byte. Run: `xcodebuild test ...` Expected: PASS. Commit.
  **Files:** `MMail/Mail/ImageProxy.swift`

---

## Phase C — WebKit integration (gated; build)

- [ ] **T013 (SC: 006): Proxy-origin allow-rule builder** — In `HTMLMessageView.swift`, add a helper building a `WKContentRuleList` JSON that blocks all remote resource types (`url-filter: .*`) then `ignore-previous-rules` for the proxy origin (host derived from `ImageProxyConfig.baseURL`). Run: `xcodebuild ... build ...` Expected: BUILD SUCCEEDED.
  **Files:** `MMail/Views/HTMLMessageView.swift`

- [ ] **T014 (SC: 001, 006): HTMLMessageView proxy mode + commit** — Add `var proxyConfig: ImageProxyConfig?` (nil ⇒ today's behavior). In `Coordinator.load`: when images shown AND `proxyConfig != nil` → rewrite html fresh at display time (never persist), compile the allow-rule, install BEFORE `loadHTMLString` (deferred completion, mirroring the block path at `HTMLMessageView.swift:99-104`); on reconfigure, discard any in-flight compile (a generation counter / token so a stale completion handler installs nothing and loads nothing). Else: existing block/direct paths unchanged. Run: `xcodebuild ... build ...` Expected: BUILD SUCCEEDED. Commit.
  **Files:** `MMail/Views/HTMLMessageView.swift`

---

## Phase D — Settings, config state, secret (gated; tests + build)

- [ ] **T015 (SC: 004): Failing secret-storage test** — Add Keychain store/read function *signatures* (stubs) for the proxy signing secret, and a test asserting: after `storeProxySecret("s")`, `readProxySecret() == "s"` AND `UserDefaults.standard.string(forKey: <secretKey>) == nil` (the "never in UserDefaults" invariant). FAILS against the stub. Run: `xcodebuild test ...` Expected: FAIL.
  **Files:** `MMail/Mail/Keychain.swift`, `MMailTests/ImageProxyTests.swift`

- [ ] **T016 (SC: 004): Implement secret storage + commit** — Implement store/read against the existing generic-password `Keychain` wrapper; secret never touches UserDefaults. Run: `xcodebuild test ...` Expected: PASS. Commit.
  **Files:** `MMail/Mail/Keychain.swift`

- [ ] **T017 (SC: 004): AppModel proxy config + commit** — Add `@Published proxyEnabled` (default `true`, persisted) and `proxyBaseURL` (persisted UserDefaults). Computed `var imageProxyConfig: ImageProxyConfig?` returns a config ONLY when `proxyEnabled && !baseURL.isEmpty && secret present`, else nil (active-condition invariant; clearing the URL never flips the toggle). Run: `xcodebuild ... build ...` Expected: BUILD SUCCEEDED. Commit.
  **Files:** `MMail/State/AppModel.swift`

- [ ] **T018 (SC: 004): SettingsView controls + commit** — Add a "Route remote images through privacy proxy" toggle (default ON), a proxy base URL field, and a secure secret field writing to the Keychain (the same string set via `wrangler secret put` in T007). Run: `xcodebuild ... build ...` Expected: BUILD SUCCEEDED. Commit.
  **Files:** `MMail/Views/SettingsView.swift`

---

## Phase E — Wiring + end-to-end live-verify (manual-exploration)

- [ ] **T019 (SC: 001, 002): Wire ReaderView + commit** — Pass `model.imageProxyConfig` (now defined, T017) into `HTMLMessageView(proxyConfig:)`. Keep `showImages = loadImages || trusted` unchanged; trusted/clicked render through the proxy when config is non-nil; banner still only in the blocked state. Run: `xcodebuild ... build ...` Expected: BUILD SUCCEEDED. Commit.
  **Files:** `MMail/Views/ReaderView.swift`

- [ ] **T020 (SC: 001, 002, 003, 006): Live-verify against the deployed Worker (USER STEP)** — Build into the pinned Dock `MMail.app` DerivedData path, ⌘Q + relaunch. In Settings set the proxy URL + matching secret. Verify: (a) trusted sender auto-loads with requests to the proxy origin ONLY (no other origin, no user IP); (b) untrusted, un-clicked sender → ZERO network; (c) re-opening a trusted message hits the origin at most once (R2 cache; Worker logs); (d) toggle OFF → direct load; (e) SC-006: a message with a non-proxy `<script>`/`<iframe>`/`srcset` shows proxy-origin requests only; (f) **race:** toggle proxy / change the URL WHILE a message is rendering → no stale rule or stale HTML is ever installed (the in-flight-compile discard from T014). Run: live app + network capture / Worker logs. Expected: all six hold.
  **Files:** (none — live verification)

- [ ] **T021 (SC: 005): Final gate** — Run: `xcodebuild test -project MMail.xcodeproj -scheme MMail -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO` then `xcodebuild -project MMail.xcodeproj -scheme MMail -configuration Debug build CODE_SIGNING_ALLOWED=NO` Expected: all tests pass + BUILD SUCCEEDED. (Hand to `/verify` for markers.)
  **Files:** (none — verification gate)
