import Foundation

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
    /// Mint a signed proxy URL for a single asset URL, or nil if it can't be
    /// proxied (empty/malformed asset). Stub until T010.
    static func proxiedURL(forAsset assetURL: String, config: ImageProxyConfig, now: Date) -> URL? {
        nil
    }

    /// Rewrite every remote `<img src>` in `html` to a signed proxy URL, leaving
    /// all other markup byte-for-byte unchanged. Stub until T012.
    static func rewrite(html: String, config: ImageProxyConfig, now: Date) -> String {
        html
    }
}
