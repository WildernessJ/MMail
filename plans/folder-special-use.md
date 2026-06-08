# folder-special-use Implementation Plan

**Goal:** Reliably detect special-use folders (especially Spam via `\Junk`) by requesting `RETURN (SPECIAL-USE)` in the IMAP `LIST`, capability-gated, so triage targets the real Spam folder even when its name is non-standard.

**Architecture:** `classify(name:attributes:)` already prefers special-use attributes over name heuristics (`IMAPService.swift:519`) and `listMailboxes()` already feeds it each folder's `info.attributes` (`:273-275`). The only production change is in `listMailboxes()`: pass `[.specialUse]` as the `LIST` return option when `capabilities` contains BOTH `SPECIAL-USE` and `LIST-EXTENDED` (else `[]`, unchanged). Automated coverage pins the existing `classify()` precedence with unit tests across all five flags; the LIST-gating is verified by build + manual-exploration.

**Test Methodology:** e2e-first (from `.harness.yaml`). NOTE: `classify()` already implements the precedence, so its unit tests PASS immediately — they are **regression-pins** for the contract the feature depends on, not a TDD red→green (the new `LIST`-gating code has no unit-testable surface — no live server in CI). This is expected; don't treat the tests passing before the `listMailboxes` change as a problem.

**Build execution note:** The FULL build is by a single Opus subagent following these tasks, then an opposite-model review loop. The production change stays in the existing `MMail/Mail/IMAPService.swift` (no new app-target file → no app regen). The ONE new file is the test file in T001 → run `xcodegen generate` once and commit the regenerated `MMail.xcodeproj/project.pbxproj`.

**NIO API notes (VERIFIED during review against the pinned swift-nio-imap — these are facts, not TODOs):**
- `Command.list(ListSelectOptions?, reference: MailboxName, MailboxPatterns, [ReturnOption])` — pass `[.specialUse]` (or `[]`) as the LAST arg (the `[ReturnOption]`). The FIRST arg (`ListSelectOptions?`) stays `nil`.
- ⚠️ **Use `ReturnOption.specialUse`, NOT `ListSelectOption.specialUse`** (a different, structurally separate type). `ReturnOption.specialUse` encodes as the `RETURN (SPECIAL-USE)` **return option** (verified in the library encoder `ListReturnOps.swift` — it writes `RETURN (SPECIAL-USE)`). `ListSelectOption.specialUse` / `ListSelectOptions` is a **selection filter** that would restrict the LIST to ONLY special-use folders and break inbox/regular-folder discovery. The library's doc comment on `ReturnOption.specialUse` misleadingly says "filters" — ignore it; the encoder is correct. Do NOT touch the first `ListSelectOptions?` argument.
- Capability atoms are stored uppercased (`extractCapabilities` does `.name.uppercased()`), so gate on `capabilities.contains("SPECIAL-USE") && capabilities.contains("LIST-EXTENDED")`.
- `MailboxInfo.Attribute` has a public `init(_ str: String)` (constructible as `MailboxInfo.Attribute("\\Junk")`). It is defined in `NIOIMAPCore`, which is an INTERNAL package target — NOT an exported product. The only exported product is `NIOIMAP` (see test-import guidance in T001).

---

## Tasks

- [ ] **T001 (SC: 002): Regression-pin the classify precedence with unit tests** — Add `MMailTests/ClassifyTests.swift` (swift-testing: `import Testing`, `@testable import MMail`). Cases to cover: each of `\Junk→.junk`, `\Sent→.sent`, `\Drafts→.drafts`, `\Trash→.trash`, `\Archive→.archive` wins even with a misleading name (e.g. Trash flag on "Papierkorb"→`.trash`, Junk flag on "Werbung"→`.junk`); plus name-fallback when no flag (`"Spam"`,`[]`→`.junk`); plus generic (`"Projects"`,`[]`→`.other`).

  **Getting the type into the test — pick whichever COMPILES cleanly, in this order:**
  1. Try `import NIOIMAP` in the test and construct `MailboxInfo.Attribute("\\Junk")` directly against `IMAPService.classify(name:attributes:)`. (If `NIOIMAP` re-exports the `NIOIMAPCore` symbols, this just works.)
  2. If the type isn't visible, add `package: swift-nio-imap` / `product: NIOIMAP` as a dependency of the `MMailTests` target in `project.yml`, `xcodegen generate`, retry. **Do NOT add `product: NIOIMAPCore`** — it is not an exported product and XcodeGen/SPM will reject it.
  3. If the NIO type still won't import cleanly into the test target, DON'T fight it — refactor for testability: extract the precedence into a NIO-free pure helper `static func classifyKind(name: String, specialUse: Set<String>) -> MailboxKind` (special-use atoms as uppercased strings like `"\\JUNK"`), have `classify(name:attributes:)` build that `Set<String>` from `attributes` and delegate, and unit-test the pure helper (no NIO import needed — mirrors the existing `moveStrategy(capabilities:)` seam). This is the preferred end state if option 1/2 are awkward.

  Then `xcodegen generate` (new test file) and stage `MMail.xcodeproj/project.pbxproj`. Run: `xcodebuild -project MMail.xcodeproj -scheme MMail -configuration Debug test CODE_SIGNING_ALLOWED=NO` Expected: PASS, non-zero executed count (these pin already-correct behavior — see methodology note). Commit: `test: pin classify() special-use precedence`.
  - **Files:** `MMailTests/ClassifyTests.swift`, `MMail.xcodeproj/project.pbxproj` (regenerated); possibly `project.yml` (option 2) or `MMail/Mail/IMAPService.swift` (option 3 refactor)

- [ ] **T002 (SC: 001,003): Request RETURN (SPECIAL-USE) when supported** — In `listMailboxes()` (`IMAPService.swift:264`), replace the hardcoded `[]` return options with: `let opts: [ReturnOption] = (capabilities.contains("SPECIAL-USE") && capabilities.contains("LIST-EXTENDED")) ? [.specialUse] : []` and pass `opts` as the last arg to `.list(...)`. Leave everything else (pattern `*`, attribute parsing, `classify` call) unchanged. Confirm the NIO symbol + encoding per the API notes. Run: `xcodebuild -project MMail.xcodeproj -scheme MMail -configuration Debug build CODE_SIGNING_ALLOWED=NO` Expected: PASS. Commit: `feat: request RETURN (SPECIAL-USE) in folder LIST, capability-gated`.
  - **Files:** `MMail/Mail/IMAPService.swift`

- [ ] **T003 (SC: 004): Full verification + manual-exploration** — Run build + test; confirm green with a NON-ZERO executed-test count (not just exit 0). Run: `xcodebuild -project MMail.xcodeproj -scheme MMail -configuration Debug build CODE_SIGNING_ALLOWED=NO && xcodebuild -project MMail.xcodeproj -scheme MMail -configuration Debug test CODE_SIGNING_ALLOWED=NO 2>&1 | tail -40` Expected: BUILD SUCCEEDED, TEST SUCCEEDED, non-zero count. Manual-exploration for the next human run (no IMAP server in CI): after launching the combined build, confirm Mark-as-spam still lands the message in mailbox.org's Spam folder (no regression) and the other special folders (Sent/Drafts/Trash/Archive) still resolve normally. Document in the handoff.
  - **Files:** none (verification only)

---

## Notes for the build subagent
- YAGNI: ONLY the gated return option + the classify regression tests. Do NOT change `classify()` logic, the folder-id map, or the move logic. Do NOT use the `(SPECIAL-USE)` selection option.
- Regression safety is the whole point of the dual-capability gate: if `RETURN (SPECIAL-USE)` were sent to a server that rejects it, `send()` would throw and break ALL folder discovery. Only send it when BOTH atoms are present.
- Do NOT switch `testing.method`; do NOT add `xcodegen generate &&` to the verify command. Run `xcodegen generate` manually in T001 (new test file; and again if you add a test-target dep), then commit the regenerated `project.pbxproj`.
- Confirm a non-zero executed-test count (swift-testing reports "Test run with N tests … passed").
- Do NOT push; do NOT touch `main`. The parent pushes the branch after an independent review + verify.
