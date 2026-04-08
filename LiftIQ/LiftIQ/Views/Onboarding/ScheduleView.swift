import SwiftUI

struct ScheduleView: View {
    @Bindable var viewModel: OnboardingViewModel

    var body: some View {
        VStack(spacing: 32) {
            Text("Training Schedule")
                .font(.title2.bold())
            Text("How often and how long do you want to train?")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            VStack(spacing: 24) {
                // Days per week
                VStack(spacing: 12) {
                    HStack {
                        Text("Days per week")
                            .font(.headline)
                        Spacer()
                        Text("\(viewModel.trainingDaysPerWeek) days")
                            .font(.title3.bold())
                            .foregroundStyle(Color.accentColor)
                    }

                    HStack(spacing: 12) {
                        ForEach(2...5, id: \.self) { days in
                            Button {
                                viewModel.trainingDaysPerWeek = days
                            } label: {
                                Text("\(days)")
                                    .font(.title3.bold())
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 16)
                                    .background(viewModel.trainingDaysPerWeek == days ? Color.accentColor : Color(.secondarySystemBackground))
                                    .foregroundStyle(viewModel.trainingDaysPerWeek == days ? .white : .primary)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                            }
                        }
                    }
                }

                Divider()

                // Session duration
                VStack(spacing: 12) {
                    HStack {
                        Text("Session duration")
                            .font(.headline)
                        Spacer()
                        Text("\(viewModel.sessionDurationMinutes) min")
                            .font(.title3.bold())
                            .foregroundStyle(Color.accentColor)
                    }

                    Slider(
                        value: Binding(
                            get: { Double(viewModel.sessionDurationMinutes) },
                            set: { viewModel.sessionDurationMinutes = Int($0) }
                        ),
                        in: 20...90,
                        step: 5
                    )
                    .tint(.accentColor)

                    HStack {
                        Text("20 min")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("90 min")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.horizontal)

            Spacer()
        }
        .padding(.top, 32)
    }
}
