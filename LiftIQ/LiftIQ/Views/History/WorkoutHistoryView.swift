import SwiftUI

/// Weekly calendar of past sessions and projected upcoming plan days.
struct WorkoutHistoryView: View {
    @Environment(AppDependencies.self) private var dependencies
    @State private var viewModel = WorkoutHistoryViewModel()
    @State private var sessionPendingDeletion: WorkoutSession?
    @State private var workoutExecutionVM: WorkoutExecutionViewModel?

    private var unitSystem: UnitSystem {
        dependencies.authService.currentUser?.profile.unitSystem ?? .imperial
    }

    var body: some View {
        List {
            Section {
                weekHeader
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
            }

            ForEach(viewModel.weekDays, id: \.self) { day in
                daySection(for: day)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("History")
        .toolbar {
            if !viewModel.isCurrentWeek {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Today") { viewModel.goToCurrentWeek() }
                }
            }
        }
        .confirmationDialog(
            "Delete this workout?",
            isPresented: Binding(
                get: { sessionPendingDeletion != nil },
                set: { if !$0 { sessionPendingDeletion = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete Workout", role: .destructive) {
                if let session = sessionPendingDeletion {
                    Task { await viewModel.delete(session: session, workoutService: dependencies.workoutService) }
                }
                sessionPendingDeletion = nil
            }
        } message: {
            Text("This removes the workout and any records it set. This can't be undone.")
        }
        .alert("Something went wrong", isPresented: Binding(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
        .task {
            if let userId = dependencies.authService.currentUserId {
                try? await dependencies.workoutService.loadRecentSessions(userId: userId)
                try? await dependencies.workoutService.loadPlans(userId: userId)
            }
        }
        .fullScreenCover(item: $workoutExecutionVM) { vm in
            WorkoutExecutionView(viewModel: vm)
                .environment(dependencies)
        }
    }

    private func startWorkout(_ template: WorkoutTemplate) {
        guard let userId = dependencies.authService.currentUserId else { return }
        workoutExecutionVM = WorkoutExecutionViewModel(
            template: template,
            userId: userId,
            planId: dependencies.workoutService.activePlan?.id,
            workoutService: dependencies.workoutService,
            exerciseService: dependencies.exerciseService,
            progressService: dependencies.progressService,
            progressionService: dependencies.progressionService
        )
    }

    private var weekHeader: some View {
        HStack {
            Button {
                viewModel.moveWeek(by: -1)
            } label: {
                Image(systemName: "chevron.left")
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Previous week")

            Spacer()
            Text(weekRangeLabel)
                .font(.subheadline.weight(.semibold))
            Spacer()

            Button {
                viewModel.moveWeek(by: 1)
            } label: {
                Image(systemName: "chevron.right")
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Next week")
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color.accentColor)
    }

    private var weekRangeLabel: String {
        if viewModel.isCurrentWeek { return "This Week" }
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        let end = Calendar.current.date(byAdding: .day, value: 6, to: viewModel.weekStart) ?? viewModel.weekStart
        return "\(formatter.string(from: viewModel.weekStart)) – \(formatter.string(from: end))"
    }

    @ViewBuilder
    private func daySection(for day: Date) -> some View {
        let sessions = viewModel.sessions(on: day, from: dependencies.workoutService.recentSessions)
        let planned = viewModel.plannedEntries(
            plan: dependencies.workoutService.activePlan,
            sessions: dependencies.workoutService.recentSessions
        )[day]

        Section {
            if sessions.isEmpty && planned == nil {
                Text("Rest day")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            ForEach(sessions) { session in
                NavigationLink {
                    SessionDetailView(session: session)
                } label: {
                    SessionRowContent(session: session, unitSystem: unitSystem)
                }
                .swipeActions(edge: .trailing) {
                    Button("Delete", role: .destructive) {
                        sessionPendingDeletion = session
                    }
                }
            }

            if let planned {
                Button {
                    startWorkout(planned)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "calendar.badge.clock")
                            .foregroundStyle(Color.accentColor)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(planned.name)
                                .font(.subheadline.weight(.semibold))
                            Text("Planned \u{2022} ~\(planned.estimatedDurationMinutes) min")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .opacity(0.75)
                        Spacer()
                        Image(systemName: "play.circle.fill")
                            .font(.title3)
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(Color.accentColor)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Start \(planned.name)")
            }
        } header: {
            HStack {
                Text(dayLabel(for: day))
                if day.isToday {
                    Text("Today")
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.accentColor.opacity(0.15))
                        .foregroundStyle(Color.accentColor)
                        .clipShape(Capsule())
                }
            }
        }
    }

    private func dayLabel(for day: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMM d"
        return formatter.string(from: day)
    }
}

/// Shared row body for a finished session (history list and dashboard).
struct SessionRowContent: View {
    let session: WorkoutSession
    let unitSystem: UnitSystem

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(session.workoutName)
                        .font(.subheadline.weight(.semibold))
                    if session.status == .abandoned {
                        Text("Abandoned")
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.liftWarning.opacity(0.15))
                            .foregroundStyle(Color.liftWarning)
                            .clipShape(Capsule())
                    }
                }
                Text(session.startedAt.relativeDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text(Formatters.durationString(from: session.durationSeconds))
                    .font(.subheadline)
                Text("\(Int(UnitConversionService.convertWeight(session.totalVolumeKg, to: unitSystem))) \(UnitConversionService.weightLabel(for: unitSystem))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
