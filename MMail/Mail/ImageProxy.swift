import Foundation
import CryptoKit

/// Configuration for the image privacy proxy. Non-nil only when the user has
/// enabled proxying AND set a base URL AND a signing secret is present in the
/// Keychain (see `AppModel.imageProxyConfig`).
struct ImageProxyConfig {
    /// Base URL of the deployed Cloudflare Worker, e.g.
    /// `https://mmail-image-proxy.you.workers.dev`. Signed URLs are minted as
    /// `<baseURL>/proxy?u=...&e=...&s=...`.
    let baseURL: URL
    /// Shared HMAC signing secret. Matches the Worker's `PROXY_SECRET`. Lives
    /// only in the macOS Keychain — never in UserDefaults or the build.
    let signingSecret: String
}

/// Pure seam that rewrites remote `<img src>` URLs to signed proxy URLs and signs
/// asset URLs to match the Cloudflare Worker. No I/O; deterministic given an
/// injected clock so it is unit-testable against the pinned cross-language vector.
enum ImageProxy {
    /// Expiry window: signed URLs are valid for 300 s from mint time.
    static let expiryWindow = 300

    /// Characters left UNescaped when percent-encoding the asset URL into `u`.
    /// RFC 3986 "unreserved" set only — everything else (including `&`, `=`, `?`,
    /// `/`, `:`, and space) is percent-encoded, so space → `%20` (never form `+`)
    /// and the Worker's `decodeURIComponent` recovers the identical assetURL.
    private static let unreserved: CharacterSet = {
        var set = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789")
        set.insert(charactersIn: "-._~")
        return set
    }()

    /// base64url (no padding): `+`→`-`, `/`→`_`, strip `=`.
    private static func base64url(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    /// Sign one asset URL for a given expiry: base64url(HMAC-SHA256(key=secret
    /// UTF-8 bytes, message="<expiry>:<assetURL>" UTF-8 bytes)). Matches the Worker.
    static func sign(assetURL: String, expiry: Int, secret: String) -> String {
        let key = SymmetricKey(data: Data(secret.utf8))
        let message = Data("\(expiry):\(assetURL)".utf8)
        let mac = HMAC<SHA256>.authenticationCode(for: message, using: key)
        return base64url(Data(mac))
    }

    /// Mint a signed proxy URL for a single asset URL, or nil if it can't be
    /// proxied (empty/malformed asset, or non-http(s) scheme).
    static func proxiedURL(forAsset assetURL: String, config: ImageProxyConfig, now: Date) -> URL? {
        let trimmed = assetURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let lower = trimmed.lowercased()
        guard lower.hasPrefix("http://") || lower.hasPrefix("https://") else { return nil }

        let expiry = Int(now.timeIntervalSince1970.rounded(.down)) + expiryWindow
        let signature = sign(assetURL: trimmed, expiry: expiry, secret: config.signingSecret)
        guard let encodedAsset = trimmed.addingPercentEncoding(withAllowedCharacters: unreserved) else {
            return nil
        }

        // Assemble the query manually so the RFC-3986 encoding of `u` is preserved
        // verbatim (URLComponents.queryItems would re-encode and turn space into `+`
        // / un-escape sub-delims). `s` is base64url, so it is already URL-safe.
        let base = config.baseURL.absoluteString
        let sep = base.hasSuffix("/") ? "" : "/"
        let urlString = "\(base)\(sep)proxy?u=\(encodedAsset)&e=\(expiry)&s=\(signature)"
        return URL(string: urlString)
    }

    /// Rewrite every remote `<img src>` in `html` to a signed proxy URL, leaving
    /// all other markup byte-for-byte unchanged. Stub until T012.
    static func rewrite(html: String, config: ImageProxyConfig, now: Date) -> String {
        html
    }
}
