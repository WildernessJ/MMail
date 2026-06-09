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

    /// Matches an `<img ...>` start tag (capturing its attribute span). Case-
    /// insensitive; does not span the closing `>`.
    private static let imgTagRegex = try! NSRegularExpression(
        pattern: "<img\\b[^>]*>",
        options: [.caseInsensitive]
    )

    /// Within an img tag's attribute text, matches a `src` attribute and captures
    /// the quote char (group 1) and the quoted value (group 2). Only matches
    /// `src`, never `srcset` (the `\\s*=` after `src` plus the `\\b` rules out
    /// `srcset`). Case-insensitive.
    private static let srcAttrRegex = try! NSRegularExpression(
        pattern: "\\bsrc\\s*=\\s*(\"|')(.*?)\\1",
        options: [.caseInsensitive]
    )

    /// Decode the handful of HTML entities that appear in URL attribute values so
    /// the client and Worker share one canonical assetURL.
    private static func decodeEntities(_ s: String) -> String {
        guard s.contains("&") else { return s }
        return s
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&#38;", with: "&")
            .replacingOccurrences(of: "&#x26;", with: "&", options: .caseInsensitive)
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
    }

    /// Rewrite every remote `<img src>` in `html` to a signed proxy URL, leaving
    /// all other markup byte-for-byte unchanged. Pure and deterministic given `now`.
    static func rewrite(html: String, config: ImageProxyConfig, now: Date) -> String {
        let proxyHost = config.baseURL.host?.lowercased()
        let full = NSRange(html.startIndex..., in: html)
        var result = ""
        var lastEnd = html.startIndex

        imgTagRegex.enumerateMatches(in: html, options: [], range: full) { match, _, _ in
            guard let m = match, let tagRange = Range(m.range, in: html) else { return }
            // Copy the untouched span before this tag verbatim.
            result += html[lastEnd..<tagRange.lowerBound]
            lastEnd = tagRange.upperBound

            let tag = String(html[tagRange])
            result += rewriteTag(tag, config: config, now: now, proxyHost: proxyHost)
        }
        // Trailing remainder.
        result += html[lastEnd...]
        return result
    }

    /// Rewrite the `src` of a single `<img ...>` tag, or return it unchanged if it
    /// has no remote `src` (or is already proxied / non-http(s) / empty).
    private static func rewriteTag(_ tag: String, config: ImageProxyConfig,
                                   now: Date, proxyHost: String?) -> String {
        let tagRange = NSRange(tag.startIndex..., in: tag)
        guard let srcMatch = srcAttrRegex.firstMatch(in: tag, options: [], range: tagRange),
              let valueNSRange = Range(srcMatch.range(at: 2), in: tag) else {
            return tag
        }
        let rawValue = String(tag[valueNSRange])
        let assetURL = decodeEntities(rawValue).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !assetURL.isEmpty else { return tag }

        let lower = assetURL.lowercased()
        guard lower.hasPrefix("http://") || lower.hasPrefix("https://") else { return tag }

        // Idempotency: an `<img src>` already pointing at the proxy origin is left
        // as-is (re-wrapping would double-sign it).
        if let proxyHost, URL(string: assetURL)?.host?.lowercased() == proxyHost {
            return tag
        }

        guard let proxied = proxiedURL(forAsset: assetURL, config: config, now: now) else {
            return tag
        }

        // Replace ONLY the attribute value span, preserving the original quote
        // char and the rest of the tag byte-for-byte.
        return tag.replacingCharacters(in: valueNSRange, with: proxied.absoluteString)
    }
}
