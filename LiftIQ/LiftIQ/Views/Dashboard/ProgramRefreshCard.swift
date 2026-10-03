import SwiftUI

/// The opt-in "switch it up" checkpoint, shown once a lifter's chosen number
/// of weeks on one program has passed. Same three ways forward as the block
/// review, and the same principle: it never changes the plan by itself, and
/// it never claims the program stopped working — it says how long it has been
/// running and what the logs show.
struct ProgramRefreshCard: View {
    let refresh: ProgramRefresh
    let plan: WorkoutPlan
    let onKeepGoing: () -> Void
    let onPlanModified: (WorkoutPlan) -> Void
    /// Beta signal for the two non-committing taps ("tweak" opens, "new" navigates).
    var onAction: ((String) -> Void)? = nil

    @State private var showingModify = false

    private var suggestedInstruction: String {
        "I've been running this program for \(refresh.weeksOnProgram) weeks and want a change. "
            + "Keep the structure and the days per week, but swap in some new exercises "
            + "and vary the rep ranges so it feels fresh."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                    .font(.title2)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(refresh.weeksOnProgram) weeks on this program")
                        .font(.system(.headline, design: .rounded))
                    Text(summaryLine)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            Text(bodyCopy)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Button(action: onKeepGoing) {
                Text("Keep going")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color.accentColor)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }

            HStack(spacing: 12) {
                Button {
                    onAction?("tweak-open")
                    showingModify = true
                } label: {
                    Label("Switch it up with AI", systemImage: "wand.and.stars")
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
        .padding(16)
        .background(
            LinearGradient(
                colors: [Color.accentColor.opacity(0.14), Color.accentColor.opacity(0.05)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(Color.accentColor.opacity(0.25), lineWidth: 1)
        )
        .padding(.horizontal)
        .sheet(isPresented: $showingModify) {
            AIModifySheet(
                plan: plan,
                workout: nil,
                onApplyPlan: onPlanModified,
                initialInstruction: suggestedInstruction
            )
        }
    }

    private var summaryLine: String {
        var parts = ["\(refresh.sessionsOnProgram) sessions"]
        if refresh.holdingLifts > 0 {
            // A description of the logs, not a verdict: these lifts have been
            // held at the same top weight, which is worth a look.
            parts.append(refresh.holdingLifts == 1
                         ? "1 lift holding steady"
                         : "\(refresh.holdingLifts) lifts holding steady")
        }
        return parts.joined(separator: " \u{2022} ")
    }

    private var bodyCopy: String {
        if refresh.holdingLifts > 0 {
            return "You asked to be checked in with every \(refresh.cadenceWeeks) weeks. "
                + "A few lifts have been sitting at the same top weight, which is often a good moment "
                + "for new exercises — but if the program still feels right, keep going."
        }
        return "You asked to be checked in with every \(refresh.cadenceWeeks) weeks. "
            + "New exercises can be a good change of pace, but a program that's still working is "
            + "worth keeping — it's your call."
    }
}
