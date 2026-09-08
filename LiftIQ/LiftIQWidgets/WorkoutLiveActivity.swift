import ActivityKit
import SwiftUI
import WidgetKit

/// Lock Screen banner and Dynamic Island for an in-progress workout: the
/// current exercise and set, a rest countdown while resting, and overall
/// set progress. Timers use `timerInterval` so they count without updates.
struct WorkoutLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: WorkoutActivityAttributes.self) { context in
            LockScreenView(context: context)
                .activityBackgroundTint(Color(.systemBackground).opacity(0.85))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(context.state.exerciseName)
                            .font(.headline)
                            .lineLimit(1)
                        Text(context.state.setLabel)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if let range = context.state.restRange() {
                        RestRing(range: range, size: 44)
                    } else if context.state.isResting {
                        Text("Rest done")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.accentColor)
                            .padding(.trailing, 4)
                    } else {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("\(context.state.completedSets)/\(context.state.totalSets)")
                                .font(.headline.monospacedDigit())
                            Text("sets")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.trailing, 4)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        if let next = context.state.nextUpLabel {
                            Text(next)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer()
                        Text(timerInterval: context.attributes.startedAt...context.attributes.startedAt.addingTimeInterval(12 * 3600), countsDown: false)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: 70, alignment: .trailing)
                    }
                    .padding(.horizontal, 4)
                }
            } compactLeading: {
                Image(systemName: "dumbbell.fill")
                    .foregroundStyle(Color.accentColor)
            } compactTrailing: {
                if let range = context.state.restRange() {
                    Text(timerInterval: range, countsDown: true)
                        .font(.caption.monospacedDigit())
                        .frame(maxWidth: 44)
                } else if context.state.isResting {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.accentColor)
                } else {
                    Text("\(context.state.completedSets)/\(context.state.totalSets)")
                        .font(.caption.monospacedDigit())
                }
            } minimal: {
                if let range = context.state.restRange() {
                    ProgressView(timerInterval: range, countsDown: true, label: { EmptyView() }, currentValueLabel: { EmptyView() })
                        .progressViewStyle(.circular)
                        .tint(Color.accentColor)
                } else {
                    Image(systemName: "dumbbell.fill")
                        .foregroundStyle(Color.accentColor)
                }
            }
        }
    }
}

private struct LockScreenView: View {
    let context: ActivityViewContext<WorkoutActivityAttributes>

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(context.attributes.workoutName, systemImage: "dumbbell.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                Text(timerInterval: context.attributes.startedAt...context.attributes.startedAt.addingTimeInterval(12 * 3600), countsDown: false)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: 70, alignment: .trailing)
            }

            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(context.state.exerciseName)
                        .font(.headline)
                        .lineLimit(1)
                    Text(context.state.setLabel)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    if let next = context.state.nextUpLabel {
                        Text(next)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                if let range = context.state.restRange() {
                    VStack(spacing: 2) {
                        RestRing(range: range, size: 52)
                        Text("rest")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                } else if context.state.isResting {
                    // Rest ran out while the app was suspended; the next set is up.
                    VStack(spacing: 2) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title2)
                            .foregroundStyle(Color.accentColor)
                        Text("rest done")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            HStack(spacing: 8) {
                ProgressView(value: Double(context.state.completedSets), total: Double(max(1, context.state.totalSets)))
                    .tint(Color.accentColor)
                Text("\(context.state.completedSets) of \(context.state.totalSets) sets")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .fixedSize()
            }
        }
        .padding(14)
    }
}

/// Circular countdown that runs on its own via `timerInterval`. The range
/// comes from `ContentState.restRange`, which is never inverted.
private struct RestRing: View {
    let range: ClosedRange<Date>
    let size: CGFloat

    var body: some View {
        ZStack {
            ProgressView(timerInterval: range, countsDown: true, label: { EmptyView() }, currentValueLabel: { EmptyView() })
                .progressViewStyle(.circular)
                .tint(Color.accentColor)
            Text(timerInterval: range, countsDown: true)
                .font(.system(size: size * 0.26, weight: .semibold, design: .rounded).monospacedDigit())
                .multilineTextAlignment(.center)
                .frame(width: size * 0.9)
        }
        .frame(width: size, height: size)
    }
}
