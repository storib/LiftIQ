import SwiftUI

struct TemplateBrowserView: View {
    @Environment(AppDependencies.self) private var dependencies
    @State private var selectedTemplate: TemplateType?
    @State private var isGenerating = false
    @State private var errorMessage: String?

    var body: some View {
        List {
            ForEach(TemplateType.allCases) { template in
                Button {
                    selectedTemplate = template
                } label: {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(template.displayName)
                                .font(.headline)
                            Spacer()
                            Text("\(template.recommendedDaysPerWeek)x/week")
                                .font(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.accentColor.opacity(0.1))
                                .clipShape(Capsule())
                        }
                        Text(template.description)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
            }
        }
        .navigationTitle("Program Templates")
        .alert("Generate Program", isPresented: Binding(
            get: { selectedTemplate != nil },
            set: { if !$0 { selectedTemplate = nil } }
        )) {
            Button("Generate") {
                if let template = selectedTemplate {
                    generatePlan(template: template)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            if let template = selectedTemplate {
                Text("Create a personalized \(template.displayName) program based on your profile?")
            }
        }
        .overlay {
            if isGenerating {
                VStack(spacing: 16) {
                    ProgressView()
                    Text("Generating your program...")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.ultraThinMaterial)
            }
        }
    }

    private func generatePlan(template: TemplateType) {
        guard let profile = dependencies.authService.currentUser?.profile,
              let userId = dependencies.authService.currentUserId else { return }

        isGenerating = true
        Task {
            do {
                var plan = try await dependencies.aiService.generateWorkoutPlan(profile: profile, templateType: template)
                plan.userId = userId
                plan.isActive = true
                try await dependencies.workoutService.savePlan(plan)
            } catch {
                errorMessage = error.localizedDescription
            }
            isGenerating = false
        }
    }
}
