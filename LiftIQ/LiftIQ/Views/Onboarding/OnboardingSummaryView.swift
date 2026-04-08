import SwiftUI

struct OnboardingSummaryView: View {
    @Bindable var viewModel: OnboardingViewModel

    var body: some View {
        VStack(spacing: 24) {
            Text("Your Profile")
                .font(.title2.bold())
            Text("Review your selections")
                .foregroundStyle(.secondary)

            ScrollView {
                VStack(spacing: 16) {
                    SummaryRow(title: "Experience", value: viewModel.experienceLevel.displayName)
                    SummaryRow(title: "Goals", value: viewModel.selectedGoals.map { $0.displayName }.joined(separator: ", "))
                    SummaryRow(title: "Equipment", value: viewModel.selectedEquipment.map { $0.displayName }.joined(separator: ", "))
                    SummaryRow(title: "Training Days", value: "\(viewModel.trainingDaysPerWeek) days/week")
                    SummaryRow(title: "Session Length", value: "\(viewModel.sessionDurationMinutes) minutes")

                    if !viewModel.injuries.isEmpty {
                        SummaryRow(title: "Injuries", value: viewModel.injuries.map { "\($0.bodyPart) (\($0.severity))" }.joined(separator: ", "))
                    }

                    if !viewModel.bodyWeight.isEmpty {
                        let unit = viewModel.unitSystem == .metric ? "kg" : "lb"
                        SummaryRow(title: "Body Weight", value: "\(viewModel.bodyWeight) \(unit)")
                    }

                    if !viewModel.height.isEmpty {
                        let unit = viewModel.unitSystem == .metric ? "cm" : "in"
                        SummaryRow(title: "Height", value: "\(viewModel.height) \(unit)")
                    }
                }
                .padding(.horizontal)
            }

            if let error = viewModel.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .padding(.top, 32)
    }
}

struct SummaryRow: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
