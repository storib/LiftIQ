import SwiftUI

@Observable
final class SignUpViewModel {
    var displayName = ""
    var email = ""
    var password = ""
    var confirmPassword = ""
    var isLoading = false
    var errorMessage: String?

    var isFormValid: Bool {
        !displayName.trimmingCharacters(in: .whitespaces).isEmpty &&
        !email.trimmingCharacters(in: .whitespaces).isEmpty &&
        password.count >= 6 &&
        password == confirmPassword
    }

    var passwordMismatch: Bool {
        !confirmPassword.isEmpty && password != confirmPassword
    }

    func signUp(authService: AuthService) async {
        isLoading = true
        errorMessage = nil
        do {
            try await authService.signUp(
                email: email.trimmingCharacters(in: .whitespaces),
                password: password,
                displayName: displayName.trimmingCharacters(in: .whitespaces)
            )
        } catch {
            errorMessage = Self.friendlyAuthError(error)
        }
        isLoading = false
    }

    static func friendlyAuthError(_ error: Error) -> String {
        let nsError = error as NSError
        // Firebase Auth errors use domain "FIRAuthErrorDomain"
        guard nsError.domain == "FIRAuthErrorDomain" else {
            return error.localizedDescription
        }
        switch nsError.code {
        case 17007: // emailAlreadyInUse
            return "An account with this email already exists."
        case 17008: // invalidEmail
            return "Please enter a valid email address."
        case 17026: // weakPassword
            return "Password is too weak. Use at least 6 characters."
        case 17006: // operationNotAllowed
            return "Email/Password sign-up is not enabled. Enable it in the Firebase Console under Authentication → Sign-in method."
        case 17020: // networkError
            return "Network error. Check your connection and try again."
        default:
            return "Sign-up failed (code \(nsError.code)): \(error.localizedDescription)"
        }
    }
}
