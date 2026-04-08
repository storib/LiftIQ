import SwiftUI

struct WelcomeView: View {
    var body: some View {
        NavigationStack {
            VStack(spacing: 32) {
                Spacer()

                VStack(spacing: 8) {
                    Text("LiftIQ")
                        .font(.system(size: 48, weight: .bold, design: .rounded))
                    Text("Train Smarter. Lift Stronger.")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 20) {
                    FeatureRow(icon: "brain.head.profile", title: "AI-Powered Programs", description: "Personalized workout plans tailored to your goals")
                    FeatureRow(icon: "chart.line.uptrend.xyaxis", title: "Track Progress", description: "See your strength gains with detailed analytics")
                    FeatureRow(icon: "arrow.up.right.circle", title: "Smart Progression", description: "Automatic weight and rep suggestions each session")
                }
                .padding(.horizontal)

                Spacer()

                VStack(spacing: 12) {
                    NavigationLink {
                        SignUpView()
                    } label: {
                        Text("Get Started")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.accentColor)
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }

                    NavigationLink {
                        SignInView()
                    } label: {
                        Text("Already have an account? **Sign In**")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 32)
            }
        }
    }
}

struct FeatureRow: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(Color.accentColor)
                .frame(width: 44, height: 44)
                .background(Color.accentColor.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

#Preview {
    WelcomeView()
}
