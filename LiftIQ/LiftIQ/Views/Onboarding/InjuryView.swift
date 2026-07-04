import SwiftUI

struct InjuryView: View {
    @Bindable var viewModel: OnboardingViewModel

    let severities = ["Mild", "Moderate", "Severe"]

    var body: some View {
        VStack(spacing: 24) {
            Text("Injuries")
                .font(.title2.bold())
            Text("Any injuries we should work around? (Optional)")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            ScrollView {
                VStack(spacing: 16) {
                    // Existing injuries
                    ForEach(viewModel.injuries) { injury in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(injury.bodyPart)
                                    .font(.subheadline.weight(.semibold))
                                Text(injury.severity)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                if !injury.notes.isEmpty {
                                    Text(injury.notes)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Button {
                                viewModel.removeInjury(injury)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .accessibilityLabel("Remove \(injury.bodyPart) injury")
                        }
                        .padding()
                        .background(Color(.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }

                    // Add new injury
                    VStack(spacing: 12) {
                        TextField("Body part (e.g., Left Shoulder)", text: $viewModel.newInjuryBodyPart)
                            .padding()
                            .background(Color(.secondarySystemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 12))

                        Picker("Severity", selection: $viewModel.newInjurySeverity) {
                            ForEach(severities, id: \.self) { severity in
                                Text(severity).tag(severity)
                            }
                        }
                        .pickerStyle(.segmented)

                        TextField("Notes (optional)", text: $viewModel.newInjuryNotes)
                            .padding()
                            .background(Color(.secondarySystemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 12))

                        Button {
                            viewModel.addInjury()
                        } label: {
                            Label("Add Injury", systemImage: "plus.circle.fill")
                                .font(.subheadline.weight(.semibold))
                        }
                        .disabled(viewModel.newInjuryBodyPart.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
                .padding(.horizontal)
            }

            Spacer()
        }
        .padding(.top, 32)
    }
}
