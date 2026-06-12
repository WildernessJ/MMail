import XCTest
import WebKit
@testable import MMail

/// FEASIBILITY GATE (dark-engine) — headless, empirical.
///
/// Confirms HEADLESSLY (no human looking at the app) the two technical cruxes the
/// dark-engine feature depends on, by MEASURING the computed background color of the
/// reader document after the vendored DarkReader engine's `enable()` runs in-page:
///
///   1. The body HTML loads with `baseURL: nil` (an `about:blank` origin) — does
///      DarkReader run over that origin at all?
///   2. The white substrate forces `:root { color-scheme: only light; }` (built by the
///      REAL `ReaderHTML.wrappedDocument`) — does DarkReader OVERRIDE that and actually
///      darken, or short-circuit (skip a document it sees as light-only)?
///
/// PASS  = measured `body`/`html` computed background is DARK (low luminance).
/// FAIL  = stayed white/light (DarkReader short-circuited or never ran).
/// The measured `rgb(...)` strings are printed LOUDLY regardless of pass/fail so the
/// orchestrator has the raw evidence to judge.
///
/// This is XCTest (not Swift Testing like the rest of the suite) on purpose: the test
/// needs a `WKNavigationDelegate` + `XCTestExpectation` for the async page-load + JS
/// settle dance, which is XCTest's native idiom. Both frameworks coexist in the target.
final class DarkEngineFeasibilityTests: XCTestCase {

    // The SAME theme config the Phase A spike used (HTMLMessageView.Coordinator
    // .spikeEnableScript): dynamic mode 1, bg #1a1a1a, light text. Mirroring it means
    // this test exercises exactly what production would inject.
    private static let enableScript = """
    if (window.DarkReader) {
      window.DarkReader.enable({
        mode: 1,
        brightness: 100,
        contrast: 100,
        sepia: 0,
        darkSchemeBackgroundColor: '#1a1a1a',
        darkSchemeTextColor: '#e8e8e8'
      });
    }
    """

    /// Navigation delegate that fulfills an expectation on `didFinish`.
    private final class LoadDelegate: NSObject, WKNavigationDelegate {
        let onFinish: () -> Void
        let onFail: (Error) -> Void
        init(onFinish: @escaping () -> Void, onFail: @escaping (Error) -> Void) {
            self.onFinish = onFinish
            self.onFail = onFail
        }
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { onFinish() }
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { onFail(error) }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { onFail(error) }
    }

    /// Load the vendored darkreader.js the SAME way production does first
    /// (`Bundle.main`), then fall through resource bundles, then the absolute source
    /// path. Returns (source, how) so the test can report exactly how it was loaded.
    private func loadDarkReaderJS() -> (source: String, how: String)? {
        // 1) Production path: the main app bundle. Under the unit-test host `Bundle.main`
        //    is the test RUNNER, so this is expected to miss here — but try it first so
        //    we mirror production and report the truth.
        if let url = Bundle.main.url(forResource: "darkreader", withExtension: "js"),
           let s = try? String(contentsOf: url, encoding: .utf8) {
            return (s, "Bundle.main (\(url.path))")
        }
        // 2) The MMail target's resource bundle, reached via a class FROM that module
        //    (AppModel lives in MMail), so Bundle(for:) resolves the app bundle — not
        //    the test bundle. No instance is created; only the type is used.
        let mmailBundle = Bundle(for: AppModel.self)
        if let url = mmailBundle.url(forResource: "darkreader", withExtension: "js"),
           let s = try? String(contentsOf: url, encoding: .utf8) {
            return (s, "Bundle(for: MMail type) (\(url.path))")
        }
        // 3) The test bundle itself (in case XcodeGen classified it into the test target).
        let testBundle = Bundle(for: Self.self)
        if let url = testBundle.url(forResource: "darkreader", withExtension: "js"),
           let s = try? String(contentsOf: url, encoding: .utf8) {
            return (s, "Bundle(for: testCase) (\(url.path))")
        }
        // 4) Absolute source path fallback so the test still runs even if the resource
        //    did not ship into any bundle under the test host.
        let srcPath = "/Users/jbholdy/Documents/Github/MMail/MMail/Resources/darkreader.js"
        if let s = try? String(contentsOf: URL(fileURLWithPath: srcPath), encoding: .utf8) {
            return (s, "absolute source path (\(srcPath))")
        }
        return nil
    }

    /// Parse an `rgb(r, g, b)` / `rgba(r, g, b, a)` string into (r,g,b) bytes.
    private func parseRGB(_ s: String) -> (r: Double, g: Double, b: Double)? {
        guard let open = s.firstIndex(of: "("), let close = s.firstIndex(of: ")") else { return nil }
        let inner = s[s.index(after: open)..<close]
        let comps = inner.split(separator: ",").map {
            Double($0.trimmingCharacters(in: .whitespaces)) ?? Double.nan
        }
        guard comps.count >= 3, !comps[0].isNaN, !comps[1].isNaN, !comps[2].isNaN else { return nil }
        return (comps[0], comps[1], comps[2])
    }

    /// Perceived (Rec. 601) luminance, 0...1.
    private func luminance(_ rgb: (r: Double, g: Double, b: Double)) -> Double {
        (0.299 * rgb.r + 0.587 * rgb.g + 0.114 * rgb.b) / 255.0
    }

    @MainActor
    func testDarkReaderDarkensColorSchemeOnlyLightSubstrate() throws {
        // 0) Engine source must be reachable, or the test cannot run.
        guard let (engine, how) = loadDarkReaderJS() else {
            XCTFail("INCONCLUSIVE: could not load darkreader.js from any bundle or the source path")
            return
        }
        NSLog("DARK-ENGINE-FEASIBILITY: darkreader.js loaded via %@ (%d bytes)", how, engine.count)
        print("DARK-ENGINE-FEASIBILITY: darkreader.js loaded via \(how) (\(engine.count) bytes)")

        // 1) Build the REAL substrate document (color-scheme: only light + white bg).
        let doc = ReaderHTML.wrappedDocument("<p>Hello world</p>")
        XCTAssertTrue(doc.contains("color-scheme: only light"), "test must exercise the real light-only substrate")

        // 2) Offscreen WKWebView with a real frame (safer than .zero for layout/computed
        //    style), loading with baseURL: nil to MATCH production.
        let web = WKWebView(frame: CGRect(x: 0, y: 0, width: 800, height: 600),
                            configuration: WKWebViewConfiguration())
        let loaded = expectation(description: "page didFinish")
        let delegate = LoadDelegate(
            onFinish: { loaded.fulfill() },
            onFail: { err in XCTFail("INCONCLUSIVE: navigation failed: \(err)"); loaded.fulfill() }
        )
        web.navigationDelegate = delegate
        web.loadHTMLString(doc, baseURL: nil)
        wait(for: [loaded], timeout: 30)

        // 3) Define the DarkReader global (same as production's first evaluation).
        let defined = expectation(description: "darkreader define")
        web.evaluateJavaScript(engine) { _, err in
            XCTAssertNil(err, "INCONCLUSIVE: darkreader.js evaluation failed: \(String(describing: err))")
            defined.fulfill()
        }
        wait(for: [defined], timeout: 30)

        // Sanity: the global is actually reachable post-define.
        let globalCheck = expectation(description: "DarkReader global present")
        web.evaluateJavaScript("typeof window.DarkReader") { result, _ in
            let t = result as? String ?? "undefined"
            NSLog("DARK-ENGINE-FEASIBILITY: typeof window.DarkReader = %@", t)
            print("DARK-ENGINE-FEASIBILITY: typeof window.DarkReader = \(t)")
            XCTAssertEqual(t, "object", "DarkReader global must exist after define")
            globalCheck.fulfill()
        }
        wait(for: [globalCheck], timeout: 30)

        // 4) enable() with the SAME theme config the spike used.
        let enabled = expectation(description: "DarkReader.enable")
        web.evaluateJavaScript(Self.enableScript) { _, err in
            XCTAssertNil(err, "INCONCLUSIVE: DarkReader.enable failed: \(String(describing: err))")
            enabled.fulfill()
        }
        wait(for: [enabled], timeout: 30)

        // 5) SETTLE: the transform is not fully applied synchronously when enable()
        //    returns. Give it a generous settle before measuring.
        let settled = expectation(description: "settle")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { settled.fulfill() }
        wait(for: [settled], timeout: 5)

        // 6) MEASURE the computed background of body AND documentElement (html).
        var bodyBG = "<unmeasured>"
        var htmlBG = "<unmeasured>"
        let measuredBody = expectation(description: "measure body bg")
        web.evaluateJavaScript("window.getComputedStyle(document.body).backgroundColor") { result, _ in
            bodyBG = result as? String ?? "<nil>"
            measuredBody.fulfill()
        }
        let measuredHTML = expectation(description: "measure html bg")
        web.evaluateJavaScript("window.getComputedStyle(document.documentElement).backgroundColor") { result, _ in
            htmlBG = result as? String ?? "<nil>"
            measuredHTML.fulfill()
        }
        wait(for: [measuredBody, measuredHTML], timeout: 30)

        // 7) Print LOUDLY regardless of pass/fail — orchestrator needs the raw value.
        NSLog("DARK-ENGINE-FEASIBILITY: MEASURED body backgroundColor = %@", bodyBG)
        NSLog("DARK-ENGINE-FEASIBILITY: MEASURED html backgroundColor = %@", htmlBG)
        print("DARK-ENGINE-FEASIBILITY: MEASURED body backgroundColor = \(bodyBG)")
        print("DARK-ENGINE-FEASIBILITY: MEASURED html backgroundColor = \(htmlBG)")
        let attachment = XCTAttachment(string: "body=\(bodyBG)\nhtml=\(htmlBG)\nengineLoadedVia=\(how)")
        attachment.name = "dark-engine-measured-colors"
        attachment.lifetime = .keepAlways
        add(attachment)

        // 8) ASSERT the background is DARK, not white. A white/near-white result means
        //    DarkReader did NOT darken → crux failure.
        //    We measure BOTH surfaces; the painted reader background is what the user
        //    sees, so require AT LEAST ONE of body/html to be measurably dark, and never
        //    accept a white body.
        let bodyRGB = parseRGB(bodyBG)
        let htmlRGB = parseRGB(htmlBG)
        XCTAssertNotNil(bodyRGB, "could not parse body background '\(bodyBG)'")

        let bodyLum = bodyRGB.map(luminance) ?? 1.0
        let htmlLum = htmlRGB.map(luminance) ?? 1.0
        NSLog("DARK-ENGINE-FEASIBILITY: luminance body=%.3f html=%.3f", bodyLum, htmlLum)
        print("DARK-ENGINE-FEASIBILITY: luminance body=\(bodyLum) html=\(htmlLum)")

        // The reader surface the user sees is the body background; assert it darkened.
        // Threshold: perceived luminance < 0.3 (a #1a1a1a target is ~0.10).
        XCTAssertLessThan(bodyLum, 0.3,
            "FAIL: body background did NOT darken — measured \(bodyBG) (lum \(bodyLum)). DarkReader short-circuited the color-scheme:only-light substrate or did not run over the baseURL:nil origin.")
    }
}
