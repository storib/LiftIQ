import SwiftUI

enum PasswordStrength {
    case weak
    case fair
    case strong

    var label: String {
        switch self {
        case .weak: return "Weak"
        case .fair: return "Fair"
        case .strong: return "Strong"
        }
    }

    var color: Color {
        switch self {
        case .weak: return Color.liftDanger
        case .fair: return Color.liftWarning
        case .strong: return Color.liftSuccess
        }
    }

    var fraction: Double {
        switch self {
        case .weak: return 1.0 / 3.0
        case .fair: return 2.0 / 3.0
        case .strong: return 1.0
        }
    }

    /// Length-first scoring: 6+ chars is Firebase's floor, longer passwords
    /// and mixed character classes upgrade the rating.
    static func evaluate(_ password: String) -> PasswordStrength {
        guard password.count >= 6 else { return .weak }
        var classes = 0
        if password.rangeOfCharacter(from: .lowercaseLetters) != nil { classes += 1 }
        if password.rangeOfCharacter(from: .uppercaseLetters) != nil { classes += 1 }
        if password.rangeOfCharacter(from: .decimalDigits) != nil { classes += 1 }
        if password.rangeOfCharacter(from: .alphanumerics.inverted) != nil { classes += 1 }

        if password.count >= 12 && classes >= 3 { return .strong }
        if password.count >= 8 && classes >= 2 { return .fair }
        return password.count >= 10 ? .fair : .weak
    }
}

@MainActor
@Observable
final class SignUpViewModel {
    var displayName = ""
    var email = ""
    var password = ""
    var confirmPassword = ""
    var isLoading = false
    var errorMessage: String?

    var trimmedEmail: String {
        email.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var isNameValid: Bool {
        !displayName.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var isEmailValid: Bool {
        EmailValidator.isPlausible(trimmedEmail)
    }

    var isPasswordLongEnough: Bool {
        password.count >= 6
    }

    var passwordsMatch: Bool {
        !password.isEmpty && password == confirmPassword
    }

    var passwordMismatch: Bool {
        !confirmPassword.isEmpty && password != confirmPassword
    }

    var passwordStrength: PasswordStrength {
        PasswordStrength.evaluate(password)
    }

    var isFormValid: Bool {
        isNameValid && isEmailValid && isPasswordLongEnough && passwordsMatch
    }

    func signUp(authService: AuthService) async {
        guard isFormValid, !isLoading else { return }
        isLoading = true
        errorMessage = nil
        do {
            try await authService.signUp(
                email: trimmedEmail,
                password: password,
                displayName: displayName.trimmingCharacters(in: .whitespaces)
            )
        } catch {
            errorMessage = AuthErrorMapper.friendlyMessage(for: error, flow: .signUp)
        }
        isLoading = false
    }
}
