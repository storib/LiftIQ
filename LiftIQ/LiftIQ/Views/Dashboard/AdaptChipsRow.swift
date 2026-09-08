import SwiftUI

/// Three one-tap ways to fit today's workout to today.
struct AdaptChipsRow: View {
    let lastMinutes: Int
    let onPick: (WorkoutAdaptationKind) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip("I have \(lastMinutes) min", icon: "clock.badge.checkmark", kind: .shortOnTime)
                chip("Equipment is busy", icon: "arrow.triangle.2.circlepath", kind: .equipmentBusy)
                chip("Somewhere else", icon: "mappin.and.ellipse", kind: .differentGym)
            }
        }
        .accessibilityLabel("Adapt today's workout")
    }

    private func chip(_ title: String, icon: String, kind: WorkoutAdaptationKind) -> some View {
        Button {
            onPick(kind)
        } label: {
            Label(title, systemImage: icon)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .padding(.horizontal, 12)
                .frame(minHeight: 36)
                .background(Color.accentColor.opacity(0.1))
                .foregroundStyle(Color.accentColor)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}
