import Testing
import Foundation
@testable import MMail

/// Unit tests for `ProxyConfigState`: the PURE classifier that maps
/// `(proxyEnabled, proxyBaseURL, secretPresent)` to one of six states. Everything is
/// exercised with injected `Bool`/`String` values and NO AppModel / WebKit / Keychain /
/// filesystem access, proving purity (SC-002). Asserted here: the six-state
/// representatives (SC-003), the URL-wins-over-secret short-circuit precedence, the
/// SC-004 equivalence matrix (`classify == .ok` ⇔ a pure transcription of the guard
/// conditions; `isWarning` ⇔ `proxyEnabled && imageProxyConfig == nil`'s logical shape),
/// and totality / exactly-one. SC-001 (on-screen Settings warning + live-Keychain
/// agreement) is the manual exploration step, not assertable by this target.
@Suite struct ProxyConfigStateTests {

    // Reusable valid base URL (parses, host present).
    private static let validHostURL = "https://worker.example.workers.dev"

    // MARK: - Six-state representatives (SC-003)

    @Test func toggleOffIsDisabledRegardlessOfOtherInputs() {
        #expect(ProxyConfigState.classify(
            proxyEnabled: false, proxyBaseURL: "anything", secretPresent: true) == .disabled)
        // Don't-care inputs: disabled holds with blank URL / no secret too.
        #expect(ProxyConfigState.classify(
            proxyEnabled: false, proxyBaseURL: "", secretPresent: false) == .disabled)
        #expect(ProxyConfigState.classify(
            proxyEnabled: false, proxyBaseURL: Self.validHostURL, secretPresent: false) == .disabled)
    }

    @Test func enabledValidURLAndSecretIsOk() {
        #expect(ProxyConfigState.classify(
            proxyEnabled: true, proxyBaseURL: Self.validHostURL, secretPresent: true) == .ok)
    }

    @Test func enabledBlankURLIsMissingURL() {
        #expect(ProxyConfigState.classify(
            proxyEnabled: true, proxyBaseURL: "", secretPresent: true) == .missingURL)
        // Whitespace-only trims to empty → still missingURL.
        #expect(ProxyConfigState.classify(
            proxyEnabled: true, proxyBaseURL: "   ", secretPresent: true) == .missingURL)
    }

    @Test func enabledUnparseableURLIsInvalidURL() {
        // Sanity precondition: this exact string makes URL(string:) return nil in this
        // project's Foundation (unescaped space in the authority). Bind to a LOCAL so
        // the precondition and the classifier reason about the same single evaluation.
        let raw = "https://foo bar.com"
        let parsed = URL(string: raw)
        #expect(parsed == nil)
        #expect(ProxyConfigState.classify(
            proxyEnabled: true, proxyBaseURL: raw, secretPresent: true) == .invalidURL)
    }

    @Test func enabledParseableHostlessURLIsUrlMissingHost() {
        // "not a url" parses under URL(string:) (the spaces percent-encode) but host == nil.
        let raw = "not a url"
        let parsed = URL(string: raw)
        #expect(parsed != nil)
        #expect(parsed?.host == nil)
        #expect(ProxyConfigState.classify(
            proxyEnabled: true, proxyBaseURL: raw, secretPresent: true) == .urlMissingHost)
    }

    @Test func enabledValidURLButNoSecretIsMissingSecret() {
        #expect(ProxyConfigState.classify(
            proxyEnabled: true, proxyBaseURL: Self.validHostURL, secretPresent: false) == .missingSecret)
    }

    // MARK: - Short-circuit precedence: URL wins over secret (SC-003 central edge case)

    @Test func blankURLAndNoSecretReportsMissingURLNotMissingSecret() {
        // Mirrors imageProxyConfig short-circuiting on the URL before the secret guard
        // (AppModel.swift:936-938): the user fixes the URL — the first blocker — first.
        #expect(ProxyConfigState.classify(
            proxyEnabled: true, proxyBaseURL: "", secretPresent: false) == .missingURL)
    }

    // MARK: - Blank-but-present secret treated as missing (spec scenario, line 94)

    @Test func enabledValidURLWithResolvedMissingSecretIsMissingSecret() {
        // The blank-secret → secretPresent == false resolution is ProxySecretStore.resolve's
        // job at the call site (exercised in ProxySecretStoreTests). Here we only assert the
        // classifier honors the injected `false`.
        #expect(ProxyConfigState.classify(
            proxyEnabled: true, proxyBaseURL: Self.validHostURL, secretPresent: false) == .missingSecret)
    }

    // MARK: - SC-004: pure equivalence to the guard-condition transcription (anti-drift)

    /// Representative input matrix: cross proxyEnabled × proxyBaseURL × secretPresent.
    /// 2 × 5 × 2 = 20 rows.
    private static let baseURLs = ["", "   ", "https://foo bar.com", "not a url", validHostURL]

    @Test func classifyOkMatchesPureGuardTranscriptionAcrossMatrix() {
        for proxyEnabled in [false, true] {
            for proxyBaseURL in Self.baseURLs {
                for secretPresent in [false, true] {
                    // PURE transcription of imageProxyConfig's guard CONDITIONS over the
                    // same injected inputs. URL(string:) evaluated ONCE (bound to a local).
                    let trimmed = proxyBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
                    let parsed = URL(string: trimmed)
                    let okRef = proxyEnabled
                        && !trimmed.isEmpty
                        && parsed != nil
                        && parsed?.host != nil            // host != nil (NOT !host.isEmpty) — matches AppModel.swift:937
                        && secretPresent

                    let state = ProxyConfigState.classify(
                        proxyEnabled: proxyEnabled,
                        proxyBaseURL: proxyBaseURL,
                        secretPresent: secretPresent)

                    #expect((state == .ok) == okRef,
                            "(\(proxyEnabled), \"\(proxyBaseURL)\", \(secretPresent)) -> state \(state); okRef \(okRef)")
                    // isWarning ⇔ proxyEnabled && !okRef ⇔ proxyEnabled && imageProxyConfig == nil.
                    #expect(state.isWarning == (proxyEnabled && !okRef),
                            "(\(proxyEnabled), \"\(proxyBaseURL)\", \(secretPresent)) -> isWarning \(state.isWarning); expected \(proxyEnabled && !okRef)")
                }
            }
        }
    }

    // MARK: - Totality / exactly-one (spec Invariant "Exactly one state")

    @Test func classifyIsTotalAndExactlyOneOfSix() {
        let allCases: Set<ProxyConfigState> = [
            .disabled, .ok, .missingURL, .invalidURL, .urlMissingHost, .missingSecret
        ]
        for proxyEnabled in [false, true] {
            for proxyBaseURL in Self.baseURLs {
                for secretPresent in [false, true] {
                    let state = ProxyConfigState.classify(
                        proxyEnabled: proxyEnabled,
                        proxyBaseURL: proxyBaseURL,
                        secretPresent: secretPresent)
                    #expect(allCases.contains(state),
                            "(\(proxyEnabled), \"\(proxyBaseURL)\", \(secretPresent)) -> \(state) must be one of the six states")
                }
            }
        }
    }
}
