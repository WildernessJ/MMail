import Testing
import Foundation
@testable import MMail

/// Robustness property tests for the MIME helpers.
@Suite struct MIMEProperties {

    /// decodeHeader passes through any input with no `=?` substring anywhere
    /// (the fast path returns it unmodified, surrounding whitespace included).
    @Test func decodeHeaderPassthroughWhenNoEncodedWord() {
        check("decodeHeader passthrough", Gen<String>.noEncodedWord) { s in
            MIME.decodeHeader(s) == s
        }
    }

    /// decodeHeader never crashes on arbitrary input, including malformed
    /// encoded-word structure and random bytes-as-text. (Crash-freedom: the
    /// property merely returns a string; a trap aborts the process.)
    @Test func decodeHeaderNeverCrashes() {
        check("decodeHeader crash-freedom", Gen<String>.arbitrary) { s in
            _ = MIME.decodeHeader(s)
            return true
        }
    }

    /// parse never crashes on arbitrary bytes (random, truncated MIME, empty).
    @Test func parseNeverCrashes() {
        check("MIME.parse crash-freedom", Gen<Data>.arbitrary) { d in
            _ = MIME.parse(d)
            return true
        }
    }

    /// extractText never crashes on arbitrary bytes.
    @Test func extractTextNeverCrashes() {
        check("MIME.extractText crash-freedom", Gen<Data>.arbitrary) { d in
            _ = MIME.extractText(from: d)
            return true
        }
    }

    /// Regression: quoted-printable CRLF soft line breaks (`=\r\n`) MUST be
    /// stripped when decoding a body. Swift treats "\r\n" as a single Character,
    /// so the prior char-based decoder never matched `=`+`\r`+`\n` and left soft
    /// breaks in — splitting `src` URLs across lines and breaking image rendering
    /// (and the image proxy). The byte-based decoder rejoins them.
    @Test func quotedPrintableDecodesCRLFSoftBreaks() {
        let raw =
            "Content-Type: text/html; charset=utf-8\r\n" +
            "Content-Transfer-Encoding: quoted-printable\r\n" +
            "\r\n" +
            "<img src=3D\"https://x.test/a=\r\nb.gif?x=3D1\">\r\n"
        let html = MIME.parse(Data(raw.utf8)).html ?? ""
        // `=3D` → `=`, and the `=\r\n` soft break is removed (rejoining a…b).
        #expect(html.contains("<img src=\"https://x.test/ab.gif?x=1\">"))
        #expect(!html.contains("=\r\n"))
        #expect(!html.contains("=3D"))
    }
}
