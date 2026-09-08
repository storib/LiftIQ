import Foundation

enum AIConsentManager {
    private static let consentKey = "liftiq_ai_consent_granted"
    private static let consentVersionKey = "liftiq_ai_consent_version"

    /// Current consent version. Bump this when the data sharing scope changes
    /// to re-prompt users who previously consented under an older version.
    /// v2: AI workout modification also shares the current plan contents and
    /// the user's free-text modification request.
    /// v3: the weekly check-in shares two weeks of session summaries —
    /// session counts, volume, best sets per lift, and difficulty ratings.
    /// v4: adapting a workout to another gym may share the names of
    /// exercises you've marked as avoided, so the AI can skip them.
    static let currentConsentVersion = 4

    static var hasConsented: Bool {
        UserDefaults.standard.bool(forKey: consentKey)
            && UserDefaults.standard.integer(forKey: consentVersionKey) >= currentConsentVersion
    }

    static func recordConsent() {
        UserDefaults.standard.set(true, forKey: consentKey)
        UserDefaults.standard.set(currentConsentVersion, forKey: consentVersionKey)
    }

    static func revokeConsent() {
        UserDefaults.standard.removeObject(forKey: consentKey)
        UserDefaults.standard.removeObject(forKey: consentVersionKey)
    }
}
