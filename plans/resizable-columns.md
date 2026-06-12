# resizable-columns Implementation Plan

**Goal:** Add a 3-way sidebar size preset (icon-only / today / roomier) with a View-menu submenu + `⌘⇧L`, and a draggable mail-list↔reader divider, both persisted and additive (defaults reproduce today's layout exactly).

**Architecture:** All sizing logic lives in two pure, view-free seams in a new `MMail/State/LayoutSizing.swift` (`SidebarSize` enum + `clampListWidth`), unit-tested in isolation (swift-testing). `AppModel` holds the two `@Published` values and persists them via the existing `persistTweaks`/`UserDefaults` pattern (with a targeted single-key write for the per-drag path). The views (`SidebarView`, `EmailListView`, `RootView`, `MMailApp`) read those seams; the "Sidebar Size" submenu is stateful SwiftUI added directly in `MMailApp`'s `CommandGroup` (NOT routed through the pure `MenuModel`). The drag handle is a private view inline in `RootView` (no new file → only one `xcodegen` regen).

**Test Methodology:** e2e-first (from `.harness.yaml`).

**Swift / worktree caveats (read before building):**
- Working tree: worktree `.worktrees/resizable-columns`, branch `feat/resizable-columns`, isolated `.harness.yaml` (`current_feature: resizable-columns`). The main checkout is mid-`dark-engine` in another session — do NOT touch it or its `.harness.yaml`.
- **Per-phase gate = `xcodebuild … build-for-testing CODE_SIGNING_ALLOWED=NO`** run FROM THE WORKTREE. This compiles the app AND the `MMailTests` bundle without launching, so it does NOT hit the worktree `xcodebuild test` LaunchServices hang (see `project_worktree-xctest-hang`). It is the gate for every phase.
- **The actual test RUN (`xcodebuild … test`) is DEFERRED to the main checkout** (T017), because (a) `test` hangs from a worktree and (b) the main checkout is currently busy with the dark-engine session. Tests are authored now and run from the main checkout at /verify once that checkout is free; they are expected to PASS.
- Adding the two new files (`LayoutSizing.swift`, `LayoutSizingTests.swift`) requires `xcodegen generate` (project globs `sources: - path: MMail` / `MMailTests`) then committing the regenerated `MMail.xcodeproj/project.pbxproj`. Only ONE regen is needed (both new files land in Phase A); everything else edits existing files or adds a private inline struct.
- Build dispatched to a single Opus subagent (per CLAUDE.md). Reviews are opposite-model (Sonnet).

---

## Phase A — Pure layout-sizing seams + unit tests

- [ ] **T001 (SC: 006, 007): Define the pure seams** — Create `MMail/State/LayoutSizing.swift`: `import Foundation` (for `UserDefaults`/`CGFloat`); `enum SidebarSize: String, CaseIterable { case small, medium, large }` with `var width: CGFloat` (`small ≈ 64`, `medium == 232`, `large ≈ 280` — small/large are visual-tunable, only `medium == 232` is contractual), `var showsLabels: Bool` (`small → false`, else `true`), `var next: SidebarSize` (small→medium→large→small); free func `clampListWidth(_ raw: CGFloat) -> CGFloat { min(max(raw, 300), 600) }`. Also add the CANONICAL persistence keys + two keyless, UserDefaults-injectable LOAD accessors (so the same key is used for read AND write — a write/read key mismatch becomes structurally impossible — and the load path is unit-testable WITHOUT constructing `AppModel`):
  - `enum LayoutDefaultsKey { static let sidebarSize = "mmail.sidebarSize"; static let listWidth = "mmail.listWidth" }`
  - `func loadSidebarSize(_ d: UserDefaults) -> SidebarSize { SidebarSize(rawValue: d.string(forKey: LayoutDefaultsKey.sidebarSize) ?? "") ?? .medium }`
  - `func loadListWidth(_ d: UserDefaults) -> CGFloat { clampListWidth((d.object(forKey: LayoutDefaultsKey.listWidth) as? Double).map { CGFloat($0) } ?? 380) }`
  All persist sites (T007/T008) MUST write via these same `LayoutDefaultsKey` constants. The accessors delegate clamping/parsing entirely to `clampListWidth`/`SidebarSize` (no sizing logic of their own).
  **Files:** `MMail/State/LayoutSizing.swift`
  Run: (compiles under the Phase-A gate, T004) Expected: type resolves.

- [ ] **T002 (SC: 006, 007): Author the unit tests** — Create `MMailTests/LayoutSizingTests.swift` (`import Testing`, `import Foundation`, `@testable import MMail`). `@Suite` with `@Test`s asserting:
  - `SidebarSize`: `medium.width == 232` and `.showsLabels`; `.small.showsLabels == false` and `.small.width < .medium.width`; `.small.width < .medium.width && .medium.width < .large.width`; `.large.showsLabels`; cycle `small.next==medium, medium.next==large, large.next==small`; rawValue round-trip for all 3 cases and `SidebarSize(rawValue:"huge") == nil`.
  - `clampListWidth`: `380→380, 120→300, 5000→600, 300→300, 600→600`.
  - **Load path via an injected `UserDefaults`**, writing through the REAL `LayoutDefaultsKey` constants (covers SC-007's load-path promise + the "corrupt persisted values" + "defaults" scenarios, without constructing `AppModel`; using the canonical keys means the test round-trips the same key shape AppModel persists with): make a throwaway suite `let d = UserDefaults(suiteName: "test.resizable.\(UUID())")!`; assert unset defaults `loadSidebarSize(d) == .medium` and `loadListWidth(d) == 380`; `d.set("small", forKey: LayoutDefaultsKey.sidebarSize); #expect(loadSidebarSize(d) == .small)`; `d.set("huge", forKey: LayoutDefaultsKey.sidebarSize); #expect(loadSidebarSize(d) == .medium)`; `d.set(9999.0, forKey: LayoutDefaultsKey.listWidth); #expect(loadListWidth(d) == 600)` (clamp-on-load); `d.set(420.0, forKey: LayoutDefaultsKey.listWidth); #expect(loadListWidth(d) == 420)`. (`removePersistentDomain(forName:)` in teardown if needed.) NOTE: this tests the load direction + key shape; the WRITE wiring (`persistTweaks`/`setListWidth` actually calling `d.set`) is live-verified at T018, per SC-007.
  **Files:** `MMailTests/LayoutSizingTests.swift`
  Run: (compiles under T004; runs at T017) Expected: test bundle compiles; asserts pass when run from main checkout.

- [ ] **T003 (SC: 007): Regenerate project to include the new files** — Run: `xcodegen generate` (from the worktree). Stage the regenerated project. Expected: `MMail.xcodeproj/project.pbxproj` now references both `LayoutSizing.swift` and `LayoutSizingTests.swift`.
  **Files:** `MMail.xcodeproj/project.pbxproj`
  Run: `xcodegen generate && git add MMail.xcodeproj/project.pbxproj` Expected: both new paths appear in `git diff --cached project.pbxproj`.

- [ ] **T004 (SC: 006, 007): Compile gate + commit Phase A** — Run (worktree): `xcodebuild -project MMail.xcodeproj -scheme MMail -configuration Debug build-for-testing CODE_SIGNING_ALLOWED=NO` Expected: `** BUILD SUCCEEDED **` (app + MMailTests bundle compile). Commit: `feat(resizable-columns): SidebarSize + clampListWidth + load helpers + tests (phase A)`.
  **Files:** (commit only)

> **Review checkpoint after Phase A** (looped Sonnet review of the pure seams + tests).

## Phase B — AppModel state + persistence

- [ ] **T005 (SC: 007): Add state** — In `AppModel`: add `@Published var sidebarSize: SidebarSize` and `@Published var listWidth: CGFloat`. Do NOT add new key consts in `AppModel` — use the canonical `LayoutDefaultsKey.sidebarSize` / `.listWidth` from `LayoutSizing.swift` everywhere (so read and write can never diverge).
  **Files:** `MMail/State/AppModel.swift`
  Run: (gate T009) Expected: compiles.

- [ ] **T006 (SC: 001, 006, 007): Init load with defaults + clamp** — In the init UserDefaults block (~`AppModel.swift:233-237`): `sidebarSize = loadSidebarSize(d)`; `listWidth = loadListWidth(d)` (the T001 keyless helpers — identical logic to what T002 unit-tests). (Unknown size → `.medium`; out-of-range/missing width → clamped/380.)
  **Files:** `MMail/State/AppModel.swift`
  Run: (gate T009) Expected: compiles; default path yields `.medium` / `380`.

- [ ] **T007 (SC: 007): Extend persistTweaks** — In `persistTweaks()` (`AppModel.swift:516-521`) add `d.set(sidebarSize.rawValue, forKey: LayoutDefaultsKey.sidebarSize)` and `d.set(Double(listWidth), forKey: LayoutDefaultsKey.listWidth)` so the batch stays a complete snapshot (this is what makes sidebar-size changes survive relaunch).
  **Files:** `MMail/State/AppModel.swift`
  Run: (gate T009) Expected: compiles.

- [ ] **T008 (SC: 002, 003, 005, 006): Mutators** — Near `setSidebar` (`AppModel.swift:1550`) add: `func setSidebarSize(_ v: SidebarSize) { sidebarSize = v; persistTweaks() }`; `func cycleSidebarSize() { sidebarSize = sidebarSize.next; persistTweaks() }`; `func setListWidth(_ v: CGFloat) { listWidth = clampListWidth(v); UserDefaults.standard.set(Double(listWidth), forKey: LayoutDefaultsKey.listWidth) }` (TARGETED single-key write — must NOT call `persistTweaks()`, so the per-drag path never flushes the whole batch; uses the same `LayoutDefaultsKey.listWidth` `loadListWidth` reads).
  **Files:** `MMail/State/AppModel.swift`
  Run: (gate T009) Expected: compiles.

- [ ] **T009 (SC: 007): Compile gate + commit Phase B** — Run (worktree): `xcodebuild -project MMail.xcodeproj -scheme MMail -configuration Debug build-for-testing CODE_SIGNING_ALLOWED=NO` Expected: `** BUILD SUCCEEDED **`. Commit: `feat(resizable-columns): AppModel sidebarSize/listWidth state, load, persist, mutators (phase B)`.
  **Files:** (commit only)
  > Note: the persistence LOAD path (defaults, clamp-on-load, unknown→medium) is unit-tested at the seam level by T002 via an injected `UserDefaults` suite + the canonical `LayoutDefaultsKey` constants — the same keys `AppModel.init`/`persistTweaks`/`setListWidth` use, so write and read can never diverge. The WRITE WIRING (that `persistTweaks`/`setListWidth` actually call `d.set`) and the full set→relaunch→read round-trip are verified by LIVE relaunch at T018 (the project's established norm for persistence), NOT by constructing a full `AppModel` in a unit test (its init has bootstrap side-effects — polling/keychain). SC-007 reflects this split.

> **Review checkpoint after Phase B** (may fold into the Phase-A review if done together — both are the non-UI core).

## Phase C — View wiring

- [ ] **T010 (SC: 002, 004): Sidebar width + compact render** — `SidebarView.swift:52` `.frame(width: 232)` → `.frame(width: model.sidebarSize.width)`. Add a compact path used when `!model.sidebarSize.showsLabels`. IMPORTANT — compact is a genuinely DIFFERENT row layout, not just hiding `Text` inside the existing `HStack(spacing: 10)`; centering requires replacing the row content. Build a `let compact = !model.sidebarSize.showsLabels` flag and branch each piece:
  - **Outer padding**: in compact, reduce the `VStack` `.padding(.horizontal, 8)` (line 50) — keep a small symmetric pad (e.g. 6) so a ~64pt column has room.
  - **folderRow**: compact → render just `Icon(name:…, size:16)` inside `.frame(maxWidth: .infinity)` (centered), drop the `Text(f.name)`, the count, the shortcut, AND the row's `.padding(.horizontal, 10)` (line 101) → use a smaller symmetric pad; keep the active/hover background + `.help(f.name)`.
  - **composeButton**: compact → pencil `Icon` only, centered, drop the `Text("Compose")`, the `Kbd("C")`, and the inner `.padding(.horizontal, 14)` (line 70).
  - **LABELS**: compact → omit the "LABELS" header `Text` entirely; `labelRow` → colored `Circle` dot only, centered (drop `Text(l.name)` + its `.padding(.horizontal, 12)`), keep `.help(l.name)`. (Note: the LABELS block is already absent on the `home` folder — `SidebarView.swift:32` — so no extra guard needed there.)
  - **footer**: compact → replace the `HStack` (line 133) with the `GradientTile` alone, centered (`.frame(maxWidth: .infinity)`); OMIT the name/email `VStack` AND both help/settings `Button`s (they overflow ~64pt; both reachable via the menu bar `⌘,` / `?`).
  `medium`/`large` render EXACTLY as today (the existing rows), only the column width differing.
  **Files:** `MMail/Views/SidebarView.swift`
  Run: (gate T016) Expected: compiles.

- [ ] **T011 (SC: 005, 006): EmailListView width from model** — `EmailListView.swift:30-31`: `.frame(width: model.readingPane ? model.listWidth : nil)` and `.frame(maxWidth: model.readingPane ? model.listWidth : .infinity, maxHeight: .infinity)` (replace both `380`s; reader keeps `maxWidth: .infinity` and absorbs the remainder). Having both `width:` and `maxWidth:` set to `model.listWidth` in reading-pane mode is INTENTIONAL and harmless — the fixed `width:` pins the column (the `maxWidth:` is then redundant), matching today's `380` behavior; in single-pane mode width is `nil` and maxWidth `.infinity` exactly as before, so single-pane is unchanged.
  **Files:** `MMail/Views/EmailListView.swift`
  Run: (gate T016) Expected: compiles.

- [ ] **T012 (SC: 005, 006): Inline drag handle in RootView** — In `RootView.content`'s `readingPane` branch (`RootView.swift:54-56`), insert a private `ListDragHandle()` view BETWEEN `EmailListView()` and `ReaderView()`. Define it as a `private struct` in `RootView.swift` (no new file): a thin (~6pt) `Rectangle().fill(.clear).contentShape(Rectangle())` with `.frame(width: 6, maxHeight: .infinity)`, `@EnvironmentObject var model`, `@State private var dragStart: CGFloat?`, `@State private var pushed = false`.
  - Gesture: `.gesture(DragGesture(minimumDistance: 0).onChanged { v in if dragStart == nil { dragStart = model.listWidth }; guard let ds = dragStart else { return }; model.listWidth = clampListWidth(ds + v.translation.width) }.onEnded { _ in model.setListWidth(model.listWidth); dragStart = nil })`. NOTE: use the `guard let ds = dragStart` binding — do NOT force-unwrap `dragStart!` (a cancelled/re-started gesture could deliver `onChanged` with `dragStart == nil` and crash).
  - Cursor (macOS 14 — `.pointerStyle` is 15.0+, do NOT use it): track the push so it can never leak. `.onHover { inside in if inside && !pushed { NSCursor.resizeLeftRight.push(); pushed = true } else if !inside && pushed { NSCursor.pop(); pushed = false } }` AND `.onDisappear { if pushed { NSCursor.pop(); pushed = false } }` — the `onDisappear` pop is REQUIRED: if the reading pane is toggled off while the cursor is over the handle, SwiftUI removes the view without an `onHover(false)`, so without this the resize cursor sticks for the whole session.
  The handle is only in the `readingPane` branch, so it is absent in `readerFullScreen`/single-pane/home/outbox by construction.
  **Files:** `MMail/Views/RootView.swift`
  Run: (gate T016) Expected: compiles.

- [ ] **T013 (SC: 002): "Sidebar Size" submenu in MMailApp** — In `MMail/MMailApp.swift`'s `.commands`, inside the existing `CommandGroup(after: .sidebar)` (immediately after the `viewInsertion` `ForEach`, in the same closure), add `Menu("Sidebar Size") { Picker("Sidebar Size", selection: Binding(get: { model.sidebarSize }, set: { model.setSidebarSize($0) })) { Text("Small").tag(SidebarSize.small); Text("Medium").tag(SidebarSize.medium); Text("Large").tag(SidebarSize.large) }.pickerStyle(.inline) }`. `SidebarSize` is a `String`-raw enum so it is `Hashable` (auto-synthesized) — `.tag()` works. The inline `Picker` is EXPECTED to render a native checkmark on the current size and live-update from `model.sidebarSize`, but checkmark rendering for an inline `Picker` nested in a `Menu` inside a `CommandGroup` is AppKit-bridge-dependent — **verify live at T018**. FALLBACK if checkmarks don't render: replace the `Picker` with three `Button`s, each `Button { model.setSidebarSize(.x) } label: { Text(model.sidebarSize == .x ? "✓ Small" : "Small") }` (manual checkmark prefix). Do NOT add any `.keyboardShortcut`. Do NOT route through `MenuModel`/`buildCommands()`.
  **Files:** `MMail/MMailApp.swift`
  Run: (gate T016) Expected: compiles.

- [ ] **T014 (SC: 003): ⌘⇧L in handleKeyDown** — In `handleKeyDown`'s `if cmd && shift { switch lower { … } }` block (currently `s`/`r`/`d`), add `case "l": cycleSidebarSize(); return true`. This sits BEFORE the single-key `isTyping`/overlay guard, so `⌘⇧L` fires consistently with `⌘⇧S/R/D` (intentionally even while typing). It is the ONLY new key; the submenu adds none.
  **Files:** `MMail/State/AppModel.swift`
  Run: (gate T016) Expected: compiles.

- [ ] **T015 (SC: 002): Animate sidebar-size changes** — In `RootView.swift` add `.animation(.easeOut(duration: 0.2), value: model.sidebarSize)` adjacent to the existing `.animation(…, value: model.sidebarVisible)` / `…readingPane` at lines 37-38 (same `ZStack` in `body`).
  **Files:** `MMail/Views/RootView.swift`
  Run: (gate T016) Expected: compiles.

- [ ] **T016 (SC: 001-008): Compile gate + commit Phase C** — Run (worktree): `xcodebuild -project MMail.xcodeproj -scheme MMail -configuration Debug build-for-testing CODE_SIGNING_ALLOWED=NO` Expected: `** BUILD SUCCEEDED **`. Commit: `feat(resizable-columns): sidebar size render + drag handle + submenu + ⌘⇧L wiring (phase C)`.
  **Files:** (commit only)

> **Review checkpoint after Phase C** (looped Sonnet review of the UI integration — the riskiest phase: drag gesture, compact render overflow, submenu state, keymap).

## Phase D — Verify (runs at /verify, not part of the build gate)

- [ ] **T017 (SC: 007): Run the full test suite FROM THE MAIN CHECKOUT** — DEFERRED until the main checkout is free of the dark-engine session (cannot run concurrently). From the main checkout on branch `feat/resizable-columns`: `xcodebuild -project MMail.xcodeproj -scheme MMail -configuration Debug test` Expected: all suites PASS including `LayoutSizingTests` (this is where the seam tests' fail→pass is actually exercised; the worktree only compiled them).
  **Files:** (test run only)

- [ ] **T018 (SC: 001-008): Live verification (manual-exploration gate)** — Build into the pinned Dock `MMail.app` DerivedData path, `⌘Q` + relaunch (per `feedback_test-build-delivery`). Verify: SC-001 default layout pixel-identical (fresh-ish defaults → 232 + 380); SC-002 View→Sidebar Size submenu shows a checkmark on the current size and selecting changes it + persists; SC-003 `⌘⇧L` cycles small→medium→large→small incl. while a text field is focused, and bare `l` types a literal `l`; SC-004 small = icon-only with hover tooltips, large visibly wider; SC-005/006 drag the list↔reader handle (resize, reader reflows, clamps at 300/600, persists across relaunch); SC-008 `⌘⇧S`/`⌘⇧R` still work and preserve widths. Write `.verified/resizable-columns` marker only after these pass.
  **Files:** `.verified/resizable-columns` (at /verify)

---

**Handoff:** On plan approval, dispatch the build to a single Opus subagent, executing Phases A→C with the `build-for-testing` gate per phase and a looped Sonnet review after Phase A(+B) and after Phase C. Phase D (T017/T018) is the /verify stage and depends on the main checkout being free.
