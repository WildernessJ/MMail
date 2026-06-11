import Testing
import Foundation
@testable import MMail

/// Unit tests for the PURE reader-HTML seams in `ReaderHTML` (no WebView, no AppModel):
///   - the white-surface wrapped-`<head>` builder (`wrappedDocument`) — SC-005a
///   - the `cid:`-referenced predicate (`isReferenced(cidToken:inHTML:)`) — SC-005c
///   - the `cid:`→`data:` rewrite (`inlineCIDImages(inHTML:parts:)`) — SC-005b
/// plus the additive MIME Content-ID capture (T005). Everything is exercised with
/// injected `String` / `[String: InlinePart]` values, proving purity. The WebView
/// render, remote-block interaction, and real-email checks are the manual exploration
/// step, not assertable by this target.
@Suite struct CIDInliningTests {

    // MARK: - White-surface head builder (SC-005a)

    @Test func headForcesOnlyLightColorScheme() {
        let doc = ReaderHTML.wrappedDocument("<p>hi</p>")
        #expect(doc.contains("color-scheme: only light"))
        #expect(!doc.contains("color-scheme: light dark"))
    }

    @Test func headPaintsOpaqueWhiteBackground() {
        let doc = ReaderHTML.wrappedDocument("<p>hi</p>")
        // An opaque white background behind the body (so transparent regions read white).
        #expect(doc.contains("background: #ffffff"))
    }

    @Test func headEmitsTheSharedFixedDarkTextColor() {
        // The CSS color comes from the SINGLE source of truth shared with the
        // plain-text path (T010), so the two surfaces cannot diverge.
        let doc = ReaderHTML.wrappedDocument("<p>hi</p>")
        #expect(doc.contains("color: \(ReaderHTML.bodyTextColorHex)"))
    }

    @Test func headPreservesInnerHTMLVerbatim() {
        let inner = "<div class=\"x\">Sender's <b>own</b> markup &amp; <img src=\"cid:logo@acme\"></div>"
        let doc = ReaderHTML.wrappedDocument(inner)
        #expect(doc.contains(inner))
    }

    // MARK: - B2 predicate: isReferenced (SC-005c)

    @Test func referencedTokenIsDetected() {
        let html = "<p><img src=\"cid:logo@acme\"></p>"
        #expect(ReaderHTML.isReferenced(cidToken: "logo@acme", inHTML: html) == true)
    }

    @Test func singleQuotedSrcIsDetected() {
        let html = "<img src='cid:logo@acme'>"
        #expect(ReaderHTML.isReferenced(cidToken: "logo@acme", inHTML: html) == true)
    }

    @Test func caseInsensitiveCidSchemeStillMatches() {
        let html = "<img src=\"CID:logo@acme\">"
        #expect(ReaderHTML.isReferenced(cidToken: "logo@acme", inHTML: html) == true)
    }

    @Test func tokenPresentOnlyAsAttachmentIsNotReferenced() {
        // The token appears as a Content-ID-ish string but NOT inside an `<img src="cid:…">`.
        let html = "<p>see attached file image001@host.png</p>"
        #expect(ReaderHTML.isReferenced(cidToken: "image001@host", inHTML: html) == false)
    }

    @Test func absentTokenIsNotReferenced() {
        let html = "<img src=\"cid:other@host\">"
        #expect(ReaderHTML.isReferenced(cidToken: "logo@acme", inHTML: html) == false)
    }

    @Test func prefixTokenDoesNotPartialMatch() {
        // `cid:logo` must NOT count as referencing token `log` (anchored to the quote).
        let html = "<img src=\"cid:logobar@acme\">"
        #expect(ReaderHTML.isReferenced(cidToken: "logo@acme", inHTML: html) == false)
    }

    @Test func emptyTokenIsNeverReferenced() {
        #expect(ReaderHTML.isReferenced(cidToken: "", inHTML: "<img src=\"cid:\">") == false)
    }

    // MARK: - B3 rewrite: inlineCIDImages (SC-005b)

    private func pngPart(_ bytes: [UInt8]) -> InlinePart {
        InlinePart(mimeType: "image/png", data: Data(bytes))
    }

    @Test func matchedRefIsRewrittenToDataURI() {
        let html = "<img src=\"cid:logo@acme\">"
        let part = pngPart([0x89, 0x50, 0x4E, 0x47])
        let out = ReaderHTML.inlineCIDImages(inHTML: html, parts: ["logo@acme": part])
        #expect(out.contains("data:image/png;base64,\(part.base64)"))
        #expect(!out.contains("cid:logo@acme"))
    }

    @Test func danglingRefIsLeftUntouched() {
        let html = "<img src=\"cid:missing@host\">"
        let out = ReaderHTML.inlineCIDImages(inHTML: html, parts: ["logo@acme": pngPart([0x00])])
        #expect(out == html)
        #expect(out.contains("cid:missing@host"))
    }

    @Test func multipleDistinctRefsAreAllRewritten() {
        let html = "<img src=\"cid:a@x\"><img src='cid:b@y'><img src=\"cid:c@z\">"
        let parts: [String: InlinePart] = [
            "a@x": InlinePart(mimeType: "image/png", data: Data([0x01])),
            "b@y": InlinePart(mimeType: "image/gif", data: Data([0x02])),
            "c@z": InlinePart(mimeType: "image/jpeg", data: Data([0x03])),
        ]
        let out = ReaderHTML.inlineCIDImages(inHTML: html, parts: parts)
        #expect(out.contains("data:image/png;base64,\(parts["a@x"]!.base64)"))
        #expect(out.contains("data:image/gif;base64,\(parts["b@y"]!.base64)"))
        #expect(out.contains("data:image/jpeg;base64,\(parts["c@z"]!.base64)"))
        #expect(!out.contains("cid:"))
    }

    @Test func emptyPartsMapIsIdentity() {
        let html = "<img src=\"cid:logo@acme\">"
        #expect(ReaderHTML.inlineCIDImages(inHTML: html, parts: [:]) == html)
    }

    // MARK: - MIME Content-ID capture (T005, additive — in-memory only)

    @Test func relatedImagePartCapturesBracketStrippedContentID() {
        let raw = """
        Content-Type: multipart/related; boundary="b"\r
        \r
        --b\r
        Content-Type: text/html; charset=utf-8\r
        \r
        <img src="cid:logo@acme">\r
        --b\r
        Content-Type: image/png\r
        Content-Transfer-Encoding: base64\r
        Content-ID: <logo@acme>\r
        Content-Disposition: inline; filename="logo.png"\r
        \r
        iVBORw0KGgo=\r
        --b--\r
        """
        let parsed = MIME.parse(Data(raw.utf8))
        let img = parsed.attachments.first { $0.mimeType == "image/png" }
        #expect(img != nil)
        #expect(img?.contentID == "logo@acme")
    }

    @Test func partWithNoContentIDStaysNil() {
        let raw = """
        Content-Type: multipart/mixed; boundary="b"\r
        \r
        --b\r
        Content-Type: text/plain; charset=utf-8\r
        \r
        hello\r
        --b\r
        Content-Type: application/pdf\r
        Content-Transfer-Encoding: base64\r
        Content-Disposition: attachment; filename="doc.pdf"\r
        \r
        JVBERi0=\r
        --b--\r
        """
        let parsed = MIME.parse(Data(raw.utf8))
        let pdf = parsed.attachments.first { $0.filename == "doc.pdf" }
        #expect(pdf != nil)
        #expect(pdf?.contentID == nil)
    }

    // MARK: - B5 second-pass filter: filterInlineCID (T006)

    private func att(_ filename: String, _ mime: String, cid: String?, bytes: [UInt8] = [0x00]) -> MIME.Attachment {
        MIME.Attachment(filename: filename, mimeType: mime, data: Data(bytes), contentID: cid)
    }

    @Test func filterDropsReferencedCIDPartAndCapturesItsBytes() {
        let html = "<img src=\"cid:logo@acme\">"
        let logo = att("logo.png", "image/png", cid: "logo@acme", bytes: [0x89, 0x50])
        let result = ReaderHTML.filterInlineCID(html: html, attachments: [logo])
        #expect(result.survivingAttachments.isEmpty)
        #expect(result.inlineParts["logo@acme"] == InlinePart(mimeType: "image/png", data: Data([0x89, 0x50])))
    }

    @Test func filterKeepsUnreferencedCIDPartAsAttachment() {
        let html = "<p>no inline image here</p>"
        let orphan = att("orphan.png", "image/png", cid: "orphan@acme")
        let result = ReaderHTML.filterInlineCID(html: html, attachments: [orphan])
        #expect(result.survivingAttachments.count == 1)
        #expect(result.survivingAttachments.first?.filename == "orphan.png")
        #expect(result.inlineParts.isEmpty)
    }

    @Test func filterKeepsNoContentIDPart() {
        let html = "<img src=\"cid:logo@acme\">"
        let doc = att("doc.pdf", "application/pdf", cid: nil)
        let result = ReaderHTML.filterInlineCID(html: html, attachments: [doc])
        #expect(result.survivingAttachments.count == 1)
        #expect(result.inlineParts.isEmpty)
    }

    @Test func filterMixedKeepsAndDropsCorrectly() {
        let html = "<img src=\"cid:sig@acme\"> and <p>text</p>"
        let sig = att("sig.png", "image/png", cid: "sig@acme")        // referenced → dropped
        let orphan = att("orphan.gif", "image/gif", cid: "orphan@acme") // unreferenced CID → kept
        let doc = att("doc.pdf", "application/pdf", cid: nil)          // no CID → kept
        let result = ReaderHTML.filterInlineCID(html: html, attachments: [sig, orphan, doc])
        #expect(Set(result.survivingAttachments.map { $0.filename }) == ["orphan.gif", "doc.pdf"])
        #expect(result.inlineParts.keys.sorted() == ["sig@acme"])
    }

    @Test func filterWithNilHTMLKeepsAllAttachments() {
        let a = att("a.png", "image/png", cid: "a@x")
        let result = ReaderHTML.filterInlineCID(html: nil, attachments: [a])
        #expect(result.survivingAttachments.count == 1)
        #expect(result.inlineParts.isEmpty)
    }

    @Test func messageWithNoCIDPartParsesIdentically() {
        // A plain multipart/alternative (text + HTML, no related images) yields the
        // same text/html/attachments/calendar/unsubscribe as before the feature.
        let raw = """
        Content-Type: multipart/alternative; boundary="b"\r
        \r
        --b\r
        Content-Type: text/plain; charset=utf-8\r
        \r
        plain body\r
        --b\r
        Content-Type: text/html; charset=utf-8\r
        \r
        <p>html body</p>\r
        --b--\r
        """
        let parsed = MIME.parse(Data(raw.utf8))
        #expect(parsed.text == "plain body")
        #expect(parsed.html == "<p>html body</p>")
        #expect(parsed.attachments.isEmpty)
        #expect(parsed.calendar == nil)
        #expect(parsed.listUnsubscribe == nil)
    }
}
