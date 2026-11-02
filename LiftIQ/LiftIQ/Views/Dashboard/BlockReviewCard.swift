import SwiftUI

/// Shown once the active plan's block is complete. Celebrates the block and
/// offers three ways forward; it never changes the plan on its own — a
/// program that is working should be kept, and that's the lifter's call.
struct BlockReviewCard: View {
    let review: BlockReview
    let plan: WorkoutPlan
    let onKeepGoing: () -> Void
    let onPlanModified: (WorkoutPlan) -> Void
    /// Beta signal for the two non-committing taps ("tweak" opens, "new" navigates).
    var onAction: ((String) -> Void)? = nil

    @State private var showingModify = false

    private var suggestedInstruction: String {
        "Progress this plan into a new \(plan.weekCount)-week block: keep the exercises that are working, "
            + "add a little volume or one new variation per day, and keep the same number of days per week."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "flag.checkered.circle.fill")
                    .font(.title2)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Color.liftPR)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Block \(review.blockNumber) complete")
                        .font(.system(.headline, design: .rounded))
                    Text(summaryLine)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            Text("Keep going with the same program, tweak it with AI, or start something new. If it's working, there's no need to change it.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Button("Keep going", action: onKeepGoing)
                .buttonStyle(.liftTinted)

            HStack(spacing: 12) {
                Button {
                    onAction?("tweak-open")
                    showingModify = true
                } label: {
                    Label("Tweak with AI", systemImage: "wand.and.stars")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                NavigationLink {
                    TemplateBrowserView()
                        .onAppear { onAction?("new") }
                } label: {
                    Label("New program", systemImage: "plus.circle")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
            }
        }
        .liftCard()
        .padding(.horizontal)
        .sheet(isPresented: $showingModify) {
            AIModifySheet(
                plan: plan,
                workout: nil,
                source: .blockReview,
                onApplyPlan: onPlanModified,
                initialInstruction: suggestedInstruction
            )
        }
    }

    private var summaryLine: String {
        var parts = ["\(review.weeks) weeks", "\(review.sessions) sessions"]
        if let strength = review.strengthChangePercent {
            let sign = strength >= 0 ? "+" : ""
            parts.append("strength \(sign)\(strength.formatted(decimals: 0))%")
        }
        if review.prCount > 0 {
            parts.append(review.prCount == 1 ? "1 PR" : "\(review.prCount) PRs")
        }
        return parts.joined(separator: " \u{2022} ")
    }
}
