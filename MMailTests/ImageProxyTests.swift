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
