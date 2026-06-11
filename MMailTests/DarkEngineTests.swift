import Testing
import Foundation
@testable import MMail

/// Unit tests for the PURE dark-engine seams on `ReaderHTML` (no WebView, no AppModel):
///   - `shouldApplyDark(dark:showOriginal:)` — the `model.dark && !showOriginal`
///     predicate (SC-011a)
///   - `darkEnableScript()` — the fixed-dark-palette `DarkReader.enable(...)` injection
///     JS builder (SC-011b)
/// Both are exercised with injected values, proving purity. The live WebView render, the
/// DarkReader transform, height/no-clip, and remote-blocking are the manual-exploration
/// gate (none headlessly assertable) — see `DarkEngineFeasibilityTests` for the headless
/// engine-feasibility evidence.
@Suite struct DarkEngineTests {

    // MARK: - dark-apply predicate (SC-011a)

    @Test func shouldApplyDarkIsTrueOnlyWhenDarkAndNotShowOriginal() {
        // The ONE true case: app is dark AND the message is not in "Show original".
        #expect(ReaderHTML.shouldApplyDark(dark: true, showOriginal: false) == true)
    }

    @Test func shouldApplyDarkIsFalseForEveryOtherInputCombination() {
        // Light mode never darkens, regardless of "Show original".
        #expect(ReaderHTML.shouldApplyDark(dark: false, showOriginal: false) == false)
        #expect(ReaderHTML.shouldApplyDark(dark: false, showOriginal: true) == false)
        // Dark mode under "Show original" reverts to the white surface (no transform).
        #expect(ReaderHTML.shouldApplyDark(dark: true, showOriginal: true) == false)
    }

    // MARK: - injection-script builder (SC-011b)

    @Test func darkEnableScriptCallsDarkReaderEnable() {
        // The builder MUST emit a `DarkReader.enable(...)` call — this is the seam the
        // Phase C wiring evaluates over the already-loaded page.
        let js = ReaderHTML.darkEnableScript()
        #expect(js.contains("DarkReader.enable"))
    }

    @Test func darkEnableScriptEmitsTheFixedDarkPalette() {
        // The fixed palette: a dark background near #1a1a1a (the single source of truth,
        // `ReaderHTML.bodyTextColorHex`) with light text. Pin the exact substrings the
        // builder must emit so the seam matches what the Phase A spike feasibility-proved.
        let js = ReaderHTML.darkEnableScript()
        // The dark background is the `#1A1A1A` source of truth (case-insensitive — the
        // JS uses the lowercased CSS form).
        #expect(js.lowercased().contains("#1a1a1a"))
        #expect(js.contains("darkSchemeBackgroundColor"))
        // Light text for the dark surface — pin the exact emitted value so a palette
        // change can't silently pass (the builder emits `'#e8e8e8'`).
        #expect(js.contains("darkSchemeTextColor"))
        #expect(js.contains("#e8e8e8"))
    }

    @Test func darkEnableScriptGuardsOnTheDarkReaderGlobal() {
        // The injected JS must be a harmless no-op if the engine define never landed
        // (mirrors the spike's `if (window.DarkReader)` guard).
        let js = ReaderHTML.darkEnableScript()
        #expect(js.contains("window.DarkReader"))
    }
}
