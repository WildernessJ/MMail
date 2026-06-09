import Testing
import Foundation
@testable import MMail

/// Unit tests for the image privacy proxy's pure seams: the CryptoKit signer
/// (asserted against the pinned cross-language HMAC vector shared with the
/// Worker), the HTML `<img src>` rewriter, and the Keychain secret storage.
@Suite struct ImageProxyTests {
    // Scaffolding only in T008 — assertions are added in T009/T011/T015.
}
