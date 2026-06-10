import Testing
import Foundation
@testable import MMail

/// Unit tests for `ReaderImageLoadState`: the PURE classifier seams — the `bodyHTML`
/// `<img src`/`srcset>` remote-ref scan (`hasRemoteImages`) and the 3-boolean →
/// 4-state `classify` mapping. Everything is exercised with injected `String?` / `Bool`
/// values and NO AppModel / WebKit / Keychain access, proving purity (SC-002). The
/// full 8-row truth table (SC-003), exactly-one/totality (SC-004), and the
/// Load-images transition (SC-005) are asserted here; SC-001 (on-screen indicator) is
/// the manual exploration step, not assertable by this target.
@Suite struct ReaderImageLoadStateTests {

    // MARK: - hasRemoteImages: No remote images (SC-002)

    @Test func noBodyHasNoRemoteImages() {
        #expect(ReaderImageLoadState.hasRemoteImages(in: nil) == false)
        #expect(ReaderImageLoadState.hasRemoteImages(in: "") == false)
    }

    @Test func plainHtmlWithNoImgHasNoRemoteImages() {
        #expect(ReaderImageLoadState.hasRemoteImages(in: "<p>hi</p>") == false)
    }

    @Test func nonHttpSchemesAreNotRemote() {
        // cid:, data:, and root-relative refs are NOT remote http(s) fetches.
        #expect(ReaderImageLoadState.hasRemoteImages(in: "<img src=\"cid:logo\">") == false)
        #expect(ReaderImageLoadState.hasRemoteImages(in: "<img src=\"data:image/png;base64,AAA\">") == false)
        #expect(ReaderImageLoadState.hasRemoteImages(in: "<img src=\"/local.png\">") == false)
    }

    // MARK: - hasRemoteImages: remote `src` (SC-002)

    @Test func remoteHttpsSrcIsRemote() {
        #expect(ReaderImageLoadState.hasRemoteImages(in: "<img src=\"https://t/x.gif\">") == true)
    }

    @Test func remoteHttpSingleQuotedSrcIsRemote() {
        #expect(ReaderImageLoadState.hasRemoteImages(in: "<img src='http://t/x'>") == true)
    }

    @Test func caseInsensitiveTagAndAttrNameStillDetectsRemoteSrc() {
        // HTML tag/attribute NAMES are case-insensitive; the quoted VALUE stays as-is.
        #expect(ReaderImageLoadState.hasRemoteImages(in: "<IMG SRC=\"https://t/x\">") == true)
    }

    // MARK: - hasRemoteImages: privacy-critical `srcset` (SC-002)

    @Test func srcsetOnlyRemoteIsRemote() {
        // A srcset-only image with no `src` STILL fetches remotely in direct mode;
        // classifying it as "No remote images" would be a privacy-dangerous false neg.
        #expect(ReaderImageLoadState.hasRemoteImages(in: "<img srcset=\"https://tracker/x.gif\">") == true)
    }

    @Test func srcsetSingleQuotedWithDescriptorIsRemote() {
        #expect(ReaderImageLoadState.hasRemoteImages(in: "<img srcset='http://t/x 2x'>") == true)
    }

    // MARK: - classify: the full 8-row truth table (SC-003, SC-004)

    /// Every `(hasRemoteImages, showImages, proxyActive)` tuple in `{false,true}^3`,
    /// paired with the SC-003 expected state.
    private static let truthTable: [(hasRemote: Bool, showImages: Bool, proxyActive: Bool, expected: ReaderImageLoadState)] = [
        (false, false, false, .noRemoteImages),
        (false, false, true,  .noRemoteImages),
        (false, true,  false, .noRemoteImages),
        (false, true,  true,  .noRemoteImages),
        (true,  false, false, .blocked),
        (true,  false, true,  .blocked),
        (true,  true,  true,  .proxied),
        (true,  true,  false, .loadedDirect),
    ]

    @Test func classifyMatchesFullTruthTable() {
        for row in Self.truthTable {
            let state = ReaderImageLoadState.classify(
                hasRemoteImages: row.hasRemote,
                showImages: row.showImages,
                proxyActive: row.proxyActive
            )
            #expect(state == row.expected,
                    "(\(row.hasRemote), \(row.showImages), \(row.proxyActive)) -> expected \(row.expected), got \(state)")
        }
    }

    /// Exactly-one / totality (SC-004): every tuple yields a single state that is one
    /// of the four known cases (the enum makes "two states" unrepresentable, so
    /// totality + membership is the assertable half).
    @Test func classifyIsTotalAndExactlyOneOfFour() {
        let allCases: Set<ReaderImageLoadState> = [.noRemoteImages, .blocked, .proxied, .loadedDirect]
        for hasRemote in [false, true] {
            for showImages in [false, true] {
                for proxyActive in [false, true] {
                    let state = ReaderImageLoadState.classify(
                        hasRemoteImages: hasRemote, showImages: showImages, proxyActive: proxyActive)
                    #expect(allCases.contains(state),
                            "(\(hasRemote), \(showImages), \(proxyActive)) -> \(state) must be one of the four states")
                }
            }
        }
    }

    // MARK: - Load-images transition (SC-005)

    @Test func loadImagesTransitionsBlockedToProxiedWithProxy() {
        // Hold hasRemoteImages = true, proxyActive = true; flip showImages false->true.
        let before = ReaderImageLoadState.classify(hasRemoteImages: true, showImages: false, proxyActive: true)
        let after = ReaderImageLoadState.classify(hasRemoteImages: true, showImages: true, proxyActive: true)
        #expect(before == .blocked)
        #expect(after == .proxied)
    }

    @Test func loadImagesTransitionsBlockedToDirectWithoutProxy() {
        let before = ReaderImageLoadState.classify(hasRemoteImages: true, showImages: false, proxyActive: false)
        let after = ReaderImageLoadState.classify(hasRemoteImages: true, showImages: true, proxyActive: false)
        #expect(before == .blocked)
        #expect(after == .loadedDirect)
    }
}
