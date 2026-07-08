import SwiftUI

struct RestTimerView: View {
    let secondsRemaining: Int
    let totalSeconds: Int
    @Binding var isMinimized: Bool
    let onSkip: () -> Void
    let onAdjust: (Int) -> Void

    var body: some View {
        Group {
            if isMinimized {
                minimizedPill
            } else {
                expandedCard
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: isMinimized)
    }

    // MARK: - Expanded card

    private var expandedCard: some View {
        VStack(spacing: 16) {
            HStack {
                Spacer()
                Text("Rest Timer")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .overlay(alignment: .trailing) {
                Button {
                    isMinimized = true
                } label: {
                    Image(systemName: "chevron.down.circle.fill")
                        .font(.title3)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.secondary)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Minimize rest timer")
            }

            ZStack {
                // Background ring
                Circle()
                    .stroke(Color.secondary.opacity(0.15), lineWidth: 10)

                // Progress ring with a subtle accent gradient along the sweep
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(
                        AngularGradient(
                            colors: [Color.accentColor.opacity(0.55), Color.accentColor],
                            center: .center,
                            startAngle: .degrees(0),
                            endAngle: .degrees(360)
                        ),
                        style: StrokeStyle(lineWidth: 10, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 1), value: progress)

                // Timer text
                Text(Formatters.timerString(from: secondsRemaining))
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }
            .frame(width: 128, height: 128)

            // Adjust buttons
            HStack(spacing: 24) {
                Button {
                    onAdjust(-15)
                } label: {
                    Text("-15s")
                        .font(.subheadline.weight(.medium))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color(.tertiarySystemBackground))
                        .clipShape(Capsule())
                }

                Button {
                    onAdjust(15)
                } label: {
                    Text("+15s")
                        .font(.subheadline.weight(.medium))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color(.tertiarySystemBackground))
                        .clipShape(Capsule())
                }
            }

            Button {
                onSkip()
            } label: {
                Text("Skip")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
            }
        }
        .padding(24)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .shadow(color: .black.opacity(0.1), radius: 24, y: 8)
        .padding(.horizontal, 40)
    }

    // MARK: - Minimized pill

    private var minimizedPill: some View {
        HStack(spacing: 12) {
            Button {
                isMinimized = false
            } label: {
                HStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .stroke(Color.secondary.opacity(0.15), lineWidth: 4)
                        Circle()
                            .trim(from: 0, to: progress)
                            .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                            .animation(.linear(duration: 1), value: progress)
                    }
                    .frame(width: 26, height: 26)

                    Text(Formatters.timerString(from: secondsRemaining))
                        .font(.headline.monospacedDigit())
                        .contentTransition(.numericText())

                    Image(systemName: "chevron.up")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Rest timer, \(Formatters.timerString(from: secondsRemaining)) remaining")
            .accessibilityHint("Expands the rest timer")

            Spacer()

            Button {
                onAdjust(15)
            } label: {
                Text("+15s")
                    .font(.subheadline.weight(.medium))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color(.tertiarySystemBackground))
                    .clipShape(Capsule())
            }

            Button {
                onSkip()
            } label: {
                Text("Skip")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 4)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
        .shadow(color: .black.opacity(0.1), radius: 16, y: 6)
        .padding(.horizontal, 20)
    }

    private var progress: Double {
        guard totalSeconds > 0 else { return 0 }
        return Double(secondsRemaining) / Double(totalSeconds)
    }
}
