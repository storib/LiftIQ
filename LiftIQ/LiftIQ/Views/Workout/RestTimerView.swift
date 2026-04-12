import SwiftUI

struct RestTimerView: View {
    let secondsRemaining: Int
    let totalSeconds: Int
    let onSkip: () -> Void
    let onAdjust: (Int) -> Void

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Spacer()
                Text("Rest Timer")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
            }

            ZStack {
                // Background ring
                Circle()
                    .stroke(Color.secondary.opacity(0.2), lineWidth: 8)

                // Progress ring
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 1), value: progress)

                // Timer text
                Text(Formatters.timerString(from: secondsRemaining))
                    .font(.system(size: 36, weight: .bold, design: .monospaced))
                    .contentTransition(.numericText())
            }
            .frame(width: 120, height: 120)

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
        .shadow(color: .black.opacity(0.15), radius: 20, y: 10)
        .padding(.horizontal, 40)
    }

    private var progress: Double {
        guard totalSeconds > 0 else { return 0 }
        return Double(secondsRemaining) / Double(totalSeconds)
    }
}
