import SwiftUI

struct AIConsentSheet: View {
    let onAccept: () -> Void
    let onDecline: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Header
                    VStack(spacing: 12) {
                        Image(systemName: "brain.head.profile.fill")
                            .font(.system(size: 44))
                            .foregroundStyle(Color.accentColor)

                        Text("AI-Powered Workout Plans")
                            .font(.title2.bold())
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 8)

                    Text("LiftIQ uses a third-party AI service to generate personalized workout programs. Before continuing, please review what data is shared and how it is used.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    // What data is shared
                    GroupBox {
                        VStack(alignment: .leading, spacing: 10) {
                            Label("Data Shared with AI", systemImage: "arrow.up.doc.fill")
                                .font(.subheadline.weight(.semibold))

                            BulletPoint("Experience level and training goals")
                            BulletPoint("Available equipment")
                            BulletPoint("Training schedule (days per week, session length)")
                            BulletPoint("Injury information (body part, severity, notes)")
                            BulletPoint("Exercise performance history (for plateau analysis)")
                        }
                    }

                    // Where it goes
                    GroupBox {
                        VStack(alignment: .leading, spacing: 10) {
                            Label("AI Processor", systemImage: "server.rack")
                                .font(.subheadline.weight(.semibold))

                            Text("Your data is sent to **Anthropic** (Claude AI) via our secure backend servers. Anthropic processes the data to generate your workout plan and does not use it for model training.")
                                .font(.caption)
                        }
                    }

                    // What is NOT shared
                    GroupBox {
                        VStack(alignment: .leading, spacing: 10) {
                            Label("What Is Not Shared", systemImage: "lock.shield.fill")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Color.liftSuccess)

                            BulletPoint("Your email address or account credentials")
                            BulletPoint("Your name or personal identifiers")
                            BulletPoint("Body measurements or weight")
                        }
                    }

                    Text("You can withdraw consent at any time from your Profile settings. Without AI consent, you can still use manually created workout programs.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)

                    // Buttons
                    VStack(spacing: 12) {
                        Button {
                            AIConsentManager.recordConsent()
                            onAccept()
                        } label: {
                            Text("I Agree")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(Color.accentColor)
                                .foregroundStyle(.white)
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                        }

                        Button {
                            onDecline()
                        } label: {
                            Text("Not Now")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.top, 4)
                }
                .padding()
            }
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

private struct BulletPoint: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text("\u{2022}")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(text)
                .font(.caption)
        }
    }
}
