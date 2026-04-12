import Foundation

enum AIConsentManager {
    private static let consentKey = "liftiq_ai_consent_granted"
    private static let consentVersionKey = "liftiq_ai_consent_version"

    /// Current consent version. Bump this when the data sharing scope changes
    /// to re-prompt users who previously consented under an older version.
    static let currentConsentVersion = 1

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
