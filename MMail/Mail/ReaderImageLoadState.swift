import Foundation

/// The realized remote-image load path for the message currently displayed in the
/// reader's primary card. A read-only, display-only classification derived purely
/// from the SAME decision inputs the render path consumes — it can never disagree
/// with `HTMLMessageView` about Blocked vs Proxied vs Direct.
///
/// Input contract (mirroring `ReaderView.swift:290-291, 316-317`):
/// - `hasRemoteImages` — derived from `email.bodyHTML` via `hasRemoteImages(in:)`.
/// - `showImages == model.isImageTrusted(fromEmail) || loadImages` — the same value
///   passed (inverted) as `blockRemote: !showImages` at `ReaderView.swift:316`.
/// - `proxyActive == (model.imageProxyConfig != nil)` — the exact value passed as
///   `proxyConfig:` at `ReaderView.swift:317`.
///
/// This is the **shared-decision-inputs** invariant: the indicator derives
/// Blocked/Proxied/Direct from the SAME `!showImages` / `proxyConfig != nil` values
/// the render path forks on (`HTMLMessageView.swift:157-183`), not from a second,
/// independently-computed notion of "is this proxied".
enum ReaderImageLoadState: Equatable {
    /// The body has no remote image reference to fetch (plain-text body, or HTML
    /// with no `<img>` carrying an http(s) `src`/`srcset`).
    case noRemoteImages
    /// The body has remote images but they were NOT loaded (`showImages == false`);
    /// the standalone block-all content rule was installed and nothing was fetched.
    case blocked
    /// Images were shown AND a proxy is active; `<img src>` was rewritten to signed
    /// proxy URLs and fetches hit only the proxy host, not the sender's origin.
    case proxied
    /// Images were shown AND no proxy is active; remote `<img src>` loaded straight
    /// from origin (the IP / open-signal-leaking path).
    case loadedDirect

    /// Matches an `<img ...>` start tag (capturing its attribute span). Case-
    /// insensitive; does not span the closing `>`. Parallels `ImageProxy.imgTagRegex`
    /// (`ImageProxy.swift:76-79`).
    private static let imgTagRegex = try! NSRegularExpression(
        pattern: "<img\\b[^>]*>",
        options: [.caseInsensitive]
    )

    /// Within an img tag, matches a `src` attribute and captures the quote char
    /// (group 1) and the quoted value (group 2). Only matches `src`, never `srcset`
    /// (the `\\s*=` after `src` plus the `\\b` rules out `srcset`). Parallels
    /// `ImageProxy.srcAttrRegex` (`ImageProxy.swift:85-88`). Case-insensitive.
    private static let srcAttrRegex = try! NSRegularExpression(
        pattern: "\\bsrc\\s*=\\s*(\"|')(.*?)\\1",
        options: [.caseInsensitive]
    )

    /// Within an img tag, matches a `srcset` attribute and captures the quote char
    /// (group 1) and the quoted value (group 2). A separate quote-aware matcher
    /// because `srcset` carries a comma-separated candidate LIST, not a single URL.
    /// Case-insensitive.
    private static let srcsetAttrRegex = try! NSRegularExpression(
        pattern: "\\bsrcset\\s*=\\s*(\"|')(.*?)\\1",
        options: [.caseInsensitive]
    )

    /// Pure: does `bodyHTML` contain at least one `<img>` whose QUOTED `src` OR
    /// `srcset` holds a remote (`http://` / `https://`) reference? `Foundation`-only,
    /// no I/O. Detects QUOTED values only — intentionally consistent with
    /// `ImageProxy.rewriteTag`, which likewise acts only on quoted `src` (real
    /// HTML-email image refs are universally quoted; unquoted values are out of scope).
    static func hasRemoteImages(in bodyHTML: String?) -> Bool {
        guard let html = bodyHTML, !html.isEmpty else { return false }
        let full = NSRange(html.startIndex..., in: html)
        var found = false
        imgTagRegex.enumerateMatches(in: html, options: [], range: full) { match, _, stop in
            guard let m = match, let tagRange = Range(m.range, in: html) else { return }
            let tag = String(html[tagRange])
            if tagHasRemoteRef(tag) {
                found = true
                stop.pointee = true
            }
        }
        return found
    }

    /// True when a single `<img ...>` tag's quoted `src` (single URL) OR `srcset`
    /// (comma-separated candidate list) holds an `http(s)` reference.
    private static func tagHasRemoteRef(_ tag: String) -> Bool {
        let tagRange = NSRange(tag.startIndex..., in: tag)

        // `src`: a single URL — the whole value, trimmed, must start with http(s).
        if let m = srcAttrRegex.firstMatch(in: tag, options: [], range: tagRange),
           let valueRange = Range(m.range(at: 2), in: tag) {
            let value = String(tag[valueRange])
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            if value.hasPrefix("http://") || value.hasPrefix("https://") {
                return true
            }
        }

        // `srcset`: a comma-separated candidate list — an `http(s)` substring
        // anywhere in the value is sufficient (any candidate URL leaks remotely).
        if let m = srcsetAttrRegex.firstMatch(in: tag, options: [], range: tagRange),
           let valueRange = Range(m.range(at: 2), in: tag) {
            let value = String(tag[valueRange]).lowercased()
            if value.contains("http://") || value.contains("https://") {
                return true
            }
        }

        return false
    }

    /// Pure: map the three derived booleans to exactly one load-path state. No
    /// AppModel / WebKit / Keychain access — totally determined by its inputs.
    /// Exactly mirrors the render fork: block when `!showImages`
    /// (`ReaderView.swift:316` / `HTMLMessageView.swift:176-183`); proxied-vs-direct
    /// per `model.imageProxyConfig != nil` (`HTMLMessageView.swift:157-176`).
    static func classify(hasRemoteImages: Bool, showImages: Bool, proxyActive: Bool) -> ReaderImageLoadState {
        guard hasRemoteImages else { return .noRemoteImages }
        guard showImages else { return .blocked }
        return proxyActive ? .proxied : .loadedDirect
    }
}
