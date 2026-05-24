import SwiftUI
import WebKit

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
                NSWorkspace.shared.open(url)
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }
    }
}
