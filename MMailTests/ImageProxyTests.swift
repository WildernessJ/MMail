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
}
