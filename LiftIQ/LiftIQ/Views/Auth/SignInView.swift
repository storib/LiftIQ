import SwiftUI

struct SignInView: View {
    @Environment(AppDependencies.self) private var dependencies
    @State private var viewModel = SignInViewModel()

    var body: some View {
        VStack(spacing: 24) {
            VStack(spacing: 8) {
                Text("Welcome Back")
                    .font(.largeTitle.bold())
                Text("Sign in to continue your training")
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 40)

            VStack(spacing: 16) {
                TextField("Email", text: $viewModel.email)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .autocapitalization(.none)
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                SecureField("Password", text: $viewModel.password)
                    .textContentType(.password)
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }

            if let error = viewModel.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }

            Button {
                Task { await viewModel.signIn(authService: dependencies.authService) }
            } label: {
                Group {
                    if viewModel.isLoading {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Text("Sign In")
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

            NavigationLink {
                ForgotPasswordView()
            } label: {
                Text("Forgot Password?")
                    .font(.subheadline)
                    .foregroundStyle(Color.accentColor)
            }

            Spacer()
        }
        .padding(.horizontal, 24)
        .navigationBarTitleDisplayMode(.inline)
    }
}
