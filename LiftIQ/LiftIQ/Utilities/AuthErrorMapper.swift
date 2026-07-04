import Foundation
import FirebaseAuth

/// Shared Firebase Auth error → user-facing message mapping for the sign-in
/// and sign-up flows, keyed on `AuthErrorCode` instead of magic NSError ints.
enum AuthErrorMapper {
    enum Flow {
        case signIn
        case signUp
        case resetPassword

        var label: String {
            switch self {
            case .signIn: return "Sign-in"
            case .signUp: return "Sign-up"
            case .resetPassword: return "Password reset"
            }
        }
    }

    static func friendlyMessage(for error: Error, flow: Flow) -> String {
        let nsError = error as NSError
        guard nsError.domain == AuthErrorDomain,
              let code = AuthErrorCode(rawValue: nsError.code) else {
            return error.localizedDescription
        }

        switch code {
        case .wrongPassword:
            return "Incorrect password. Please try again."
        case .invalidCredential:
            // Firebase returns this generic code for wrong email/password
            // combinations when email enumeration protection is enabled.
            return "Incorrect email or password. Please try again."
        case .userNotFound:
            return "No account found with this email."
        case .invalidEmail:
            return "Please enter a valid email address."
        case .userDisabled:
            return "This account has been disabled."
        case .emailAlreadyInUse:
            return "An account with this email already exists."
        case .weakPassword:
            return "Password is too weak. Use at least 6 characters."
        case .networkError:
            return "Network error. Check your connection and try again."
        case .tooManyRequests:
            return "Too many attempts. Please wait a few minutes and try again."
        case .invalidRecipientEmail, .missingEmail:
            return "Please enter a valid email address."
        case .operationNotAllowed:
            return "Email/Password authentication is not enabled. Enable it in the Firebase Console under Authentication \u{2192} Sign-in method."
        default:
            return "\(flow.label) failed (code \(nsError.code)): \(error.localizedDescription)"
        }
    }
}
