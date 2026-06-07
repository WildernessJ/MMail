# swift-property-tests Implementation Plan

**Goal:** Stand up a dependency-free property-based-testing baseline (a seedable `forAll` harness on `swift-testing`) plus property suites over MMail's highest-value pure functions, and fix the one real crash the suite surfaces.

**Architecture:** A new `MMailTests` unit-test target (swift-testing, `@testable import MMail`, zero third-party deps) holds: a small `PropertyTesting/` harness (SplitMix64 seedable RNG → `Gen<T>` generators → `forAll` runner that returns a result so failures are assertable, reports a replay seed, and shrinks), and `Properties/` suites for `Privacy.cleanLink`, `AppModel.dedupById`, `MIME.decodeHeader`/`parse`/`extractText`, and `AppModel.parseRecipients`. One minimal production fix lands in `AppModel.parseRecipients` (backwards-range guard) — the only defect in scope.

**Test Methodology:** e2e-first (from `.harness.yaml`). Adapted for a test-infrastructure feature: the "behavioral scaffold" is the test target + harness self-tests taken red→green; "implementation" is the harness, generators, and the production fix; the property suites are the feature's deliverable. Every task carries a Swift `Run:`/`Expected:` cue.

**Canonical commands:**
- `TEST` = `xcodebuild test -project MMail.xcodeproj -scheme MMail -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO`
- `BUILD` = `xcodebuild -project MMail.xcodeproj -scheme MMail -configuration Debug build CODE_SIGNING_ALLOWED=NO`
- `REGEN` = `xcodegen generate` (NOTE: rewrites the git-tracked `MMail.xcodeproj/project.pbxproj` — stage and commit it deliberately as part of the task that runs it)

---

- [ ] **T001 (SC: 001, 003): Add `MMailTests` target + prove it runs** — In `project.yml`: (a) add target `MMailTests` (`type: bundle.unit-test`, `platform: macOS`, `sources: [MMailTests]`, `dependencies: [- target: MMail]`) — the test bundle links the app target so `@testable import MMail` resolves. (b) Add an explicit scheme so headless `xcodebuild test` actually runs the bundle (don't rely on auto-scheme):

    ```yaml
    schemes:
      MMail:
        build:
          targets: { MMail: all, MMailTests: [test] }
        test:
          targets: [MMailTests]
    ```

  (c) Add a smoke test: `import Testing` + `@Suite struct Smoke { @Test func ok() { #expect(Bool(true)) } }`.
  On `SWIFT_VERSION`: the app target is language mode `"5.0"`; `swift-testing`'s `@Test`/`#expect` macros are a *toolchain* feature and work in language mode 5 under Xcode 26, so NO bump is expected. This is untrodden, so the verification below confirms a non-zero test count actually executes; ONLY if macro expansion genuinely fails, set `SWIFT_VERSION: "6.0"` on the `MMailTests` target (per-target; independent of the app). `@MainActor` is NOT expected to bite — `AppModel` is not `@MainActor` (`AppModel.swift:87`) and all four target functions are non-isolated `static`s; add isolation tweaks only if a concrete error appears.
  - **Files:** `project.yml`, `MMailTests/SmokeTests.swift`
  - Run: `REGEN` then `TEST` — Expected: builds clean; exactly one test (`Smoke.ok`) runs and passes — **confirm the executed-test count is non-zero** (a green run with zero tests means the scheme wiring is wrong). Then `BUILD` — Expected: BUILD SUCCEEDED (app unaffected). Commit (including the regenerated `project.pbxproj`).

- [ ] **T002 (SC: 004): Seedable RNG (SplitMix64)** — Implement a `SplitMix64: RandomNumberGenerator` seeded from a `UInt64` (public-domain algorithm, no dependency). This is the seedability the spec/reviewer flagged as the open risk — Swift's `SystemRandomNumberGenerator` is not seedable.
  - **Files:** `MMailTests/PropertyTesting/SeededRNG.swift`, `MMailTests/PropertyTesting/SeededRNGTests.swift`
  - Run: `TEST` — Expected: PASS (same seed → identical `next()` sequence; two different seeds → different sequences). Commit.

- [ ] **T003 (SC: 001): Generators (`Gen<T>`)** — Implement `struct Gen<T>` wrapping `(inout SplitMix64) -> T` with map/combine + a per-generator `shrink: (T) -> [T]`. Provide generators: `Int`, arbitrary `String` (unicode + bytes-as-text), a dedicated **no-encoded-word `String`** that excludes any string containing the two-char sequence `=?` *anywhere* (for the `decodeHeader` passthrough property — the fast path at `MIME.swift:10` keys on `contains("=?")`), `Data`, `http(s)` `URL` (query mixing tracking keys from `Privacy.trackingParams` and non-tracking keys), `Email` (with a small id pool so duplicates occur), and recipient-field strings (constrained: clean `Name <addr>` with no `@`/`<`/`>` in names; unconstrained: display names with arbitrary `<`/`>` in any order).
  - **Files:** `MMailTests/PropertyTesting/Generators.swift`
  - Run: `TEST` — Expected: PASS (a self-test drawing 50 values from each generator returns without trapping). Commit.

- [ ] **T004 (SC: 001, 004): `forAll` runner** — Implement `forAll` returning a `PropertyResult` (`.passed` or `.failed(counterexample:String, seed:UInt64)`), defaulting to 200 iterations, seeded by `SplitMix64` (seed defaultable/overridable), shrinking the first failing input via the generator's `shrink` toward a minimal case, and a thin `check(...)` wrapper that turns `.failed` into a `swift-testing` `#expect` failure carrying the counterexample + seed. Returning a result (not only `#expect`) is what makes the harness self-testable.
  - **Files:** `MMailTests/PropertyTesting/ForAll.swift`
  - Run: `TEST` — Expected: PASS (compiles; trivial always-true property via `check` passes). Commit.

- [ ] **T005 (SC: 001, 004): Harness self-tests** — Cover the spec's "forAll PBT harness" scenarios against the result-returning API: (a) always-true property → `.passed`; (b) sometimes-false property → `.failed` with a non-empty counterexample and a seed; (c) re-running pinned to that seed reproduces the same first counterexample; (d) shrinking: property `n < 5` over non-negative `Int` yields minimal counterexample `5`.
  - **Files:** `MMailTests/PropertyTesting/ForAllTests.swift`
  - Run: `TEST` — Expected: PASS. Commit.

- [ ] **T006 (SC: 001, 002): `Privacy.cleanLink` properties** — idempotence; all tracking keys removed; every non-tracking query item retained and scheme/host/path unchanged; edge case "components cannot re-serialize" returns without trapping (and if a tracking key survives, the test fails loudly — do not weaken the generator). Generator: `http(s)` URLs only.
  - **Files:** `MMailTests/Properties/CleanLinkProperties.swift`
  - Run: `TEST` — Expected: PASS (`cleanLink` is already correct; this locks the behavior in). Commit.

- [ ] **T007 (SC: 001, 002): `AppModel.dedupById` properties** — no duplicate ids; first-occurrence order preserved; result is a subsequence of input; result count equals number of distinct input ids; idempotence; many-duplicate input returns without trapping.
  - **Files:** `MMailTests/Properties/DedupByIdProperties.swift`
  - Run: `TEST` — Expected: PASS. Commit.

- [ ] **T008 (SC: 001, 005): MIME robustness properties** — `decodeHeader`: input with no `=?` substring anywhere returns unchanged (exact equality, whitespace included); arbitrary input returns without trapping. `parse`/`extractText`: arbitrary `Data` (random/truncated/empty) returns without trapping.
  - **Files:** `MMailTests/Properties/MIMEProperties.swift`
  - Run: `TEST` — Expected: PASS. Commit.

- [ ] **T009 (SC: 005): `parseRecipients` crash-freedom property — RED** — Add the crash-freedom property using the UNCONSTRAINED recipient-field generator (display names with arbitrary `<`/`>` in any order). Do NOT fix the production code yet and do NOT commit this red state.
  - **Files:** `MMailTests/Properties/ParseRecipientsProperties.swift`
  - Run: `TEST` — Expected: FAIL/CRASH — the backwards-range trap at `AppModel.swift:2667-2668` fires. NOTE: this aborts the test *process* (fatal precondition); it shows up as a crashed test run, NOT a swift-testing assertion failure with a shrunk counterexample — the process death IS the expected signal here. Do not commit this red state.

- [ ] **T010 (SC: 005): `parseRecipients` fix — GREEN** — Fix `AppModel.parseRecipients` by searching for the closing `>` only AFTER the opening `<`: change the `gt` lookup to `s.range(of: ">", range: lt.upperBound..<s.endIndex)`. A `>` that precedes the first `<` can then no longer form a backwards range. Prefer this over a bare `guard lt.upperBound <= gt.lowerBound else { return s }`: both stop the crash, but the guard returns the whole piece and leaks the display name, whereas search-after-`<` also extracts the address correctly. If no `>` follows the `<`, the `if let` fails and the existing bare-string branch returns `s`. This is the one in-scope production change; `current_feature` is set so the `*.swift` gate allows it.
  - **Files:** `MMail/State/AppModel.swift`
  - Run: `TEST` — Expected: the T009 crash-freedom property now PASSES. Then `BUILD` — Expected: BUILD SUCCEEDED (app still compiles). Commit test + fix together.

- [ ] **T011 (SC: 002): `parseRecipients` extraction property** — Constrained generator (display names contain neither `@` nor `<`/`>`; addresses contain `@`), separators `,` and `;`: each embedded address appears in the result; every returned entry contains `@`; no returned entry contains its source display-name text.
  - **Files:** `MMailTests/Properties/ParseRecipientsProperties.swift`
  - Run: `TEST` — Expected: PASS. Commit.

- [ ] **T012 (SC: 002, 004): Prove the net actually catches regressions** — Temporarily break one value function (e.g. make `dedupById` return its input unchanged), run, confirm the matching property FAILS with a concrete counterexample + seed, then confirm re-running pinned to that printed seed reproduces it; revert the break. This is a manual verification of SC-002/SC-004; nothing from this task is committed.
  - **Files:** (temporary edit to `MMail/State/AppModel.swift`, reverted)
  - Run: `TEST` (broken) — Expected: FAIL with counterexample + seed; replay with that seed reproduces; `TEST` (after revert) — Expected: PASS.

- [ ] **T013 (SC: 001, 003): Full green + no-new-dependency check + final commit** — Confirm the whole suite is green and the audit posture is intact.
  - **Files:** `project.yml` (read-only check)
  - Run: `TEST` — Expected: all properties pass. Then `git diff project.yml` review — Expected: `packages:` list unchanged (only the `MMailTests` target was added; no third-party dependency). Commit.
