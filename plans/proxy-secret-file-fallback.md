# proxy-secret-file-fallback Implementation Plan

**Goal:** Persist the image-proxy HMAC signing secret in both the Keychain (primary) and a private `0600` fallback file so it survives unsigned rebuilds with no re-paste.

**Architecture:** A new `ProxySecretStore` owns a pure `resolve(keychain:file:)`, a pure `shouldSyncFile(...)` decision, a pure `saveErrorMessage(keychainOK:fileOK:)`, plus atomic-`0600` file read/write under `~/Library/Application Support/MMail/`, and an impure `loadAndSync(keychainSecret:)` wrapper. `AppModel.loadProxySecret()` delegates to it; `imageProxyConfig` and `hasProxySecret` route through it; `setProxySecret` writes both stores and surfaces a per-store outcome. `Keychain.storeProxySecret` is changed to report success. All tests live in `MMailTests/` (fork-local, never goes upstream).

**Test Methodology:** e2e-first

**Test framework:** **Swift Testing** (`import Testing`, `@Suite struct`, `@Test func`, `#expect`) — matches every existing file in `MMailTests/`. Do NOT use XCTest.

**Pre-flight (handled by `/build`, not a task):** cut branch `feat/proxy-secret-file-fallback` off `main` before editing any `*.swift`. Build runs on an Opus subagent; review is opposite-model (Sonnet).

**Command shorthand:**
- BUILD = `xcodebuild -project MMail.xcodeproj -scheme MMail -configuration Debug build CODE_SIGNING_ALLOWED=NO`
- TEST = `xcodebuild test -project MMail.xcodeproj -scheme MMail -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO`
- `xcodegen generate` runs ONLY in tasks adding a new `.swift` file (T001, T002); the regenerated `MMail.xcodeproj/project.pbxproj` (+ any scheme xcshareddata) is committed deliberately in that task's commit.

---

- [ ] **T001 (SC: 002, 006): Define `ProxySecretStore` types + stubs** — Create `MMail/Mail/ProxySecretStore.swift` (`import Foundation`, `import OSLog`):
  - `struct ProxySecretStore { let directory: URL; var fileURL: URL { directory.appendingPathComponent("proxy-secret") } }`
  - Pure statics (stubs): `static func resolve(keychain: String?, file: String?) -> String?` → `nil`; `static func shouldSyncFile(effective: String?, keychainTrimmed: String?, fileTrimmed: String?) -> Bool` → `false`; `static func saveErrorMessage(keychainOK: Bool, fileOK: Bool) -> String?` → `nil`.
  - Instance (stubs): `func read() -> String?` → `nil`; `@discardableResult func write(_ secret: String) -> Bool` → `false`; `func loadAndSync(keychainSecret: String?) -> String?` → `nil`.
  - `static let \`default\` = ProxySecretStore(directory: FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: false).appendingPathComponent("MMail"))` (force-try acceptable for the default app-support URL).
  - Run: `xcodegen generate && BUILD` Expected: `** BUILD SUCCEEDED **`
  - **Files:** `MMail/Mail/ProxySecretStore.swift`, `MMail.xcodeproj/project.pbxproj`

- [ ] **T002 (SC: 002, 003, 004, 005, 006): Failing Swift Testing suite** — Create `MMailTests/ProxySecretStoreTests.swift` (`import Testing`, `import Foundation`, `@testable import MMail`). Tests against the T001 stubs so they FAIL on assertions (T001 exposes every symbol, so this compiles):
  - **`resolve` (pure, injected strings, NO I/O):** keychain wins over file; keychain blank → file; both blank → nil; whitespace-only file → nil. (SC-002)
  - **`shouldSyncFile` (pure):** `effective="K", keychain="K", file=nil` → true (migrate); `…file="F"` → true (divergence); `…file="K"` → false (idempotent — no write when equal); `effective="F", keychain=nil, file="F"` → false (came from file); `effective=nil, keychain=nil, file=nil` → false (no secret anywhere). (SC-004)
  - **`saveErrorMessage` (pure):** `(true,true)`→nil; `(true,false)`→non-nil mentioning the file; `(false,true)`→non-nil mentioning the Keychain; `(false,false)`→non-nil. (SC-006, message logic)
  - **file round-trip (real I/O in a per-test temp dir = `FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)`):** `write("s")` then `read() == "s"`; file POSIX perms == `0o600`; raw bytes == `"s"` (no trailing newline); `write("  s\n")` stores `"s"`. (SC-003)
  - **`write` failure:** writing into a non-existent/unwritable parent (e.g. a path under a `0o500` dir) returns `false`. (SC-006, file-failure half)
  - **`loadAndSync` (temp dir):** keychain `"K"` + file absent → returns `"K"` AND file now `"K"` (migrate); keychain `"K"` + file `"F"` → returns `"K"` AND file now `"K"` (divergence); keychain `nil` + file `"F"` → returns `"F"` AND no write occurs to the file (file already authoritative; came-from-file). (SC-004, SC-005)
  - **`loadAndSync` sync-write fails → read not broken:** temp dir `chmod 0o500`, file absent, keychain `"K"` → `loadAndSync` returns `"K"` (the internal `write` fails and is logged, but the read still yields `"K"`). (spec "sync write fails" scenario)
  - Run: `xcodegen generate && TEST` Expected: TEST FAILS (stubs return nil/false)
  - **Files:** `MMailTests/ProxySecretStoreTests.swift`, `MMail.xcodeproj/project.pbxproj`

- [ ] **T003 (SC: 002, 003, 004, 005, 006): Implement `ProxySecretStore` + commit** — Real bodies (`import OSLog` for failures):
  - `resolve`: trimmed-keychain if non-empty, else trimmed-file if non-empty, else nil.
  - `shouldSyncFile`: `effective != nil && effective == keychainTrimmed && (keychainTrimmed?.isEmpty == false) && fileTrimmed != effective`.
  - `saveErrorMessage`: nil when both true; otherwise a short sentence naming which store(s) failed.
  - `read`: read `fileURL`; trim; nil if missing or blank.
  - `write`: `createDirectory(at: directory, withIntermediateDirectories: true)`; write the trimmed secret (no trailing newline) atomically — POSIX `open(tmp, O_CREAT|O_WRONLY|O_TRUNC, 0o600)` where `tmp = directory.appendingPathComponent("proxy-secret.tmp-\(UUID().uuidString)")`, write bytes, `close`, then `rename(tmp, fileURL)`; on ANY failure clean up the temp and return `false` (never throw).
  - `loadAndSync`: `let fileValue = read(); let effective = Self.resolve(keychain: keychainSecret, file: fileValue)`; if `Self.shouldSyncFile(effective: effective, keychainTrimmed: keychainSecret?.trimmingCharacters(in: .whitespacesAndNewlines), fileTrimmed: fileValue?.trimmingCharacters(in: .whitespacesAndNewlines))` then `if !write(effective!) { os_log error }`; return `effective`. (Use `.trimmingCharacters(in: .whitespacesAndNewlines)` everywhere — there is no `.trimmed` helper in this codebase.)
  - Run: `TEST` Expected: PASS (all `ProxySecretStore` tests green). Commit (include `project.pbxproj` from T001/T002).
  - **Files:** `MMail/Mail/ProxySecretStore.swift`

- [ ] **T004 (SC: 006): `Keychain.storeProxySecret` reports success** — Change `setPassword(_:account:)` to `@discardableResult ... -> Bool` returning `SecItemAdd(...) == errSecSuccess` (existing mail-credential callers ignore it — verified discardable-safe). Change `storeProxySecret(_:) -> Bool`: returns `setPassword`'s result for the store branch, and `true` for the empty→delete branch.
  - Run: `BUILD` Expected: `** BUILD SUCCEEDED **`
  - **Files:** `MMail/Mail/Keychain.swift`

- [ ] **T005 (SC: 004, 005, 006): Wire `AppModel` through the resolver + per-store outcome** — In `MMail/State/AppModel.swift` (`import OSLog` if not present):
  - Add `func loadProxySecret() -> String? { ProxySecretStore.default.loadAndSync(keychainSecret: Keychain.readProxySecret()) }`.
  - `hasProxySecret` → `loadProxySecret() != nil`.
  - `imageProxyConfig` → replace inline `Keychain.readProxySecret()` with `guard let secret = loadProxySecret(), !secret.isEmpty`.
  - Add `@Published var proxySecretSaveError: String?`.
  - `setProxySecret(_:)`: `let kOK = Keychain.storeProxySecret(secret); let fOK = ProxySecretStore.default.write(secret)` (BOTH attempted regardless of the other); `proxySecretSaveError = ProxySecretStore.saveErrorMessage(keychainOK: kOK, fileOK: fOK)`; `os_log` on any failure; call `objectWillChange.send()` **after** the writes and the error assignment (so views read final state).
  - **Acknowledged & accepted (no change):** `imageProxyConfig`/`hasProxySecret` now do a small synchronous file read per render. This matches the existing Keychain-read-per-render behavior, is bounded, and the idempotent sync means no writes in steady state. Caching is a deliberate non-goal (YAGNI); revisit only if profiling shows it matters.
  - Run: `BUILD` Expected: `** BUILD SUCCEEDED **`
  - **Files:** `MMail/State/AppModel.swift`

- [ ] **T006 (SC: —): Settings copy fix + surface save failure** — In `MMail/Views/SettingsView.swift` "Image privacy proxy" section: **replace** the existing line `"The same secret you set with \`wrangler secret put PROXY_SECRET\`. Stored only in the macOS Keychain."` (SettingsView.swift:59) so it no longer claims Keychain-only — e.g. "…stored in the macOS Keychain and a local file (`~/Library/Application Support/MMail/`) so it survives rebuilds." When `model.proxySecretSaveError != nil`, render that message below the field in the warning/error color. Save button unchanged (still `model.setProxySecret`; disabled-on-empty stays). No contradictory text may remain.
  - Run: `BUILD` Expected: `** BUILD SUCCEEDED **`
  - Manual: Settings shows the single updated helper line; a normal Save shows no error.
  - **Files:** `MMail/Views/SettingsView.swift`

- [ ] **T007 (SC: —): Update local CLAUDE.md security note** — Change the project `CLAUDE.md` "Credentials are stored in the macOS Keychain only" line to note the image-proxy signing secret's low-sensitivity `0600` file fallback (HMAC key, not a mail credential). CLAUDE.md is git-excluded (`.git/info/exclude`) — local-only edit, no commit.
  - Run: n/a (doc)
  - **Files:** `CLAUDE.md` (local, untracked)

- [ ] **T008 (SC: 001–006): Full suite green + commit** — Run the full automated suite and commit any remaining changes.
  - **Coverage disclosure:** SC-006's file-write-failure half is automated (T002 `write`-fails + `saveErrorMessage` cases). The *live Keychain-write* failure half is NOT automatable — `SecItemAdd` has no injectable mock seam in this codebase — so it is covered structurally (both writes attempted independently; `saveErrorMessage` tested for the `keychainOK=false` input) and confirmed manually in `/verify`. SC-001 (unsigned rebuild + `wrangler tail` proxy-hit) is the manual exploration step, also in `/verify`.
  - Run: `TEST` Expected: all automated scenarios PASS
  - **Files:** (commit only — no new edits)
