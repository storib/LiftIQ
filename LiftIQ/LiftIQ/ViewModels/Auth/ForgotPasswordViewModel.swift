import SwiftUI

@MainActor
@Observable
final class ForgotPasswordViewModel {
    var email = ""
    var isLoading = false
    var errorMessage: String?
    /// True once at least one reset request succeeded.
    var linkSent = false
    /// The email a reset was actually requested for — the success card must
    /// show this, not the live field, which the user can edit afterwards.
    var lastRequestedEmail: String?
    var resendCooldownRemaining = 0

    private var cooldownTask: Task<Void, Never>?

    var trimmedEmail: String {
        email.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var isEmailValid: Bool {
        EmailValidator.isPlausible(trimmedEmail)
    }

    var canSubmit: Bool {
        isEmailValid && !isLoading && resendCooldownRemaining == 0
    }

    func sendResetLink(authService: AuthService) async {
        guard canSubmit else { return }
        isLoading = true
        errorMessage = nil
        do {
            try await authService.resetPassword(email: trimmedEmail)
            linkSent = true
            lastRequestedEmail = trimmedEmail
            startResendCooldown()
        } catch {
            errorMessage = AuthErrorMapper.friendlyMessage(for: error, flow: .resetPassword)
        }
        isLoading = false
    }

    /// Wall-clock based so backgrounding the app can't stretch the cooldown.
    private func startResendCooldown(seconds: TimeInterval = 30) {
        cooldownTask?.cancel()
        let endDate = Date().addingTimeInterval(seconds)
        resendCooldownRemaining = Int(seconds)
        cooldownTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let remaining = Int(endDate.timeIntervalSinceNow.rounded(.up))
                self.resendCooldownRemaining = max(0, remaining)
                if remaining <= 0 { return }
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }
}
