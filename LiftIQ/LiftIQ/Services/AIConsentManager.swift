import Foundation

enum AIConsentManager {
    private static let consentKey = "liftiq_ai_consent_granted"
    private static let consentVersionKey = "liftiq_ai_consent_version"

    /// Current consent version. Bump this when the data sharing scope changes
    /// to re-prompt users who previously consented under an older version.
    /// v2: AI workout modification also shares the current plan contents and
    /// the user's free-text modification request.
    static let currentConsentVersion = 2

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
