import SwiftUI

@Observable
final class SignInViewModel {
    var email = ""
    var password = ""
    var isLoading = false
    var errorMessage: String?

    var isFormValid: Bool {
        !email.trimmingCharacters(in: .whitespaces).isEmpty && password.count >= 6
    }

    func signIn(authService: AuthService) async {
        isLoading = true
        errorMessage = nil
        do {
            try await authService.signIn(email: email.trimmingCharacters(in: .whitespaces), password: password)
        } catch {
            errorMessage = Self.friendlyAuthError(error)
        }
        isLoading = false
    }

    static func friendlyAuthError(_ error: Error) -> String {
        let nsError = error as NSError
        guard nsError.domain == "FIRAuthErrorDomain" else {
            return error.localizedDescription
        }
        switch nsError.code {
        case 17009: // wrongPassword
            return "Incorrect password. Please try again."
        case 17011: // userNotFound
            return "No account found with this email."
        case 17008: // invalidEmail
            return "Please enter a valid email address."
        case 17010: // userDisabled
            return "This account has been disabled."
        case 17020: // networkError
            return "Network error. Check your connection and try again."
        case 17006: // operationNotAllowed
            return "Email/Password sign-in is not enabled. Enable it in the Firebase Console under Authentication → Sign-in method."
        default:
            return "Sign-in failed (code \(nsError.code)): \(error.localizedDescription)"
        }
    }
}
