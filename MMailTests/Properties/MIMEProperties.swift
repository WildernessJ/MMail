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
}
