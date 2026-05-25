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
    @Binding var height: CGFloat

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let web = WKWebView(frame: .zero, configuration: config)
        web.navigationDelegate = context.coordinator
        web.setValue(false, forKey: "drawsBackground")
        context.coordinator.load(web, html: html, blockRemote: blockRemote)
        return web
    }

    func updateNSView(_ web: WKWebView, context: Context) {
        if context.coordinator.lastHTML != html || context.coordinator.lastBlock != blockRemote {
            context.coordinator.load(web, html: html, blockRemote: blockRemote)
        }
    }

    private static func wrapped(_ html: String) -> String {
        """
        <!doctype html><html><head><meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>
          :root { color-scheme: light dark; }
          body { font: 14px -apple-system, system-ui, sans-serif; margin: 0; padding: 0;
                 word-wrap: break-word; overflow-wrap: anywhere; -webkit-text-size-adjust: 100%; }
          img, table { max-width: 100% !important; height: auto; }
          a { color: #2D3DEC; }
        </style></head><body>\(html)</body></html>
        """
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        let parent: HTMLMessageView
        var lastHTML = ""
        var lastBlock = true
        init(_ parent: HTMLMessageView) { self.parent = parent }

        private static let blockRules = """
        [{"trigger":{"url-filter":".*","resource-type":["image","media","style-sheet","font","raw","script","fetch","websocket","other"]},"action":{"type":"block"}}]
        """

        func load(_ web: WKWebView, html: String, blockRemote: Bool) {
            lastHTML = html
            lastBlock = blockRemote
            let body = HTMLMessageView.wrapped(html)
            web.configuration.userContentController.removeAllContentRuleLists()
            guard blockRemote else { web.loadHTMLString(body, baseURL: nil); return }
            WKContentRuleListStore.default().compileContentRuleList(
                forIdentifier: "mmail-block-remote",
                encodedContentRuleList: Self.blockRules) { list, _ in
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
