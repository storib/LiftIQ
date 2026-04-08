import SwiftUI

struct SignUpView: View {
    @Environment(AppDependencies.self) private var dependencies
    @State private var viewModel = SignUpViewModel()

    var body: some View {
        VStack(spacing: 24) {
            VStack(spacing: 8) {
                Text("Create Account")
                    .font(.largeTitle.bold())
                Text("Start your training journey")
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 40)

            VStack(spacing: 16) {
                TextField("Display Name", text: $viewModel.displayName)
                    .textContentType(.name)
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                TextField("Email", text: $viewModel.email)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .autocapitalization(.none)
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                SecureField("Password", text: $viewModel.password)
                    .textContentType(.newPassword)
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                SecureField("Confirm Password", text: $viewModel.confirmPassword)
                    .textContentType(.newPassword)
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                if viewModel.passwordMismatch {
                    Text("Passwords don't match")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            if let error = viewModel.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }

            Button {
                Task { await viewModel.signUp(authService: dependencies.authService) }
            } label: {
                Group {
                    if viewModel.isLoading {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Text("Create Account")
                    }
                }
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding()
                .background(viewModel.isFormValid ? Color.accentColor : Color.gray.opacity(0.3))
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .disabled(!viewModel.isFormValid || viewModel.isLoading)

            Spacer()
        }
        .padding(.horizontal, 24)
        .navigationBarTitleDisplayMode(.inline)
    }
}
