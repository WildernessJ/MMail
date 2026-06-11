import SwiftUI
import WebKit

/// Privacy helpers: count blocked remote resources (trackers) and strip
/// click-tracking parameters from links.
enum Privacy {
    private static let trackerPatterns = [
        "<img[^>]+src\\s*=\\s*[\"']?https?://",
        "<script[^>]+src\\s*=\\s*[\"']?https?://",
        "<iframe[^>]+src\\s*=\\s*[\"']?https?://",
        "<link[^>]+href\\s*=\\s*[\"']?https?://",
        "url\\(\\s*[\"']?https?://"
    ]

    static func trackerCount(in html: String) -> Int {
        let range = NSRange(html.startIndex..., in: html)
        var n = 0
        for p in trackerPatterns {
            if let re = try? NSRegularExpression(pattern: p, options: [.caseInsensitive]) {
                n += re.numberOfMatches(in: html, options: [], range: range)
            }
        }
        return n
    }

    static let trackingParams: Set<String> = [
        "utm_source", "utm_medium", "utm_campaign", "utm_term", "utm_content", "utm_id",
        "fbclid", "gclid", "gclsrc", "dclid", "mc_eid", "mc_cid", "_hsenc", "_hsmi",
        "mkt_tok", "yclid", "igshid", "vero_id", "oly_enc_id", "oly_anon_id", "wickedid",
        "cmpid", "ncid", "spm", "trk"
    ]

    /// Remove common click-tracking query parameters from a URL.
    static func cleanLink(_ url: URL) -> URL {
        guard var comps = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let items = comps.queryItems, !items.isEmpty else { return url }
        let kept = items.filter { !trackingParams.contains($0.name.lowercased()) }
        guard kept.count != items.count else { return url }
        comps.queryItems = kept.isEmpty ? nil : kept
        return comps.url ?? url
    }
}

/// Renders an email's HTML body in a WKWebView. Remote content (images, fonts,
/// scripts, external CSS) is blocked by default for privacy; pass blockRemote
/// false to load it. Reports its content height so it can size itself.
struct HTMLMessageView: NSViewRepresentable {
    let html: String
    var blockRemote: Bool
    /// When non-nil AND images are shown (blockRemote == false), remote `<img src>`
    /// is rewritten to signed proxy URLs and the message renders behind a
    /// block-all-except-proxy-origin content rule. Nil ⇒ today's behavior
    /// (direct load when shown, block-all when blocked).
    var proxyConfig: ImageProxyConfig? = nil
    /// When true, after a body loads the vendored DarkReader engine is injected and
    /// `DarkReader.enable(ReaderHTML.darkEnableScript())` is called to darken the page
    /// in-page; when it later changes, `updateNSView` toggles the engine IN-PLACE
    /// (`enable`/`disable` via `evaluateJavaScript`, no reload flash) and re-measures the
    /// transformed-DOM height (T008/T009). The call site passes
    /// `ReaderHTML.shouldApplyDark(dark:showOriginal:)`. In light mode / "Show original"
    /// this is `false` → today's path byte-for-byte (no engine injected, immediate
    /// height measure).
    var applyDark: Bool = false
    @Binding var height: CGFloat

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let web = WKWebView(frame: .zero, configuration: config)
        web.navigationDelegate = context.coordinator
        web.setValue(false, forKey: "drawsBackground")
        context.coordinator.load(web, html: html, blockRemote: blockRemote, proxyConfig: proxyConfig, applyDark: applyDark)
        return web
    }

    func updateNSView(_ web: WKWebView, context: Context) {
        let c = context.coordinator
        if c.lastHTML != html || c.lastBlock != blockRemote || c.lastProxyConfig != proxyConfig {
            // An html/blockRemote/proxyConfig change re-runs `load` as today; the fresh
            // load then applies dark in `didFinish` (`applyDarkAndMeasure`, T008), and
            // `load` records `lastApplyDark`, so the in-place branch below is skipped on
            // the same pass.
            c.load(web, html: html, blockRemote: blockRemote, proxyConfig: proxyConfig, applyDark: applyDark)
        } else if c.lastApplyDark != applyDark {
            // ONLY the dark-apply decision changed (app dark↔light or "Show original").
            // Toggle the engine IN-PLACE on the already-loaded page — no reload flash —
            // then re-measure the transformed-DOM height (T009).
            c.toggleDark(web, applyDark: applyDark)
        }
    }

    /// Thin private wrapper over the tested `ReaderHTML.wrappedDocument` builder
    /// (T009) so the production wrapper IS the unit-tested code (no parallel copy).
    /// Forces `color-scheme: only light` + an opaque white body background — the
    /// `drawsBackground=false` WKWebView (makeNSView) then reads white over the dark
    /// window from this CSS background rather than from a transparent webview.
    private static func wrapped(_ html: String) -> String {
        ReaderHTML.wrappedDocument(html)
    }

    /// Load the vendored DarkReader UMD engine (MMail/Resources/darkreader.js,
    /// MIT — see darkreader.LICENSE) from the app bundle, once. Returns the JS
    /// source as a String that, when evaluated in a page, defines the global
    /// `window.DarkReader` (confirmed UMD global name; API: `DarkReader.enable` /
    /// `DarkReader.disable`). A nil URL means the resource did not ship in the
    /// built bundle (XcodeGen auto-classification failed) — that MUST be loud, so
    /// we log it; an unbundled engine is the first failure to surface in the spike.
    private static let darkReaderScript: String? = {
        guard let url = Bundle.main.url(forResource: "darkreader", withExtension: "js") else {
            print("⚠️ MMail: darkreader.js NOT FOUND in Bundle.main — the dark engine resource did not ship in the build.")
            return nil
        }
        return try? String(contentsOf: url, encoding: .utf8)
    }()

    final class Coordinator: NSObject, WKNavigationDelegate {
        let parent: HTMLMessageView
        var lastHTML = ""
        var lastBlock = true
        var lastProxyConfig: ImageProxyConfig?
        /// Mirrors `lastBlock`: the `applyDark` value last applied to the loaded page, so
        /// `updateNSView` can detect an `applyDark`-only change and toggle the engine
        /// IN-PLACE (no reload flash) instead of re-running `load` (T009).
        var lastApplyDark = false
        /// Monotonic token bumped on every `load`. A content-rule compile is async;
        /// when it completes we install/load ONLY if the token still matches, so a
        /// reconfigure (toggle/URL change) that started a newer load can never have
        /// a stale completion install a stale rule or load stale HTML.
        private var generation = 0
        init(_ parent: HTMLMessageView) { self.parent = parent }

        // Block every remote resource type, then `ignore-previous-rules` (allow) for
        // `data:` URIs (T011). The `.*` url-filter matches a `data:` string too, so
        // without this carve-out an inline CID image (rewritten to a self-contained
        // `data:` URI at render time) would be blocked alongside genuine remotes.
        // A `data:` URI is embedded — zero network request leaves the machine — so
        // allowing it is privacy-safe; every remote http(s) resource stays blocked.
        // `internal` (not `private`) so `@testable import MMail` can compile this exact
        // JSON through WKContentRuleListStore in a headless test (the `data:` carve-out's
        // JSON validity is otherwise only observable at runtime in the live UI).
        static let blockRules = """
        [{"trigger":{"url-filter":".*","resource-type":["image","media","style-sheet","font","raw","script","fetch","websocket","other"]},"action":{"type":"block"}},\
        {"trigger":{"url-filter":"^data:"},"action":{"type":"ignore-previous-rules"}}]
        """

        /// Regex-escape a string so it can be embedded literally in a
        /// `url-filter` (which is a regex). Escapes the regex metacharacters that
        /// can appear in a host (`.`, plus a defensive set) so e.g. the `.` in
        /// `proxy.example.com` matches a literal dot, not any character.
        static func regexEscaped(_ s: String) -> String {
            var out = ""
            let meta: Set<Character> = [".", "\\", "+", "*", "?", "(", ")", "[", "]",
                                        "{", "}", "^", "$", "|", "/"]
            for ch in s {
                if meta.contains(ch) { out.append("\\") }
                out.append(ch)
            }
            return out
        }

        /// Build a content-rule JSON that blocks every remote resource type, then
        /// `ignore-previous-rules` (allows) ONLY requests whose RESOURCE URL is on
        /// the proxy origin. The allow rule matches via `url-filter` against the
        /// request URL — NOT `if-domain`, which matches the document/page domain
        /// (here `about:blank`, since the HTML loads with `baseURL: nil`) and so
        /// would never fire. Any remote resource that is not a rewritten
        /// `<img src>` proxy URL — scripts, iframes, fonts, external CSS, CSS
        /// `url()`, non-proxy `srcset` — therefore stays blocked. Returns nil if
        /// the proxy base URL has no host.
        static func proxyAllowRules(for config: ImageProxyConfig) -> String? {
            guard let host = config.baseURL.host, !host.isEmpty else { return nil }
            // Match the resource URL on the proxy host: `^https://<host>/`.
            // Escape the host so its dots are literal. JSON-escape the backslashes
            // the regex needs (`\.` -> `\\.` in the JSON string literal).
            let hostPattern = regexEscaped(host).replacingOccurrences(of: "\\", with: "\\\\")
            let urlFilter = "^https://\(hostPattern)/"
            // Same `data:` carve-out as `blockRules` (T011): un-block self-contained
            // `data:` URIs (inline CID images) so they render in the proxy path too,
            // while every non-proxy remote http(s) resource stays blocked. Privacy-safe
            // — a `data:` URI makes no network request.
            return """
            [{"trigger":{"url-filter":".*","resource-type":["image","media","style-sheet","font","raw","script","fetch","websocket","other"]},"action":{"type":"block"}},\
            {"trigger":{"url-filter":"\(urlFilter)"},"action":{"type":"ignore-previous-rules"}},\
            {"trigger":{"url-filter":"^data:"},"action":{"type":"ignore-previous-rules"}}]
            """
        }

        func load(_ web: WKWebView, html: String, blockRemote: Bool, proxyConfig: ImageProxyConfig?, applyDark: Bool) {
            lastHTML = html
            lastBlock = blockRemote
            lastProxyConfig = proxyConfig
            // Record the applyDark state this fresh load will apply in `didFinish`
            // (via `applyDarkAndMeasure`), so a later `applyDark`-only change in
            // `updateNSView` is detected against the value actually on the page.
            // Threaded EXPLICITLY from the live struct (like html/blockRemote/proxyConfig)
            // — NOT read from `parent.applyDark`, which is a first-render snapshot frozen
            // in `makeCoordinator()` and goes stale after an in-session light→dark toggle.
            lastApplyDark = applyDark

            // Bump the generation so any in-flight compile from a prior load is
            // discarded when it completes (it will not match `myGen`).
            generation += 1
            let myGen = generation

            web.configuration.userContentController.removeAllContentRuleLists()

            // Proxy mode: images shown AND a proxy is configured. Rewrite the HTML
            // FRESH here (never persisted) and render behind the proxy-origin
            // allow-rule, installed BEFORE load.
            if !blockRemote,
               let config = proxyConfig,
               let rules = Self.proxyAllowRules(for: config) {
                let rewritten = ImageProxy.rewrite(html: html, config: config, now: Date())
                let body = HTMLMessageView.wrapped(rewritten)
                WKContentRuleListStore.default().compileContentRuleList(
                    forIdentifier: "mmail-proxy-allow",
                    encodedContentRuleList: rules) { [weak self] list, _ in
                        // Stale compile (a newer load started): install nothing, load nothing.
                        guard let self, self.generation == myGen else { return }
                        if let list { web.configuration.userContentController.add(list) }
                        web.loadHTMLString(body, baseURL: nil)
                    }
                return
            }

            // Non-proxy paths (today's behavior): direct load when shown, block-all
            // when blocked.
            let body = HTMLMessageView.wrapped(html)
            guard blockRemote else { web.loadHTMLString(body, baseURL: nil); return }
            WKContentRuleListStore.default().compileContentRuleList(
                forIdentifier: "mmail-block-remote",
                encodedContentRuleList: Self.blockRules) { [weak self] list, _ in
                    guard let self, self.generation == myGen else { return }
                    if let list { web.configuration.userContentController.add(list) }
                    web.loadHTMLString(body, baseURL: nil)
                }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            applyDarkAndMeasure(webView)
        }

        /// Single sequencing seam for the load-completion path (T008). When
        /// `applyDark`: inject the vendored DarkReader engine to define
        /// `window.DarkReader`, THEN — only after that define resolves — evaluate
        /// `ReaderHTML.darkEnableScript()` (the tested fixed-palette `enable(...)`),
        /// and read `document.body.scrollHeight` on the NEXT runloop turn inside the
        /// enable() completion. The deferred read matters: DarkReader's `enable()`
        /// injects CSS + attaches a MutationObserver and its effect is NOT fully
        /// applied synchronously when the `evaluateJavaScript` completion fires —
        /// reading height in the bare completion samples a pre/mid-transform height
        /// (violates SC-007). The deferred read therefore SUPERSEDES the immediate
        /// measure so a darkening layout shift never leaves a stale height.
        /// When NOT `applyDark`: measure `scrollHeight` immediately (today's path).
        ///
        /// Settle escalation ladder (build-time tunable, only if a LIVE T015 verify
        /// shows height still samples early): `DispatchQueue.main.async` →
        /// `asyncAfter(deadline: .now() + ~0.016–0.032)` (one frame) → a
        /// double-`requestAnimationFrame` in the injected JS posting the settled height
        /// back via a `WKScriptMessageHandler`. `DispatchQueue.main.async` is the
        /// starting rung.
        private func applyDarkAndMeasure(_ web: WKWebView) {
            // Read the dark state from `lastApplyDark` — the value `load()` just recorded
            // for the page now being measured — NOT `parent.applyDark`, which is the
            // first-render struct snapshot and goes stale after an in-session toggle.
            // `lastApplyDark` is the source of truth for "what dark state is on the page."
            guard lastApplyDark, let engine = HTMLMessageView.darkReaderScript else {
                // Light mode / "Show original": today's immediate measure, unchanged.
                measureHeight(web)
                return
            }
            web.evaluateJavaScript(engine) { [weak self, weak web] _, defineErr in
                guard let self, let web else { return }
                if let defineErr {
                    print("⚠️ MMail dark-engine: DarkReader define failed: \(defineErr)")
                    // Fall back to an immediate measure so a define failure does not
                    // leave height at zero (the page still rendered, just not darkened).
                    self.measureHeight(web)
                    return
                }
                web.evaluateJavaScript(ReaderHTML.darkEnableScript()) { [weak self, weak web] _, enableErr in
                    guard let self, let web else { return }
                    if let enableErr {
                        print("⚠️ MMail dark-engine: DarkReader.enable failed: \(enableErr)")
                    }
                    // Defer the height read one runloop turn so the synchronously-injected
                    // styles + first layout have applied (see the escalation ladder above).
                    DispatchQueue.main.async { [weak self, weak web] in
                        guard let self, let web else { return }
                        self.measureHeight(web)
                    }
                }
            }
        }

        /// Toggle the dark transform IN-PLACE on the ALREADY-LOADED page (T009) — no
        /// reload, so no white-then-dark flash on every dark↔light / "Show original"
        /// toggle. Toggling ON re-injects the engine define (the page may have first
        /// loaded in light mode, never injecting it) then `DarkReader.enable(...)`;
        /// toggling OFF calls `DarkReader.disable()`. Every injected call is GUARDED with
        /// `if (window.DarkReader)` so a toggle on a never-injected page is a harmless
        /// no-op. After the toggle settles, re-measure the transformed-DOM height via the
        /// SAME deferred settle path as `applyDarkAndMeasure` (one runloop turn — see its
        /// escalation ladder).
        ///
        /// Generation snap-and-check (mirrors `load()`): capture `myGen = generation`
        /// BEFORE the async toggle; `guard generation == myGen` in BOTH the toggle
        /// completion AND the deferred height read, so a stale toggle cannot race a newer
        /// `load()` that already bumped `generation`.
        func toggleDark(_ web: WKWebView, applyDark: Bool) {
            // Record the intended state synchronously so a rapid follow-up `updateNSView`
            // re-detects the next change against the value this toggle is applying.
            lastApplyDark = applyDark
            let myGen = generation

            // Build the in-place JS. ON: re-define the engine (cheap idempotent UMD eval)
            // then enable; OFF: disable. Both guard on `window.DarkReader`.
            let toggleJS: String
            if applyDark {
                // Re-inject the engine define so a first-light-then-dark page gets the
                // global; `darkEnableScript()` itself also guards on `window.DarkReader`.
                let engine = HTMLMessageView.darkReaderScript ?? ""
                toggleJS = engine + "\n" + ReaderHTML.darkEnableScript()
            } else {
                toggleJS = "if (window.DarkReader) { window.DarkReader.disable(); }"
            }

            web.evaluateJavaScript(toggleJS) { [weak self, weak web] _, err in
                guard let self, let web else { return }
                // Stale toggle (a newer load() bumped generation): do nothing further.
                guard self.generation == myGen else { return }
                if let err {
                    print("⚠️ MMail dark-engine: in-place toggle failed: \(err)")
                }
                // Re-measure on the next runloop turn so the restyle + relayout has
                // applied (DarkReader's effect is not synchronous on completion).
                DispatchQueue.main.async { [weak self, weak web] in
                    guard let self, let web else { return }
                    guard self.generation == myGen else { return }
                    self.measureHeight(web)
                }
            }
        }

        /// Read `document.body.scrollHeight` and publish it to `height`. The sole height
        /// measure, routed through both the load-completion path (T008) and the in-place
        /// toggle path (T009) so a transformed-DOM layout shift never leaves a stale value.
        private func measureHeight(_ web: WKWebView) {
            web.evaluateJavaScript("document.body.scrollHeight") { result, _ in
                if let h = result as? CGFloat, h > 0 {
                    DispatchQueue.main.async { self.parent.height = ceil(h) }
                }
            }
        }

        // Open links in the user's browser instead of navigating inside the message.
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if navigationAction.navigationType == .linkActivated, let url = navigationAction.request.url {
                NSWorkspace.shared.open(Privacy.cleanLink(url))
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }
    }
}
