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
    @Binding var height: CGFloat

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let web = WKWebView(frame: .zero, configuration: config)
        web.navigationDelegate = context.coordinator
        web.setValue(false, forKey: "drawsBackground")
        context.coordinator.load(web, html: html, blockRemote: blockRemote, proxyConfig: proxyConfig)
        return web
    }

    func updateNSView(_ web: WKWebView, context: Context) {
        let c = context.coordinator
        if c.lastHTML != html || c.lastBlock != blockRemote || c.lastProxyConfig != proxyConfig {
            c.load(web, html: html, blockRemote: blockRemote, proxyConfig: proxyConfig)
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

    final class Coordinator: NSObject, WKNavigationDelegate {
        let parent: HTMLMessageView
        var lastHTML = ""
        var lastBlock = true
        var lastProxyConfig: ImageProxyConfig?
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

        func load(_ web: WKWebView, html: String, blockRemote: Bool, proxyConfig: ImageProxyConfig?) {
            lastHTML = html
            lastBlock = blockRemote
            lastProxyConfig = proxyConfig

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
            webView.evaluateJavaScript("document.body.scrollHeight") { result, _ in
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
