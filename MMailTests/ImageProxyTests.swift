import Testing
import Foundation
@testable import MMail

/// Unit tests for the image privacy proxy's pure seams: the CryptoKit signer
/// (asserted against the pinned cross-language HMAC vector shared with the
/// Worker), the HTML `<img src>` rewriter, and the Keychain secret storage.
@Suite struct ImageProxyTests {

    // MARK: - Pinned cross-language vector (must match proxy-worker/test/vector.json)

    /// K — ASCII-printable secret (unambiguous UTF-8 bytes across CryptoKit,
    /// crypto.subtle, and openssl).
    private let K = "mmail-proxy-test-secret-v1"
    /// A — asset URL deliberately containing a space and an `&`.
    private let A = "https://x.test/a b.gif?u=1&v=2"
    /// e — fixed expiry. The signer computes e = floor(now)+300, so inject a clock
    /// 300 s earlier.
    private let e = 1_900_000_300
    /// S — the signature openssl produced for ("<e>:<A>", key=K). Pinned verbatim.
    private let S = "uWhC12gGW0FwsCdVPPxtSTEUlhqu3PPL-z9mFQBPgd0"

    /// A2 — asset URL whose canonical form contains a LITERAL `%XX` sequence
    /// (`caf%C3%A9`, `q=a%2Fb`) AND a multi-byte UTF-8 char. This is the
    /// regression guard for "decode u exactly once": the minted `u`, decoded a
    /// SINGLE time, must recover A2 byte-for-byte. (A double-decode would turn
    /// `%25C3` back into `%C3` and corrupt the value.)
    private let A2 = "https://x.test/caf%C3%A9  details.gif?q=a%2Fb"
    /// e2 — fixed expiry for vector 2.
    private let e2 = 1_900_000_300
    /// S2 — the signature openssl produced for ("<e2>:<A2>", key=K). Pinned verbatim.
    private let S2 = "vsny-_a3X6xftatAQKcbdKNv9mdmNVb_RriwvjfKurA"

    private var vectorConfig: ImageProxyConfig {
        ImageProxyConfig(baseURL: URL(string: "https://proxy.test")!, signingSecret: K)
    }

    /// Clock such that floor(now)+300 == e.
    private var vectorClock: Date {
        Date(timeIntervalSince1970: TimeInterval(e - 300))
    }

    // MARK: - Signer (SC-003)

    /// The Swift signer emits exactly the pinned S, with e = floor(now)+300, and
    /// percent-encodes the space in A as %20 (RFC 3986), never form `+`.
    @Test func signerMatchesPinnedVector() throws {
        let url = try #require(
            ImageProxy.proxiedURL(forAsset: A, config: vectorConfig, now: vectorClock)
        )
        let comps = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let items = comps.queryItems ?? []
        let s = items.first { $0.name == "s" }?.value
        let eParam = items.first { $0.name == "e" }?.value

        #expect(s == S, "signature must equal the pinned cross-language vector S")
        #expect(eParam == String(e), "e must equal floor(now)+300")

        // The raw query string must contain %20 for the space in A, never a `+`.
        let rawQuery = try #require(comps.percentEncodedQuery)
        #expect(rawQuery.contains("a%20b.gif"), "space must be %20-encoded, not form +")
        #expect(!rawQuery.contains("a+b.gif"), "space must not be form-encoded as +")
    }

    /// Second pinned vector (FIX 2 regression / cross-language single-decode
    /// contract): the Swift signer emits exactly S2 for an asset URL that already
    /// contains a literal `%XX`, AND the `u` it mints, decoded EXACTLY ONCE,
    /// recovers A2 byte-for-byte (proving the Worker must not double-decode).
    @Test func signerMatchesSecondVectorAndRoundTrips() throws {
        let clock = Date(timeIntervalSince1970: TimeInterval(e2 - 300))
        let url = try #require(
            ImageProxy.proxiedURL(forAsset: A2, config: vectorConfig, now: clock)
        )
        let comps = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let items = comps.queryItems ?? []
        let s = items.first { $0.name == "s" }?.value
        let eParam = items.first { $0.name == "e" }?.value

        #expect(s == S2, "signature must equal the pinned second vector S2")
        #expect(eParam == String(e2), "e must equal floor(now)+300")

        // Single-decode round-trip: pull the RAW (still percent-encoded) `u` out of
        // the query and decode it exactly once. It MUST equal A2 byte-for-byte.
        let rawQuery = try #require(comps.percentEncodedQuery)
        let rawU = try #require(
            rawQuery
                .split(separator: "&")
                .first { $0.hasPrefix("u=") }
                .map { String($0.dropFirst(2)) }
        )
        // The literal `%C3` in A2 must appear in `u` as the double-encoded `%25C3`,
        // so a SINGLE decode recovers it (a double-decode would corrupt it).
        #expect(rawU.contains("%25C3"), "literal % in A2 must be encoded as %25 in u")
        let decodedOnce = try #require(rawU.removingPercentEncoding)
        #expect(decodedOnce == A2,
                "single decode of u must recover A2 byte-for-byte (no double-decode)")
    }

    // MARK: - Rewriter (SC-005)

    private let rewriteConfig = ImageProxyConfig(
        baseURL: URL(string: "https://proxy.test")!,
        signingSecret: "rewrite-secret"
    )
    private let rewriteClock = Date(timeIntervalSince1970: 1_700_000_000)

    /// The proxy URL the rewriter should produce for a given (already-decoded)
    /// asset, so tests can compare against the real signer output.
    private func expectedProxyURL(_ asset: String) -> String {
        ImageProxy.proxiedURL(forAsset: asset, config: rewriteConfig, now: rewriteClock)!
            .absoluteString
    }

    private func rewrite(_ html: String) -> String {
        ImageProxy.rewrite(html: html, config: rewriteConfig, now: rewriteClock)
    }

    /// A single remote `<img src>` is replaced by the signed proxy URL; the rest
    /// of the HTML is untouched.
    @Test func singleRemoteImgIsRewritten() {
        let asset = "https://track.example/p.gif?id=ME"
        let html = "<p>hi</p><img src=\"\(asset)\"><p>bye</p>"
        let out = rewrite(html)
        let proxied = expectedProxyURL(asset)
        #expect(out == "<p>hi</p><img src=\"\(proxied)\"><p>bye</p>")
    }

    /// Non-image and non-remote sources are left untouched.
    @Test func nonImageAndNonRemoteSourcesUntouched() {
        let html = """
        <script src="https://x.test/a.js"></script>\
        <iframe src="https://x.test/f.html"></iframe>\
        <link href="https://x.test/s.css" rel="stylesheet">\
        <img src="cid:abc123">\
        <img src="data:image/png;base64,AAAA">\
        <img src="/relative.png">
        """
        #expect(rewrite(html) == html)
    }

    /// srcset and CSS url() are out of scope — never rewritten.
    @Test func srcsetAndCssUrlUntouched() {
        let html = """
        <img srcset="https://x.test/a.jpg 1x">\
        <div style="background-image:url(https://x.test/b.jpg)">x</div>
        """
        #expect(rewrite(html) == html)
    }

    /// Rewriting an already-proxied `<img src>` is idempotent.
    @Test func alreadyProxiedIsIdempotent() {
        let asset = "https://track.example/p.gif"
        let once = rewrite("<img src=\"\(asset)\">")
        let twice = rewrite(once)
        #expect(once == twice, "rewriting an already-proxied URL must be a fixpoint")
    }

    /// HTML with no remote `<img>` is returned unchanged.
    @Test func imageFreeHtmlUnchanged() {
        let html = "<p>No images here. <a href=\"https://x.test\">link</a></p>"
        #expect(rewrite(html) == html)
    }

    /// Empty or malformed `src` produces no signed URL and no rewrite.
    @Test func emptyOrMalformedSrcUntouched() {
        let html = "<img src=\"\"><img>"
        #expect(rewrite(html) == html)
    }

    /// An `<img src>` that appears only INSIDE a `<script>` body (e.g. a JS string
    /// literal) is NOT markup the browser renders — it must be left byte-for-byte.
    @Test func imgInsideScriptIsUntouched() {
        let html = "<script>var t='<img src=\"https://x.test/t.gif\">'</script>"
        #expect(rewrite(html) == html, "img inside <script> must not be rewritten")
    }

    /// Same for an `<img src>` inside a `<style>` body (it's CSS text, not markup).
    @Test func imgInsideStyleIsUntouched() {
        let html = "<style>/* <img src=\"https://x.test/t.gif\"> */ body{}</style>"
        #expect(rewrite(html) == html, "img inside <style> must not be rewritten")
    }

    /// Same for an `<img src>` inside an HTML comment.
    @Test func imgInsideCommentIsUntouched() {
        let html = "<!-- <img src=\"https://x.test/t.gif\"> -->"
        #expect(rewrite(html) == html, "img inside a comment must not be rewritten")
    }

    /// A real `<img>` OUTSIDE any script/style/comment is still rewritten, even
    /// when those skip-spans are present alongside it.
    @Test func realImgRewrittenAlongsideSkipSpans() {
        let asset = "https://track.example/real.gif"
        let html = "<script>var s='<img src=\"https://x.test/in-js.gif\">';</script>"
            + "<img src=\"\(asset)\">"
            + "<style>.x{background:url(https://x.test/css.gif)}</style>"
            + "<!-- <img src=\"https://x.test/in-comment.gif\"> -->"
        let out = rewrite(html)
        let proxied = expectedProxyURL(asset)
        let expected = "<script>var s='<img src=\"https://x.test/in-js.gif\">';</script>"
            + "<img src=\"\(proxied)\">"
            + "<style>.x{background:url(https://x.test/css.gif)}</style>"
            + "<!-- <img src=\"https://x.test/in-comment.gif\"> -->"
        #expect(out == expected,
                "the real img is rewritten; script/style/comment spans are verbatim")
    }

    /// An HTML-entity-encoded `src` (`&amp;` -> `&`) is decoded to the canonical
    /// assetURL before signing, so the signature is over the decoded form.
    @Test func entityDecodedSrcIsTheSignedValue() throws {
        let decodedAsset = "https://track.example/p.gif?a=1&b=2"
        let html = "<img src=\"https://track.example/p.gif?a=1&amp;b=2\">"
        let out = rewrite(html)

        // Extract the produced src and confirm its `s` matches signing the DECODED url.
        let proxied = expectedProxyURL(decodedAsset)
        #expect(out == "<img src=\"\(proxied)\">")
    }

    // MARK: - Keychain secret storage (SC-004)

    /// The signing secret round-trips through the Keychain AND is never written to
    /// UserDefaults under the Keychain account key (the "never in UserDefaults"
    /// invariant).
    @Test func proxySecretRoundTripsAndStaysOutOfUserDefaults() {
        let key = Keychain.proxySecretAccount
        // Hermetic: ensure no stale UserDefaults value masks the assertion.
        UserDefaults.standard.removeObject(forKey: key)
        defer { Keychain.storeProxySecret("") }   // clear the Keychain after the test

        Keychain.storeProxySecret("super-secret-hmac-key")
        #expect(Keychain.readProxySecret() == "super-secret-hmac-key")
        #expect(UserDefaults.standard.string(forKey: key) == nil,
                "the signing secret must NEVER be written to UserDefaults")
    }
}
