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

    // MARK: - No cache-schema change (SC-010, T014)

    /// The dark transform is render-time only: it added ZERO stored properties to any
    /// cache-serialized `Codable` type (`Email`, `AttachmentMeta`). The dark seams live
    /// on the stateless `enum ReaderHTML` namespace (pure funcs + `Color` statics), which
    /// is not serialized. This proves the contract DIRECTLY for the dark feature: a
    /// pre-feature `[Email]` cache decodes cleanly via the bare `JSONDecoder().decode(
    /// [Email].self, …)` that `MailCache` uses — a new REQUIRED key would have failed the
    /// whole-array decode and discarded the cached folder. (The shipped
    /// `CIDInliningTests.preFeatureCacheDecodesCleanly` covers the same schema invariant
    /// for the prior feature; this is the dark-engine-local restatement, not a duplicate
    /// of its broader fixture — there is no dark-feature key to assert nil on, which is the
    /// point: this feature serialized nothing.)
    @Test func preFeatureCacheDecodesCleanlyAfterDarkEngine() throws {
        let json = """
        [{
          "id": "pre-dark-1",
          "account": "acct@host",
          "from": "alice@host",
          "subject": "Cached before dark-engine",
          "preview": "hi",
          "body": "plain body text",
          "time": "9:00 AM",
          "day": "earlier",
          "unread": false,
          "starred": false,
          "hasAttachment": false,
          "labels": [],
          "folder": "INBOX",
          "bodyLoaded": true,
          "attachments": []
        }]
        """
        let emails = try JSONDecoder().decode([Email].self, from: Data(json.utf8))
        #expect(emails.count == 1)
        let e = try #require(emails.first)
        #expect(e.id == "pre-dark-1")
        #expect(e.body == "plain body text")
        // The dark feature added no stored property, so the prior feature-era optionals
        // remain the only additive keys — still absent here → nil, NOT a decode error.
        #expect(e.bodyHTML == nil)
        #expect(e.bodyComplete == nil)
        #expect(e.sortDate == nil)
    }
}
