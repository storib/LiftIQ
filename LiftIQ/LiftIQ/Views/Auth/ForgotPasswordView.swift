import SwiftUI

struct ForgotPasswordView: View {
    @Environment(AppDependencies.self) private var dependencies
    @State private var email = ""
    @State private var isLoading = false
    @State private var showSuccess = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 24) {
            VStack(spacing: 8) {
                Text("Reset Password")
                    .font(.largeTitle.bold())
                Text("Enter your email to receive a reset link")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 40)

            TextField("Email", text: $email)
                .textContentType(.emailAddress)
                .keyboardType(.emailAddress)
                .autocapitalization(.none)
                .padding()
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))

            if let error = errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            if showSuccess {
                Label("Reset link sent! Check your email.", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.subheadline)
            }

            Button {
                Task {
                    isLoading = true
                    errorMessage = nil
                    do {
                        try await dependencies.authService.resetPassword(email: email.trimmingCharacters(in: .whitespaces))
                        showSuccess = true
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                    isLoading = false
                }
            } label: {
                Group {
                    if isLoading {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Text("Send Reset Link")
                    }
                }
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding()
                .background(!email.isEmpty ? Color.accentColor : Color.gray.opacity(0.3))
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .disabled(email.isEmpty || isLoading)

            Spacer()
        }
        .padding(.horizontal, 24)
        .navigationBarTitleDisplayMode(.inline)
    }
}
