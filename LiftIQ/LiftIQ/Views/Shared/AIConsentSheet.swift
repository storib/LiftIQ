import SwiftUI

struct AIConsentSheet: View {
    let onAccept: () -> Void
    let onDecline: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    VStack(spacing: 12) {
                        Image(systemName: "brain.head.profile.fill")
                            .font(.system(size: 44))
                            .foregroundStyle(Color.accentColor)

                        Text("AI-Powered Workout Plans")
                            .font(.title2.bold())
                            .multilineTextAlignment(.center)

                        Text("We send some of your training info to Anthropic (Claude) to generate your plan. It isn't used to train their models.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 8)

                    ConsentSection(
                        title: "Shared",
                        tint: .secondary,
                        items: [
                            "Goals, experience, and equipment",
                            "Training schedule and session length",
                            "Injuries and exercise history"
                        ]
                    )

                    ConsentSection(
                        title: "Not shared",
                        tint: Color.liftSuccess,
                        items: [
                            "Name, email, or account info",
                            "Body measurements or weight"
                        ]
                    )

                    Text("You can withdraw consent anytime in Profile.")
                        .font(.footnote)
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, alignment: .center)

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
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .frame(maxWidth: .infinity)
            }
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

private struct ConsentSection: View {
    let title: String
    let tint: Color
    let items: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased())
                .font(.caption.weight(.semibold))
                .foregroundStyle(tint)
                .tracking(0.5)

            VStack(alignment: .leading, spacing: 6) {
                ForEach(items, id: \.self) { item in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text("•")
                            .foregroundStyle(.secondary)
                        Text(item)
                            .font(.subheadline)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
