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
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}
