import Foundation

/// The configuration health of the image privacy proxy, classified down to the
/// single sub-condition the user must fix. A read-only, display-only classification
/// derived PURELY from injected inputs — it can never disagree with
/// `AppModel.imageProxyConfig` about whether the proxy is inert, because
/// `imageProxyConfig` DERIVES its `nil`-vs-non-`nil` decision from
/// `classify(...) == .ok` (`AppModel.swift`), making this the single source of truth.
///
/// Input contract:
/// - `proxyEnabled` — `model.proxyEnabled` (the toggle).
/// - `proxyBaseURL` — the raw, user-typed `model.proxyBaseURL` string (untrimmed).
/// - `secretPresent == (loadProxySecret() != nil)` — the ONE impure step (Keychain +
///   fallback file I/O) is resolved at the call site (`AppModel.swift:906`), NOT here.
///   `loadProxySecret()` already returns nil for a blank/whitespace-only secret
///   (`ProxySecretStore.resolve`, `ProxySecretStore.swift:22-30`), so `secretPresent`
///   already encodes the `!secret.isEmpty` guard.
///
/// `.ok ⇔ all of imageProxyConfig's guards pass` (`AppModel.swift:934-938`). The
/// sub-condition order MUST mirror the guard short-circuit: `proxyEnabled` → blank URL
/// → unparseable URL → host-less URL → secret. This single-source-of-truth role is
/// load-bearing: there is exactly ONE copy of the validity logic (here), so the
/// Settings warning and the actual image-load path cannot silently diverge.
///
/// `Foundation` only (`URL`, string trimming) — no AppModel / WebKit / Keychain /
/// filesystem access (purity).
enum ProxyConfigState: Equatable {
    /// `proxyEnabled == false`. Direct loading is the user's explicit choice. No warning.
    case disabled
    /// All guards pass; the proxy is functional (`imageProxyConfig != nil`). No warning.
    case ok
    /// Enabled, but the base URL trims to empty (fails `!trimmed.isEmpty`).
    case missingURL
    /// Enabled, base URL non-empty but `URL(string:)` returns nil (unparseable).
    case invalidURL
    /// Enabled, URL parses but `url.host == nil` (bare path / scheme-only string).
    case urlMissingHost
    /// Enabled, URL chain fully passes, but the signing secret is absent
    /// (`secretPresent == false`).
    case missingSecret

    /// The single "show the warning?" predicate consumed by the Settings view.
    /// `isWarning == (self ∈ {missingURL, invalidURL, urlMissingHost, missingSecret})`.
    var isWarning: Bool {
        switch self {
        case .disabled, .ok: return false
        default: return true
        }
    }

    /// Pure: map `(proxyEnabled, proxyBaseURL, secretPresent)` to exactly one state,
    /// decomposing the `imageProxyConfig` guard chain (`AppModel.swift:934-938`) in the
    /// SAME short-circuit order, evaluating `URL(string:)` exactly ONCE. No I/O.
    static func classify(proxyEnabled: Bool, proxyBaseURL: String, secretPresent: Bool) -> ProxyConfigState {
        guard proxyEnabled else { return .disabled }
        let trimmed = proxyBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .missingURL }
        guard let url = URL(string: trimmed) else { return .invalidURL }
        guard url.host != nil else { return .urlMissingHost }   // host != nil, NOT !host.isEmpty (mirror AppModel.swift:937)
        guard secretPresent else { return .missingSecret }
        return .ok
    }
}
