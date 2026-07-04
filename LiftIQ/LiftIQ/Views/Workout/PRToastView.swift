import SwiftUI
import UIKit

/// Non-blocking top banner celebrating a new personal record. Tap to dismiss;
/// auto-dismisses after ~4 seconds. Unlike a modal overlay, it never blocks
/// input to the workout underneath.
struct PRToastView: View {
    let personalRecord: PersonalRecord
    let unitSystem: UnitSystem
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "trophy.fill")
                .font(.title2)
                .foregroundStyle(Color.liftPR)

            VStack(alignment: .leading, spacing: 2) {
                Text("New PR!")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Color.liftPR)

                Text("\(personalRecord.exerciseName) \u{2022} \(prDescription)")
                    .font(.caption)
                    .foregroundStyle(.primary)

                if let previous = personalRecord.previousValue {
                    let improvement = personalRecord.value - previous
                    Text("+\(improvement.formatted()) \(prUnit)")
                        .font(.caption2)
                        .foregroundStyle(Color.liftSuccess)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.liftCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .shadow(color: Color.black.opacity(0.2), radius: 10, y: 4)
        .contentShape(RoundedRectangle(cornerRadius: 14))
        .onTapGesture { onDismiss() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityAnnouncement)
        .accessibilityHint("Double tap to dismiss")
        .accessibilityAddTraits(.isButton)
        .onAppear {
            UIAccessibility.post(notification: .announcement, argument: accessibilityAnnouncement)
        }
        .task {
            try? await Task.sleep(for: .seconds(4))
            onDismiss()
        }
    }

    private var accessibilityAnnouncement: String {
        "New personal record: \(personalRecord.exerciseName), \(prDescription)"
    }

    private var prDescription: String {
        switch personalRecord.type {
        case .weight:
            return personalRecord.value.asWeight(unit: unitSystem)
        case .estimated1RM:
            return "Est. 1RM: \(personalRecord.value.asWeight(unit: unitSystem))"
        case .reps:
            return "\(Int(personalRecord.value)) reps"
        case .volume:
            return "\(personalRecord.value.asWeight(unit: unitSystem)) volume"
        }
    }

    private var prUnit: String {
        switch personalRecord.type {
        case .weight, .estimated1RM, .volume:
            return UnitConversionService.weightLabel(for: unitSystem)
        case .reps:
            return "reps"
        }
    }
}
