import SwiftUI

struct SignUpView: View {
    @Environment(AppDependencies.self) private var dependencies
    @State private var viewModel = SignUpViewModel()
    @FocusState private var focusedField: Field?

    private enum Field: Hashable {
        case name, email, password, confirmPassword
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                header
                fields

                if let error = viewModel.errorMessage {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(Color.liftDanger)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                createButton

                Text("Next up: a one-minute profile so we can tailor your first program.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 24)
        }
        .navigationBarTitleDisplayMode(.inline)
    }

    private var header: some View {
        VStack(spacing: 8) {
            Text("Create Account")
                .font(.largeTitle.bold())
            Text("Start your training journey")
                .foregroundStyle(.secondary)
        }
        .padding(.top, 24)
    }

    private var fields: some View {
        VStack(spacing: 16) {
            TextField("Display Name", text: $viewModel.displayName)
                .textContentType(.name)
                .submitLabel(.next)
                .focused($focusedField, equals: .name)
                .onSubmit { focusedField = .email }
                .authFieldStyle()

            TextField("Email", text: $viewModel.email)
                .textContentType(.emailAddress)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.next)
                .focused($focusedField, equals: .email)
                .onSubmit { focusedField = .password }
                .authFieldStyle()

            if !viewModel.email.isEmpty && !viewModel.isEmailValid && focusedField != .email {
                inlineHint("That doesn't look like a valid email address.", ok: false)
            }

            RevealableSecureField(
                "Password",
                text: $viewModel.password,
                contentType: .newPassword
            )
            .submitLabel(.next)
            .focused($focusedField, equals: .password)
            .onSubmit { focusedField = .confirmPassword }

            if !viewModel.password.isEmpty {
                strengthMeter
            }

            RevealableSecureField(
                "Confirm Password",
                text: $viewModel.confirmPassword,
                contentType: .newPassword
            )
            .submitLabel(.join)
            .focused($focusedField, equals: .confirmPassword)
            .onSubmit { submit() }

            if !viewModel.password.isEmpty || !viewModel.confirmPassword.isEmpty {
                requirementChecklist
            }
        }
    }

    private var strengthMeter: some View {
        HStack(spacing: 12) {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.gray.opacity(0.2))
                    Capsule()
                        .fill(viewModel.passwordStrength.color)
                        .frame(width: proxy.size.width * viewModel.passwordStrength.fraction)
                        .animation(.easeOut(duration: 0.2), value: viewModel.passwordStrength.fraction)
                }
            }
            .frame(height: 6)

            Text(viewModel.passwordStrength.label)
                .font(.caption.weight(.medium))
                .foregroundStyle(viewModel.passwordStrength.color)
                .frame(width: 50, alignment: .trailing)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Password strength: \(viewModel.passwordStrength.label)")
    }

    private var requirementChecklist: some View {
        VStack(alignment: .leading, spacing: 6) {
            inlineHint("At least 6 characters", ok: viewModel.isPasswordLongEnough)
            inlineHint("Passwords match", ok: viewModel.passwordsMatch)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func inlineHint(_ text: String, ok: Bool) -> some View {
        Label(text, systemImage: ok ? "checkmark.circle.fill" : "circle")
            .font(.caption)
            .foregroundStyle(ok ? Color.liftSuccess : Color.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var createButton: some View {
        Button {
            submit()
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
    }

    private func submit() {
        guard viewModel.isFormValid, !viewModel.isLoading else { return }
        focusedField = nil
        Task { await viewModel.signUp(authService: dependencies.authService) }
    }
}

/// SecureField with an eye toggle. Revealing swaps in a TextField, which
/// drops keyboard focus — acceptable for a deliberate visibility check.
struct RevealableSecureField: View {
    private let title: String
    @Binding private var text: String
    private let contentType: UITextContentType
    @State private var isRevealed = false

    init(_ title: String, text: Binding<String>, contentType: UITextContentType) {
        self.title = title
        self._text = text
        self.contentType = contentType
    }

    var body: some View {
        HStack {
            Group {
                if isRevealed {
                    TextField(title, text: $text)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } else {
                    SecureField(title, text: $text)
                }
            }
            .textContentType(contentType)

            Button {
                isRevealed.toggle()
            } label: {
                Image(systemName: isRevealed ? "eye.slash" : "eye")
                    .foregroundStyle(.secondary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isRevealed ? "Hide password" : "Show password")
        }
        .padding(.leading)
        .padding(.vertical, 4)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

private extension View {
    func authFieldStyle() -> some View {
        self
            .padding()
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
