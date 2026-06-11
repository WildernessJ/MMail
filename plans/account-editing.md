# account-editing Implementation Plan

**Goal:** Let a user rename an account, recolor its avatar tile, or replace it with a chosen image from Settings → Accounts, persisting across relaunches and flowing through the single derived `Account` so every avatar site stays consistent.

**Architecture:** Two additive `Optional` fields on `MailAccountConfig` (`avatarColorHex`, `hasCustomAvatar`) are the persisted source of truth; a pure, SwiftUI-free `AvatarSpec.resolve(...)` (new `MMail/Models/AvatarSpec.swift`) computes initials/gradient/usesImage and a pure `AvatarImage.squareCropRect(...)` computes the centered crop, both unit-tested. `AppModel.uiAccount(for:)` consumes the spec and, when `usesImage`, loads a fresh `NSImage` via the new `AvatarStore.default` (new `MMail/Mail/AvatarStore.swift`, mirroring `ProxySecretStore`); mutation APIs (`renameAccount`/`setAccountColor`/`setAccountImage`/`removeAccountImage`) rebuild exactly the one `accounts` entry and persist. `GradientTile` gains an optional image and all four account-avatar render sites pass the derived `Account`; a new `AccountEditRow` in `SettingsView` (mirroring `LabelEditRow`) drives the mutations.

**Test Methodology:** e2e-first (from `.harness.yaml`). The pure seams (`AvatarSpec.resolve`, `AvatarImage.squareCropRect`, additive-Codable round-trip) carry automatable coverage as hand-authored **swift-testing** suites in `MMailTests/` (the harness property-tests skill emits Python/hypothesis and is explicitly rejected here). Storage round-trip, GUI rendering, persistence-across-relaunch, and removal cleanup are live/manual verification finalized in /verify.

**Test commands:**
- Type-check / build: `xcodebuild -project MMail.xcodeproj -scheme MMail -configuration Debug build CODE_SIGNING_ALLOWED=NO`
- Unit tests: `xcodebuild test -project MMail.xcodeproj -scheme MMail -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO`
- New `.swift` files require `xcodegen generate` first, then commit the regenerated `MMail.xcodeproj/project.pbxproj` (project.yml globs the folders; pbxproj is git-tracked). Existing-file edits need no regenerate.

---

## Phase A — Data model + pure seams (automatable)

- [ ] **T001 (SC: 005): Add additive Codable fields to MailAccountConfig** — In `MMail/Mail/MailAccountConfig.swift`, inside `struct MailAccountConfig` (after `var smtpUsername: String` at line 32, before the computed `imapPasswordKey` at line 34), add two stored properties **WITH `= nil` defaults**: `var avatarColorHex: String? = nil` and `var hasCustomAvatar: Bool? = nil`. The `= nil` defaults are REQUIRED: without them the synthesized memberwise initializer gains two new required parameters, and the sole construction site `ManualAccountSetupView.swift:249` (which passes only the 11 current fields) would fail to compile with "missing argument for parameter 'avatarColorHex'". (`= nil` is fully additive-Codable-compatible — synthesized `Codable` still decodes absent keys to `nil`.) Do NOT add an explicit `CodingKeys` or custom `init(from:)`. Existing-file edit; no regenerate.
  - Run: `xcodebuild -project MMail.xcodeproj -scheme MMail -configuration Debug build CODE_SIGNING_ALLOWED=NO`
  - Expected: PASS (compiles; the `= nil` defaults keep `ManualAccountSetupView.swift:249` and every other construction site building unchanged — no new required arguments)
  - **Files:** `MMail/Mail/MailAccountConfig.swift`

- [ ] **T002 (SC: 007): Define pure AvatarSpec + AvatarImage types (stubbed)** — Create `MMail/Models/AvatarSpec.swift` with `import Foundation` ONLY (no SwiftUI/AppKit). Add `struct AvatarSpec { let initials: String; let gradientHex: [String]; let usesImage: Bool; static func resolve(displayName: String, email: String, customColorHex: String?, hasImage: Bool) -> AvatarSpec }` returning a stub (`AvatarSpec(initials: "", gradientHex: [], usesImage: false)`). Add `enum AvatarImage { static func squareCropRect(sourceWidth: CGFloat, sourceHeight: CGFloat) -> CGRect }` returning a stub (`.zero`). `CGRect`/`CGFloat` come from `CoreGraphics` (re-exported by `Foundation` on Apple platforms) — do NOT import SwiftUI. Then `xcodegen generate` (new file) and build.
  - Run: `xcodegen generate && xcodebuild -project MMail.xcodeproj -scheme MMail -configuration Debug build CODE_SIGNING_ALLOWED=NO`
  - Expected: PASS (compiles; `project.pbxproj` now lists `AvatarSpec.swift`)
  - **Files:** `MMail/Models/AvatarSpec.swift` (new), `MMail.xcodeproj/project.pbxproj` (regenerated)

- [ ] **T003 (SC: 007): Failing unit tests for the pure seams + additive Codable** — Create `MMailTests/AvatarSpecTests.swift` (`import Testing`, `import Foundation`, `@testable import MMail`, `@Suite struct AvatarSpecTests`). Encode every spec pure scenario:
  - AvatarSpec: `resolve(displayName: "Jane Doe", email: "jane@x.org", customColorHex: nil, hasImage: false)` → `initials == "J"`, `gradientHex == [Sender.stableColorHex(for: "jane@x.org"), "1E2DB0"]`, `usesImage == false`.
  - Custom color: `resolve(... customColorHex: "E5484D", hasImage: false)` → `gradientHex == ["E5484D", "E5484D"]`, `initials == "J"`.
  - Empty name → email fallback: `resolve(displayName: "   ", email: "jane@x.org", customColorHex: nil, hasImage: false)` → `initials == "J"`.
  - Image flag overrides render but color still resolved: `resolve(... customColorHex: "E5484D", hasImage: true)` → `usesImage == true`, `gradientHex == ["E5484D", "E5484D"]`.
  - squareCropRect: wide `(800, 400)` → `CGRect(x: 200, y: 0, width: 400, height: 400)`; tall `(300, 900)` → `CGRect(x: 0, y: 300, width: 300, height: 300)`; square `(500, 500)` → `CGRect(x: 0, y: 0, width: 500, height: 500)`.
  - Additive-Codable: decode a hand-written pre-feature JSON string (a full `MailAccountConfig` blob with NEITHER `avatarColorHex` NOR `hasCustomAvatar` keys) → `cfg.avatarColorHex == nil` AND `cfg.hasCustomAvatar == nil`. Round-trip: a `MailAccountConfig` with `avatarColorHex = "1FB36B"`, `hasCustomAvatar = true` JSON-encoded then decoded preserves both values.

    Then `xcodegen generate` (new test file) and run tests.
  - Run: `xcodegen generate && xcodebuild test -project MMail.xcodeproj -scheme MMail -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO`
  - Expected: FAIL — AvatarSpec/squareCropRect assertions fail because the stubs return empty/`.zero` ("not implemented"); the Codable assertions may already pass (that is fine — the suite as a whole fails)
  - **Files:** `MMailTests/AvatarSpecTests.swift` (new), `MMail.xcodeproj/project.pbxproj` (regenerated)

- [ ] **T004 (SC: 007): Implement the pure seams + commit** — In `MMail/Models/AvatarSpec.swift`:
  - `AvatarSpec.resolve`: `let trimmedName = displayName.trimmingCharacters(in: .whitespaces)`; `let source = trimmedName.isEmpty ? email : trimmedName`; `let initials = String(source.prefix(1)).uppercased()` (KEEP `prefix(1)` — it is grapheme-correct; do NOT use `unicodeScalars`); `let gradientHex = customColorHex.map { [$0, $0] } ?? [Sender.stableColorHex(for: email), "1E2DB0"]`; return with `usesImage: hasImage`.
  - `AvatarImage.squareCropRect`: `let edge = min(sourceWidth, sourceHeight)`; `let x = (sourceWidth - edge) / 2`; `let y = (sourceHeight - edge) / 2`; return `CGRect(x: x, y: y, width: edge, height: edge)`. (This rect is in TOP-LEFT origin coordinates, the convention of `CGImage.cropping(to:)`.)

    Make T003 green, then commit.
  - Run: `xcodebuild test -project MMail.xcodeproj -scheme MMail -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO`
  - Expected: PASS (all AvatarSpecTests green; existing suites still green)
  - **Files:** `MMail/Models/AvatarSpec.swift`

- [ ] **T005 (SC: 005): Refactor uiAccount to consume AvatarSpec (value-preserving) + commit** — In `MMail/State/AppModel.swift`, rewrite `static func uiAccount(for cfg:)` (lines 1547–1553) to consume the seam without changing output for un-customized configs: `let spec = AvatarSpec.resolve(displayName: cfg.displayName, email: cfg.email, customColorHex: cfg.avatarColorHex, hasImage: cfg.hasCustomAvatar ?? false)`; `let display = cfg.displayName.isEmpty ? cfg.email : cfg.displayName`; build `Account(id: cfg.id, name: display, email: cfg.email, initials: spec.initials, gradient: spec.gradientHex, colorHex: spec.gradientHex.first ?? Sender.stableColorHex(for: cfg.email), provider: "IMAP / SMTP")`. Do NOT load the image yet (that needs `AvatarStore`, added in Phase B) — leave a `// TODO Phase B: load image when spec.usesImage` marker. The function stays `static`. Build, then commit Phase A.
  - Run: `xcodebuild -project MMail.xcodeproj -scheme MMail -configuration Debug build CODE_SIGNING_ALLOWED=NO`
  - Expected: PASS (compiles; for a `nil`/`nil` config, `initials`, `gradient`, and `colorHex` are byte-identical to the old derivation)
  - **Files:** `MMail/State/AppModel.swift`

---

## Phase B — Storage + image-capable rendering + mutation API

- [ ] **T006 (SC: 003): Create AvatarStore (stubbed) + AvatarImage crop helper site** — Create `MMail/Mail/AvatarStore.swift` (`import Foundation`, `import AppKit`, `import OSLog`). Mirror `ProxySecretStore`: `struct AvatarStore { let directory: URL }`, a private `static let log`, `var directory`'s per-id file via `func fileURL(for id: String) -> URL { directory.appendingPathComponent("\(id).png") }`, and `static let default = AvatarStore(directory: try! FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: false).appendingPathComponent("MMail").appendingPathComponent("avatars"))`. Declare three methods returning stubs for now: `@discardableResult func save(_ image: NSImage, for id: String) -> Bool { false }`, `func load(for id: String) -> NSImage? { nil }`, `@discardableResult func remove(for id: String) -> Bool { false }`. Then `xcodegen generate` (new file) and build.
  - Run: `xcodegen generate && xcodebuild -project MMail.xcodeproj -scheme MMail -configuration Debug build CODE_SIGNING_ALLOWED=NO`
  - Expected: PASS (compiles; `project.pbxproj` lists `AvatarStore.swift`)
  - **Files:** `MMail/Mail/AvatarStore.swift` (new), `MMail.xcodeproj/project.pbxproj` (regenerated)

- [ ] **T007 (SC: 003): Implement AvatarStore save/load/remove + commit** — In `MMail/Mail/AvatarStore.swift`:
  - `save`: create `directory` (`try? FileManager.default.createDirectory(at:withIntermediateDirectories: true)`); obtain the `CGImage` with an EXPLICIT guard (the method returns `CGImage?` — do NOT force-unwrap): `guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { Self.log.error("avatar: no CGImage"); return false }`; compute the centered crop via `AvatarImage.squareCropRect(sourceWidth: CGFloat(cg.width), sourceHeight: CGFloat(cg.height))`; crop with `guard let cropped = cg.cropping(to: rect) else { return false }` (the REQUIRED top-left-origin mechanism — NOT a flipped `NSImage.draw`). Then **downscale + PNG-encode via the codebase's `NSImage`/`NSBitmapImageRep` idiom — NOT a raw `CGContext`** (a hand-rolled `CGContext(...)` needs exact colorSpace/bitmapInfo params and returns nil if they are wrong; avoid it):
    - `let targetEdge = min(cropped.width, 256)` (the crop is square so width == height; this never upscales).
    - Draw the cropped image scaled into a square bitmap: `let out = NSImage(size: NSSize(width: targetEdge, height: targetEdge))`; `out.lockFocus()`; `NSGraphicsContext.current?.imageInterpolation = .high`; `NSImage(cgImage: cropped, size: .zero).draw(in: NSRect(x: 0, y: 0, width: targetEdge, height: targetEdge), from: .zero, operation: .copy, fraction: 1)`; `out.unlockFocus()`. (`lockFocus` is main-thread-only — our synchronous-on-main invariant covers it; it builds its own backing context, so there are NO colorSpace/bitmapInfo params to get wrong.)
    - PNG-encode exactly like `ComposeView.swift:110-112`: `guard let tiff = out.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff), let data = rep.representation(using: .png, properties: [:]) else { return false }`.
    - Write: `do { try data.write(to: fileURL(for: id)); return true } catch { Self.log.error("avatar: write failed \(error.localizedDescription)"); return false }`.

    Return `false` (logged) on ANY nil/throw; never force-unwrap, never crash.
  - `load`: `guard let data = try? Data(contentsOf: fileURL(for: id)) else { return nil }`; `return NSImage(data: data)` — build a FRESH `NSImage` from the freshly-read `Data` on EVERY call (no `NSImage(named:)`, no instance/name cache), so a replaced file always loads its new bytes.
  - `remove`: `try? FileManager.default.removeItem(at: fileURL(for: id))`; return success flag; missing-file is not an error.

    Commit.
  - Run: `xcodebuild -project MMail.xcodeproj -scheme MMail -configuration Debug build CODE_SIGNING_ALLOWED=NO`
  - Expected: PASS (compiles; save/load round-trip is exercised live in Phase D, not unit-tested here)
  - **Files:** `MMail/Mail/AvatarStore.swift`

- [ ] **T008 (SC: 003): Add Account.avatarImage + load it in uiAccount + commit** — In `MMail/Models/Models.swift`, in `struct Account` (after `let provider: String` at line 27), add `var avatarImage: NSImage? = nil` **WITH the `= nil` default** (this adds NO conformance — `Account` stays non-`Codable`/`Equatable`/`Hashable`; it is never compared by value, SwiftUI diffs `accounts` by `id`). The `= nil` default is REQUIRED: there are OTHER `Account(...)` construction sites besides `uiAccount` — three struct literals in `SampleData.swift:44,47,50` (`work`/`personal`/`freelance`) — which would otherwise fail to compile with "missing argument for parameter 'avatarImage'". With the default they build unchanged. `Models.swift` already `import SwiftUI`, so `NSImage` is in scope. In `MMail/State/AppModel.swift` `uiAccount(for:)`, replace the Phase-A TODO: build the `Account` with `avatarImage: spec.usesImage ? AvatarStore.default.load(for: cfg.id) : nil`. Commit.
  - Run: `xcodebuild -project MMail.xcodeproj -scheme MMail -configuration Debug build CODE_SIGNING_ALLOWED=NO`
  - Expected: PASS (compiles; `uiAccount` passes `avatarImage`; the `SampleData.swift` literals build via the `= nil` default — no call site breaks)
  - **Files:** `MMail/Models/Models.swift`, `MMail/State/AppModel.swift`

- [ ] **T009 (SC: 003): Extend GradientTile for images + commit** — In `MMail/Components/Atoms.swift`, add `var image: NSImage? = nil` to `struct GradientTile` (after `var fontSize: CGFloat = 14` at line 102). In `body`, when `image != nil` render `Image(nsImage: image!).resizable().scaledToFill().frame(width: size, height: size).clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))` INSTEAD of the gradient+text tile; otherwise render today's gradient `Text` tile unchanged. Use an `if let img = image { … } else { … }` branch so the default-`nil` callers are untouched. `Atoms.swift` already `import SwiftUI`. Commit.
  - Run: `xcodebuild -project MMail.xcodeproj -scheme MMail -configuration Debug build CODE_SIGNING_ALLOWED=NO`
  - Expected: PASS (compiles; existing `GradientTile(colors:text:...)` calls compile unchanged because `image` defaults to `nil`)
  - **Files:** `MMail/Components/Atoms.swift`

- [ ] **T010 (SC: 003): Point the four account-avatar sites at the image tile + commit** — Pass the derived `Account.avatarImage` at each account site (NON-account tiles untouched):
  - `MMail/Views/AccountRailView.swift:28` — `GradientTile(colors: a.gradientColors, text: a.initials, size: 38, image: a.avatarImage)`.
  - `MMail/Views/SidebarView.swift:135-136` — this is ONE `GradientTile` call gated by an `isAll` ternary; `acct` is `Account?`. Add `image: isAll ? nil : acct?.avatarImage` as a new argument. (`acct?.avatarImage` is `NSImage?` not `NSImage??` — Swift optional chaining flattens, so it matches `GradientTile`'s `image: NSImage?` parameter.) The `isAll` "All inboxes" branch (hardcoded `"M"` + fixed colors) MUST stay image-less — only the per-account (non-`isAll`) branch gets the image.
  - `MMail/Views/ComposeView.swift:243` — `GradientTile(colors: acct.gradientColors, text: acct.initials, size: 18, cornerRadius: 5, fontSize: 10, image: acct.avatarImage)`.
  - `MMail/Views/ComposeView.swift:261` — `GradientTile(colors: a.gradientColors, text: a.initials, size: 22, cornerRadius: 6, fontSize: 11, image: a.avatarImage)`.

    Commit.
  - Run: `xcodebuild -project MMail.xcodeproj -scheme MMail -configuration Debug build CODE_SIGNING_ALLOWED=NO`
  - Expected: PASS (compiles; the unified "All", "you" reader, and sender avatars are unaffected — none touched)
  - **Files:** `MMail/Views/AccountRailView.swift`, `MMail/Views/SidebarView.swift`, `MMail/Views/ComposeView.swift`

- [ ] **T011 (SC: 001, 002, 003, 004): Add mutation API + rebuild helper + commit** — In `MMail/State/AppModel.swift`, near `uiAccount`/`persistRealAccounts` (~1553), add a private rebuild-one helper and four mutation funcs. All run SYNCHRONOUSLY on the main thread (called from SwiftUI actions); `NSImage` NEVER crosses a `Task`/actor boundary.
  - `private func rebuildAccount(_ id: String) { guard let cfg = config(for: id), let i = accounts.firstIndex(where: { $0.id == id }) else { return }; accounts[i] = AppModel.uiAccount(for: cfg) }` — replaces EXACTLY the one matching entry.
  - `func renameAccount(_ id: String, to newName: String) { guard let i = realConfigs.firstIndex(where: { $0.id == id }) else { return }; realConfigs[i].displayName = newName.trimmingCharacters(in: .whitespaces); rebuildAccount(id); persistRealAccounts() }`
  - `func setAccountColor(_ id: String, hex: String) { guard let i = realConfigs.firstIndex(where: { $0.id == id }) else { return }; realConfigs[i].avatarColorHex = hex; rebuildAccount(id); persistRealAccounts() }`
  - `func setAccountImage(_ id: String, _ image: NSImage) { guard let i = realConfigs.firstIndex(where: { $0.id == id }) else { return }; AvatarStore.default.save(image, for: id); realConfigs[i].hasCustomAvatar = true; rebuildAccount(id); persistRealAccounts() }` (save first so the subsequent `uiAccount` load finds the file).
  - `func removeAccountImage(_ id: String) { guard let i = realConfigs.firstIndex(where: { $0.id == id }) else { return }; AvatarStore.default.remove(for: id); realConfigs[i].hasCustomAvatar = false; rebuildAccount(id); persistRealAccounts() }`

    Commit.
  - Run: `xcodebuild -project MMail.xcodeproj -scheme MMail -configuration Debug build CODE_SIGNING_ALLOWED=NO`
  - Expected: PASS (compiles; editing one account mutates only its `realConfigs` slot and its one `accounts` entry — others untouched)
  - **Files:** `MMail/State/AppModel.swift`

- [ ] **T012 (SC: 006): Clean up avatar file on account removal + commit** — In `MMail/State/AppModel.swift` `removeRealAccount(_:)` (lines 1508–1528), add `AvatarStore.default.remove(for: accountId)` alongside the other per-account teardown (e.g. right after `MailCache.clear(account: accountId)` at line 1512), so removing an account leaves no orphaned `<id>.png`. Commit Phase B.
  - Run: `xcodebuild -project MMail.xcodeproj -scheme MMail -configuration Debug build CODE_SIGNING_ALLOWED=NO`
  - Expected: PASS (compiles)
  - **Files:** `MMail/State/AppModel.swift`

---

## Phase C — Settings editing UI

- [ ] **T013 (SC: 001, 002, 003, 004): Create AccountEditRow + commit** — In `MMail/Views/SettingsView.swift`, add `struct AccountEditRow: View` mirroring `LabelEditRow` (lines 376–421). `@EnvironmentObject var model: AppModel`, `@Environment(\.palette) var p`, `let cfg: MailAccountConfig`, `@State private var name = ""`, `@State private var colorOpen = false`, `@State private var imageOpen = false`. Derive the row's live `Account` via `let acct = model.accountsById[cfg.id] ?? AppModel.uiAccount(for: cfg)` — `accountsById` is a computed property on `AppModel` (`AppModel.swift:306`) that always contains a configured account, so the `??` is only a compile-time non-optional guarantee (it never actually fires). Layout (`HStack`):
  - Avatar preview: `GradientTile(colors: acct.gradientColors, text: acct.initials, size: 32, image: acct.avatarImage)`.
  - Inline name `TextField("Account name", text: $name)` (plain style) with `.onSubmit { model.renameAccount(cfg.id, to: name) }`; `.onAppear { name = cfg.displayName }` and `.onChange(of: cfg.displayName) { _, v in name = v }`.
  - Color swatch button (shown ONLY when `cfg.hasCustomAvatar != true` — color is moot while an image renders): a small circle filled `acct.color`, `.popover(isPresented: $colorOpen)` presenting a `LazyVGrid` over `AppModel.labelPalette` (10 swatches, mirror `LabelEditRow.swatches`) each calling `model.setAccountColor(cfg.id, hex: hex); colorOpen = false`.
  - Image controls: a **Choose image…** button → `chooseImage()` (T014); a **Use letters** button shown ONLY when `cfg.hasCustomAvatar == true` → `model.removeAccountImage(cfg.id)`.
  - Retain **Resync** (`model.loadFolder(cfg.id, "inbox", force: true)`) and **Remove** (`model.removeRealAccount(cfg.id)`) buttons (copy from the current Accounts HStack at lines 98–107).

    Add a placeholder `private func chooseImage() {}` for now (filled in T014). Commit.
  - Run: `xcodebuild -project MMail.xcodeproj -scheme MMail -configuration Debug build CODE_SIGNING_ALLOWED=NO`
  - Expected: PASS (compiles; `AccountEditRow` is defined but not yet wired into the section)
  - **Files:** `MMail/Views/SettingsView.swift`

- [ ] **T014 (SC: 003): Implement the native image picker + commit** — In `AccountEditRow.chooseImage()`, present a native `NSOpenPanel`: `let panel = NSOpenPanel(); panel.allowedContentTypes = [.png, .jpeg, .image]` (`import UniformTypeIdentifiers` at top of file if not present); `panel.allowsMultipleSelection = false`; `panel.canChooseDirectories = false`; on `panel.runModal() == .OK`, `guard let url = panel.url, let img = NSImage(contentsOf: url) else { return }`; call `model.setAccountImage(cfg.id, img)`. This runs synchronously on the main thread; the `NSImage` never crosses a `Task` boundary. Commit.
  - Run: `xcodebuild -project MMail.xcodeproj -scheme MMail -configuration Debug build CODE_SIGNING_ALLOWED=NO`
  - Expected: PASS (compiles; the panel itself is exercised live in Phase D)
  - **Files:** `MMail/Views/SettingsView.swift`

- [ ] **T015 (SC: 001, 002, 003, 004): Wire AccountEditRow into the Accounts section + commit** — In `MMail/Views/SettingsView.swift`, in the `section("Accounts")` `ForEach` (lines 91–110), REPLACE the inline `HStack { … Resync … Remove … }` (lines 92–108) with `AccountEditRow(cfg: cfg).environmentObject(model)` (the `@EnvironmentObject` propagates automatically, so `.environmentObject` is belt-and-suspenders — confirm it compiles either way), keeping the inter-row divider at line 109 and the "Add account" button below (lines 112–116) unchanged. Commit Phase C.
  - Run: `xcodebuild -project MMail.xcodeproj -scheme MMail -configuration Debug build CODE_SIGNING_ALLOWED=NO`
  - Expected: PASS (compiles; the Accounts section now renders one `AccountEditRow` per account)
  - **Files:** `MMail/Views/SettingsView.swift`

- [ ] **T016 (SC: 007, 008): Full test + build gate before manual verification** — Run the full unit suite and a clean build to confirm nothing regressed across Phases A–C.
  - Run: `xcodebuild test -project MMail.xcodeproj -scheme MMail -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO`
  - Expected: PASS (AvatarSpecTests green; all pre-existing suites green; no compile warnings escalated to errors)
  - **Files:** none (gate only)

---

## Phase D — Live verification (manual; finalized in /verify)

- [ ] **T017 (SC: 001): Rename persists across relaunch + updates all four sites** — Launch the test build, open Settings → Accounts, rename an account (e.g. "Personal" → "Work") and press Return. Confirm the rail tile, sidebar header, and BOTH compose surfaces (From field + From popover) show the new name and "W" initials. ⌘Q and relaunch; confirm the new name/initials persist.
  - Run: manual — launch the test build, edit + relaunch
  - Expected: name + initials update everywhere and survive relaunch
  - **Files:** none (verification only)

- [ ] **T018 (SC: 002): Color pick recolors every site, solid fill, survives relaunch** — In the same row (no image set), open the color popover and pick a swatch (e.g. green `1FB36B`). Confirm the avatar tile is a SOLID fill of that color at the rail, sidebar header, and both compose surfaces. Relaunch; confirm the color persists.
  - Run: manual — pick a color, relaunch
  - Expected: solid-color tile everywhere, persists
  - **Files:** none (verification only)

- [ ] **T019 (SC: 003): Choose an image — stored, cropped, rendered everywhere, persists** — Click **Choose image…**, select a non-square PNG/JPEG. Confirm the image (center-cropped, clipped to the rounded tile) appears at all four account sites and a **Use letters** control appears. Confirm a PNG exists at `~/Library/Application Support/MMail/avatars/<id>.png` and is ≤256px on its long edge. Replace it with a DIFFERENT image and confirm the NEW image renders (no stale cache). Relaunch; confirm the image persists.
  - Run: manual — choose image, replace, inspect file, relaunch; `ls -la ~/Library/Application\ Support/MMail/avatars/`
  - Expected: cropped image renders everywhere, file present + small, replace shows new image, persists
  - **Files:** none (verification only)

- [ ] **T020 (SC: 004): Use letters reverts to the tile and deletes the PNG** — With an image set, click **Use letters**. Confirm the letters-and-color tile returns at every site and the swatch popover reappears. Confirm the PNG at `…/avatars/<id>.png` is gone.
  - Run: manual — click Use letters; `ls ~/Library/Application\ Support/MMail/avatars/`
  - Expected: letters tile returns; PNG deleted
  - **Files:** none (verification only)

- [ ] **T021 (SC: 005): Pre-feature account loads unchanged** — Before building this feature, capture a screenshot of an existing (pre-feature) account's avatar. After the feature ships, relaunch WITHOUT editing that account; confirm its initials and email-hash-derived color are identical to the captured baseline and no decode error/cache wipe occurred (mail still listed). (If no genuine pre-feature blob remains, simulate by hand-writing a `kRealAccounts` UserDefaults JSON lacking the two new keys and relaunching.)
  - Run: manual — relaunch with a pre-feature config, compare appearance
  - Expected: identical appearance; no error; no cache wipe
  - **Files:** none (verification only)

- [ ] **T022 (SC: 006): Removing an account deletes its avatar file** — Set an image on a (disposable/test) account so its PNG exists, then click **Remove**. Confirm no `…/avatars/<id>.png` remains for that id.
  - Run: manual — set image, remove account; `ls ~/Library/Application\ Support/MMail/avatars/`
  - Expected: that account's PNG is gone (no orphan)
  - **Files:** none (verification only)

---

## Notes for the build engineer
- **Additive-Codable, no cache wipe (SC-005):** the two new `MailAccountConfig` fields are `Optional` with synthesized `Codable` — absent JSON keys decode to `nil`. Do NOT add a custom `CodingKeys`/`init(from:)`, a migration step, or any cache clear. A pre-feature config must behave exactly as today.
- **`= nil` defaults are mandatory on BOTH new stored properties** (`MailAccountConfig.avatarColorHex`/`hasCustomAvatar` AND `Account.avatarImage`). Swift's synthesized memberwise initializer does NOT auto-default Optionals — without `= nil` it adds required parameters that break existing construction sites: `ManualAccountSetupView.swift:249` (`MailAccountConfig`) and `SampleData.swift:44,47,50` (three `Account` literals). The `= nil` default keeps every existing constructor compiling untouched and is fully Codable-compatible.
- **`prefix(1)` is grapheme-correct:** keep `String(source.prefix(1)).uppercased()` for initials. Do NOT "fix" it to `unicodeScalars.first` — that splits emoji/combined graphemes. This matches today's `uiAccount`.
- **Threading invariant:** image decode + crop + downscale + PNG-encode + file writes run SYNCHRONOUSLY on the main thread as a one-shot user action. `AppModel` is not `@MainActor` but mutates state on main by convention; `NSImage` must NEVER be sent across a `Task`/actor boundary. The project is Swift 5 language mode (`project.yml SWIFT_VERSION "5.0"`) so `NSImage`'s non-`Sendable`ness is at most a warning — the synchronous-main-thread rule keeps it a non-issue.
- **Fresh load on every rebuild (no stale image):** `AvatarStore.load(for:)` reads `Data` fresh and builds a NEW `NSImage(data:)` each call. NEVER use `NSImage(named:)` or any name/URL-keyed cache — replacing the file at `<id>.png` must always render the new image (SC-003 replace scenario).
- **`CGImage.cropping(to:)` top-left convention:** `AvatarImage.squareCropRect` returns a TOP-LEFT-origin rect; crop via `cg.cropping(to: rect)`, NOT a flipped `NSImage.draw(in:from:)`. For this always-centered crop the offset `(longer − shorter)/2` is symmetric, but do NOT treat origin as "don't care".
- **Downscale, don't upscale:** target edge is `min(croppedEdge, 256)` — only shrink sources larger than 256px; leave smaller sources at their native edge.
- **xcodegen for new files only:** T002 (`AvatarSpec.swift`), T003 (`AvatarSpecTests.swift`), and T006 (`AvatarStore.swift`) each add a NEW `.swift` file → run `xcodegen generate` and commit the regenerated `project.pbxproj` WITH that task. All other tasks edit existing files (no regenerate, no pbxproj change). Do not regenerate gratuitously — it dirties the tree.
- **Sidebar isAll-branch caution:** `SidebarView.swift:135-136` is a SINGLE `GradientTile` call switched by an `isAll` ternary. ONLY the per-account (non-`isAll`) branch gets `image:`; the "All inboxes" `"M"` tile must stay image-less. Pass `image: isAll ? nil : acct?.avatarImage`.
- **Non-account tiles untouched:** only the four named account sites change. The unified "All" tile, the "you" reader avatar, and sender avatars (the `Avatar`/`Sender` components) must be left exactly as-is.
- **Per-task ordering (e2e-first):** types → failing test → implementation + commit. The only seams with automatable tests are `AvatarSpec`/`AvatarImage`/Codable (Phase A T002→T003→T004). Storage and UI are type-check + manual-verify only.
