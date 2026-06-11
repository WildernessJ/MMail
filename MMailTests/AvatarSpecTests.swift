import Testing
import Foundation
@testable import MMail

/// Pure-seam coverage for the account-editing feature: `AvatarSpec.resolve`
/// (initials/color/usesImage), `AvatarImage.squareCropRect` (centered crop), and
/// the additive-Codable round-trip on `MailAccountConfig`'s two new optional fields.
@Suite struct AvatarSpecTests {

    // MARK: - AvatarSpec.resolve

    @Test func unCustomizedConfigPreservesTodaysLook() {
        let spec = AvatarSpec.resolve(displayName: "Jane Doe", email: "jane@x.org",
                                      customColorHex: nil, hasImage: false)
        #expect(spec.initials == "J")
        #expect(spec.gradientHex == [Sender.stableColorHex(for: "jane@x.org"), "1E2DB0"])
        #expect(spec.usesImage == false)
    }

    @Test func customColorYieldsSolidFill() {
        let spec = AvatarSpec.resolve(displayName: "Jane Doe", email: "jane@x.org",
                                      customColorHex: "E5484D", hasImage: false)
        #expect(spec.gradientHex == ["E5484D", "E5484D"])
        #expect(spec.initials == "J")
    }

    @Test func emptyNameFallsBackToEmail() {
        let spec = AvatarSpec.resolve(displayName: "   ", email: "jane@x.org",
                                      customColorHex: nil, hasImage: false)
        #expect(spec.initials == "J")
    }

    @Test func imageFlagOverridesRenderButColorStillResolved() {
        let spec = AvatarSpec.resolve(displayName: "Jane Doe", email: "jane@x.org",
                                      customColorHex: "E5484D", hasImage: true)
        #expect(spec.usesImage == true)
        #expect(spec.gradientHex == ["E5484D", "E5484D"])
    }

    // MARK: - AllInboxSpec.resolve

    @Test func allInboxNamedUsesShortTextAndFullLabel() {
        let spec = AllInboxSpec.resolve(name: "Everything", hasImage: false)
        #expect(spec.tileText == "Eve")
        #expect(spec.label == "Everything")
        #expect(spec.usesImage == false)
    }

    @Test func allInboxBlankNameFallsBackToDefaults() {
        let spec = AllInboxSpec.resolve(name: "   ", hasImage: false)
        #expect(spec.tileText == "All")
        #expect(spec.label == "All inboxes")
    }

    @Test func allInboxImageFlagPassesThroughWithText() {
        let spec = AllInboxSpec.resolve(name: "Hi", hasImage: true)
        #expect(spec.tileText == "Hi")
        #expect(spec.label == "Hi")
        #expect(spec.usesImage == true)
    }

    // MARK: - AvatarImage.squareCropRect

    @Test func squareCropOfWideImage() {
        #expect(AvatarImage.squareCropRect(sourceWidth: 800, sourceHeight: 400)
                == CGRect(x: 200, y: 0, width: 400, height: 400))
    }

    @Test func squareCropOfTallImage() {
        #expect(AvatarImage.squareCropRect(sourceWidth: 300, sourceHeight: 900)
                == CGRect(x: 0, y: 300, width: 300, height: 300))
    }

    @Test func squareCropOfAlreadySquareImage() {
        #expect(AvatarImage.squareCropRect(sourceWidth: 500, sourceHeight: 500)
                == CGRect(x: 0, y: 0, width: 500, height: 500))
    }

    // MARK: - Additive Codable

    /// A full pre-feature `MailAccountConfig` blob: every original field present,
    /// NEITHER `avatarColorHex` NOR `hasCustomAvatar`.
    private let preFeatureJSON = """
    {
        "id": "real-abc",
        "displayName": "Jane Doe",
        "email": "jane@x.org",
        "imapHost": "imap.example.org",
        "imapPort": 993,
        "imapSecurity": "tls",
        "imapUsername": "jane",
        "smtpHost": "smtp.example.org",
        "smtpPort": 587,
        "smtpSecurity": "startTLS",
        "smtpUsername": "jane"
    }
    """

    @Test func preFeatureConfigDecodesWithBothFieldsNil() throws {
        let cfg = try JSONDecoder().decode(MailAccountConfig.self,
                                           from: Data(preFeatureJSON.utf8))
        #expect(cfg.avatarColorHex == nil)
        #expect(cfg.hasCustomAvatar == nil)
    }

    @Test func customizedConfigRoundTrips() throws {
        var cfg = try JSONDecoder().decode(MailAccountConfig.self,
                                           from: Data(preFeatureJSON.utf8))
        cfg.avatarColorHex = "1FB36B"
        cfg.hasCustomAvatar = true
        let data = try JSONEncoder().encode(cfg)
        let decoded = try JSONDecoder().decode(MailAccountConfig.self, from: data)
        #expect(decoded.avatarColorHex == "1FB36B")
        #expect(decoded.hasCustomAvatar == true)
    }

    // MARK: - uiAccount end-to-end (SC-005 value-preservation)

    /// A decoded pre-feature config must produce a derived `Account` identical to
    /// the pre-refactor derivation: initials from the name, gradient/colorHex from
    /// the email hash, and no image. Guards the whole `uiAccount` path, not just
    /// the `AvatarSpec` seam in isolation.
    @Test func uiAccountPreservesTodaysDerivationForUnCustomizedConfig() throws {
        let cfg = try JSONDecoder().decode(MailAccountConfig.self,
                                           from: Data(preFeatureJSON.utf8))
        let account = AppModel.uiAccount(for: cfg)
        let base = Sender.stableColorHex(for: "jane@x.org")
        #expect(account.name == "Jane Doe")
        #expect(account.initials == "J")
        #expect(account.colorHex == base)
        #expect(account.gradient == [base, "1E2DB0"])
    }

    /// A whitespace-only displayName resolves initials from the email (trim-then-
    /// empty-check). This is an intentional, spec-compliant divergence from the
    /// old `.isEmpty`-only check, which would have yielded a blank initial.
    @Test func uiAccountWhitespaceNameFallsBackToEmailInitial() throws {
        var cfg = try JSONDecoder().decode(MailAccountConfig.self,
                                           from: Data(preFeatureJSON.utf8))
        cfg.displayName = "   "
        #expect(AppModel.uiAccount(for: cfg).initials == "J")
    }
}
