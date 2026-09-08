import SwiftUI

/// Dashboard card for the weekly AI check-in. Consent is handled the same
/// way as AIModifySheet: personal training data goes to Claude only after
/// the user has agreed to the current consent version.
struct WeeklyCheckInCard: View {
    @Environment(AppDependencies.self) private var dependencies
    @Bindable var viewModel: WeeklyCheckInViewModel

    @State private var showingConsent = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "calendar.badge.checkmark")
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Weekly check-in")
                        .font(.headline)
                    Text(weekLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    viewModel.dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Dismiss weekly check-in")
            }

            switch viewModel.state {
            case .ready:
                Text("A short read on last week from Claude: what went well, and one thing to try next week.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                generateButton(title: "Review my week")

            case .loading:
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Reading last week…")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 44)

            case .result(let insights):
                resultBody(insights)

            case .failed(let message):
                Text(message)
                    .font(.caption)
                    .foregroundStyle(Color.liftDanger)
                generateButton(title: "Try again")

            case .hidden:
                EmptyView()
            }
        }
        .padding(16)
        .background(Color.liftCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal)
        .sheet(isPresented: $showingConsent) {
            AIConsentSheet(
                onAccept: {
                    showingConsent = false
                    Task { await viewModel.generate(aiService: dependencies.aiService) }
                },
                onDecline: { showingConsent = false }
            )
            .interactiveDismissDisabled()
        }
    }

    private func generateButton(title: String) -> some View {
        Button {
            if AIConsentManager.hasConsented {
                Task { await viewModel.generate(aiService: dependencies.aiService) }
            } else {
                showingConsent = true
            }
        } label: {
            Label(title, systemImage: "wand.and.stars")
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(Color.accentColor.opacity(0.1))
                .foregroundStyle(Color.accentColor)
                .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }

    private func resultBody(_ insights: WeeklyInsights) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(ratingLabel(insights.overallRating), systemImage: ratingIcon(insights.overallRating))
                .font(.caption.weight(.semibold))
                .foregroundStyle(ratingTint(insights.overallRating))
            ForEach(Array(insights.insights.enumerated()), id: \.offset) { _, line in
                HStack(alignment: .top, spacing: 8) {
                    Text("\u{2022}")
                    Text(line)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .font(.subheadline)
            }
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "arrow.right.circle.fill")
                    .foregroundStyle(Color.accentColor)
                Text("Next week: \(insights.actionItem)")
                    .font(.subheadline.weight(.medium))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 2)
        }
    }

    private var weekLabel: String {
        let start = viewModel.reviewWeekStart
        let end = Calendar.current.date(byAdding: .day, value: 6, to: start) ?? start
        return "\(start.formatted(.dateTime.month(.abbreviated).day())) – \(end.formatted(.dateTime.month(.abbreviated).day()))"
    }

    private func ratingLabel(_ rating: WeeklyInsights.Rating) -> String {
        switch rating {
        case .great: return "Great week"
        case .good: return "Good week"
        case .needsAttention: return "Worth a look"
        }
    }

    private func ratingIcon(_ rating: WeeklyInsights.Rating) -> String {
        switch rating {
        case .great: return "star.fill"
        case .good: return "checkmark.circle.fill"
        case .needsAttention: return "exclamationmark.circle.fill"
        }
    }

    private func ratingTint(_ rating: WeeklyInsights.Rating) -> Color {
        switch rating {
        case .great: return Color.liftSuccess
        case .good: return Color.accentColor
        case .needsAttention: return Color.liftWarning
        }
    }
}
