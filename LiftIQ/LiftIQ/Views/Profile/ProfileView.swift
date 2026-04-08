import SwiftUI

struct ProfileView: View {
    @Environment(AppDependencies.self) private var dependencies

    var body: some View {
        List {
            if let user = dependencies.authService.currentUser {
                Section {
                    HStack(spacing: 16) {
                        Image(systemName: "person.circle.fill")
                            .font(.system(size: 48))
                            .foregroundStyle(Color.accentColor)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(user.displayName)
                                .font(.title3.bold())
                            Text(user.email)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section("Training Profile") {
                    LabeledContent("Experience", value: user.profile.experienceLevel.displayName)
                    LabeledContent("Goals", value: user.profile.goals.map { $0.displayName }.joined(separator: ", "))
                    LabeledContent("Schedule", value: "\(user.profile.trainingDaysPerWeek) days/week")
                    LabeledContent("Session Length", value: "\(user.profile.sessionDurationMinutes) min")
                    LabeledContent("Units", value: user.profile.unitSystem == .metric ? "Metric" : "Imperial")
                }

                Section("Equipment") {
                    let equipmentList = user.profile.availableEquipment.map { $0.displayName }.joined(separator: ", ")
                    Text(equipmentList)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                Button("Sign Out", role: .destructive) {
                    try? dependencies.authService.signOut()
                }
            }
        }
        .navigationTitle("Profile")
    }
}
