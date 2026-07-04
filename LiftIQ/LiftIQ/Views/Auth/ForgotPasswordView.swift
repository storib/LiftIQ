import SwiftUI

struct ForgotPasswordView: View {
    @Environment(AppDependencies.self) private var dependencies
    @State private var viewModel = ForgotPasswordViewModel()
    @FocusState private var emailFocused: Bool

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                header

                TextField("Email", text: $viewModel.email)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.send)
                    .focused($emailFocused)
                    .onSubmit { send() }
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                if let error = viewModel.errorMessage {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(Color.liftDanger)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if viewModel.linkSent {
                    successCard
                }

                sendButton

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 24)
        }
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { emailFocused = true }
    }

    private var header: some View {
        VStack(spacing: 12) {
            Image(systemName: "lock.rotation")
                .font(.system(size: 44))
                .foregroundStyle(Color.accentColor)
                .frame(width: 80, height: 80)
                .background(Color.accentColor.opacity(0.1))
                .clipShape(Circle())

            Text("Reset Password")
                .font(.largeTitle.bold())
            Text("Enter the email you signed up with and we'll send you a reset link.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 32)
    }

    private var successCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Reset link requested", systemImage: "envelope.badge.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.liftSuccess)

            Text("If an account exists for **\(viewModel.lastRequestedEmail ?? viewModel.trimmedEmail)**, a reset link is on its way. It can take a few minutes to arrive.")
                .font(.subheadline)

            VStack(alignment: .leading, spacing: 6) {
                tipRow("Check your spam or junk folder — the sender is *noreply@* your app's Firebase domain.")
                tipRow("Make sure this is the exact email you signed up with. For security, we can't reveal whether an account exists.")
                tipRow("The link expires after a short time; request a new one if it stopped working.")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func tipRow(_ text: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "circle.fill")
                .font(.system(size: 4))
                .padding(.top, 5)
            Text(text)
        }
    }

    private var sendButton: some View {
        Button {
            send()
        } label: {
            Group {
                if viewModel.isLoading {
                    ProgressView()
                        .tint(.white)
                } else if viewModel.resendCooldownRemaining > 0 {
                    Text("Resend in \(viewModel.resendCooldownRemaining)s")
                } else {
                    Text(viewModel.linkSent ? "Resend Link" : "Send Reset Link")
                }
            }
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding()
            .background(viewModel.canSubmit ? Color.accentColor : Color.gray.opacity(0.3))
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .disabled(!viewModel.canSubmit)
        .accessibilityHint("Sends a password reset link to the entered email")
    }

    private func send() {
        guard viewModel.canSubmit else { return }
        emailFocused = false
        Task { await viewModel.sendResetLink(authService: dependencies.authService) }
    }
}
