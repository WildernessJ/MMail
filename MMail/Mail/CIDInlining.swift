import Foundation
import SwiftUI

/// Pure, view-free reader-HTML seams (unit-testable without a WebView host):
///   - `wrappedDocument(_:)` — the white-surface `<head>` builder (Bug A, white surface)
///   - `isReferenced(cidToken:inHTML:)` — "is this Content-ID referenced by an
///     `<img src="cid:…">`?" predicate (Bug B2)
///   - `inlineCIDImages(inHTML:parts:)` — the `cid:`→`data:<mime>;base64,…` rewrite (Bug B3)
///   - `InlinePart` — the (mimeType, bytes) value carried from parse to render
///
/// Everything here is `internal` (the default) so `@testable import MMail` can reach it.
/// Do NOT mark these `private`/`fileprivate`.
enum ReaderHTML {

    /// The single source of truth for the reader's fixed dark text color, emitted into
    /// the CSS `color` of the wrapped HTML body (T001) AND consumed by the plain-text
    /// `else` branch (T010) so the HTML and plain-text surfaces cannot visually diverge.
    static let bodyTextColorHex = "#1A1A1A"

    /// SwiftUI `Color` derived from the SAME hex as `bodyTextColorHex`, for the
    /// plain-text reader path's `.foregroundStyle` (single source of truth).
    static let bodyTextColor = Color(
        red: 0x1A / 255.0, green: 0x1A / 255.0, blue: 0x1A / 255.0
    )

    /// Build the full wrapped reader document for `innerHTML`. Forces an opaque
    /// pure-white surface decoupled from the app theme: `color-scheme: only light`
    /// so WebKit never applies a dark auto-transform, plus an opaque white background
    /// and a fixed dark text color so transparent/unstyled regions read white over the
    /// (possibly dark) window. The inner HTML is preserved verbatim. Full-bleed (no
    /// inset/card). Pure over the inner HTML string.
    static func wrappedDocument(_ innerHTML: String) -> String {
        """
        <!doctype html><html><head><meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>
          :root { color-scheme: only light; }
          html, body { background: #ffffff; color: \(bodyTextColorHex); }
          body { font: 14px -apple-system, system-ui, sans-serif; margin: 0; padding: 0;
                 word-wrap: break-word; overflow-wrap: anywhere; -webkit-text-size-adjust: 100%; }
          img, table { max-width: 100% !important; height: auto; }
          a { color: #2D3DEC; }
        </style></head><body>\(innerHTML)</body></html>
        """
    }

    // MARK: - B2: CID-referenced predicate (T003)

    /// True iff `cidToken` is referenced by an `<img … src="cid:TOKEN"…>` in `html`.
    /// The `cid:` scheme is matched case-insensitively; the TOKEN itself is matched
    /// case-SENSITIVELY (Content-IDs are case-sensitive per RFC 2392). Tolerant of
    /// single/double quotes and surrounding attribute whitespace.
    static func isReferenced(cidToken: String, inHTML html: String) -> Bool {
        guard !cidToken.isEmpty else { return false }
        // Match `cid:` (any case) then the exact token, anchored to the end of the
        // quoted attribute value (next char is a quote) so `cid:logo` does not match
        // `cid:logobar`. The token is regex-escaped so its own metacharacters (e.g. the
        // `.` and `@` in `image001.png@host`) are literal. Token is case-SENSITIVE
        // (RFC 2392); only the `cid:` scheme is case-insensitive.
        let escaped = NSRegularExpression.escapedPattern(for: cidToken)
        let pattern = "(?i:cid:)\(escaped)[\"']"
        guard let re = try? NSRegularExpression(pattern: pattern, options: []) else { return false }
        let range = NSRange(html.startIndex..., in: html)
        return re.firstMatch(in: html, options: [], range: range) != nil
    }

    // MARK: - B5: second-pass CID filter at the promotion boundary (T006)

    /// Result of the post-parse referenced/unreferenced filtering: the attachments
    /// that survive (referenced inline CID parts dropped, everything else kept) and
    /// the referenced CID→`InlinePart` BYTES map for render-time inlining (T007).
    struct CIDFilterResult {
        let survivingAttachments: [MIME.Attachment]
        let inlineParts: [String: InlinePart]
    }

    /// Second pass over a fully-assembled parse result. Given the message `html` and
    /// the parsed `attachments`, DROP any attachment whose `contentID` is non-nil AND
    /// referenced by a `cid:` in the HTML (it renders inline instead), and KEEP every
    /// other part (unreferenced CID parts and no-CID parts stay normal attachments).
    /// Also build the referenced CID→bytes map so the render-time `data:` rewrite has
    /// the embedded bytes (which `AttachmentMeta` discards). Pure over (HTML, parts).
    static func filterInlineCID(html: String?, attachments: [MIME.Attachment]) -> CIDFilterResult {
        guard let html, html.range(of: "cid:", options: .caseInsensitive) != nil else {
            return CIDFilterResult(survivingAttachments: attachments, inlineParts: [:])
        }
        var surviving: [MIME.Attachment] = []
        var parts: [String: InlinePart] = [:]
        for att in attachments {
            if let cid = att.contentID, isReferenced(cidToken: cid, inHTML: html) {
                parts[cid] = InlinePart(mimeType: att.mimeType, data: att.data)
            } else {
                surviving.append(att)
            }
        }
        return CIDFilterResult(survivingAttachments: surviving, inlineParts: parts)
    }

    // MARK: - B3: cid:→data: rewrite (T004)

    /// Rewrite every `<img src="cid:TOKEN">` whose TOKEN matches a key in `parts` to a
    /// `data:<mimeType>;base64,<base64>` URI so the embedded image renders inline.
    /// Dangling `cid:` refs (no matching part) are left untouched (no crash, no
    /// fabrication). Pure over (HTML, map). Token matching is case-sensitive (RFC 2392).
    static func inlineCIDImages(inHTML html: String, parts: [String: InlinePart]) -> String {
        guard !parts.isEmpty, html.range(of: "cid:", options: .caseInsensitive) != nil else { return html }
        var out = html
        for (token, part) in parts {
            guard !token.isEmpty else { continue }
            let dataURI = "data:\(part.mimeType);base64,\(part.base64)"
            // Replace `cid:TOKEN` exactly (case-sensitive token, case-insensitive scheme),
            // anchored to a following quote so `cid:logo` does not match `cid:logobar`.
            let escaped = NSRegularExpression.escapedPattern(for: token)
            let pattern = "(?i:cid:)\(escaped)(?=[\"'])"
            guard let re = try? NSRegularExpression(pattern: pattern, options: []) else { continue }
            let range = NSRange(out.startIndex..., in: out)
            // Escape `$`/`\` in the replacement so the base64 string is inserted literally.
            let replacement = NSRegularExpression.escapedTemplate(for: dataURI)
            out = re.stringByReplacingMatches(in: out, options: [], range: range, withTemplate: replacement)
        }
        return out
    }
}

/// A render-time inline part: the embedded image's MIME type and its raw bytes. Built
/// from a `MIME.Attachment`'s `(mimeType, data)` at the promotion boundary, carried to
/// the reader via a render-time-only, NON-cache-serialized map keyed by `Email.id`.
struct InlinePart: Equatable {
    let mimeType: String
    let data: Data

    init(mimeType: String, data: Data) {
        self.mimeType = mimeType
        self.data = data
    }

    /// Base64 of the bytes with no line breaks (suitable for a `data:` URI).
    var base64: String { data.base64EncodedString() }
}
