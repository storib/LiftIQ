#if DEBUG
import SwiftUI

/// Debug-only design harness: `-LiftIQDesignPreview` launches straight into
/// the tab bar with sample data instead of Firebase, so screens can be
/// screenshotted on a simulator in light and dark mode without an account.
///
///     xcrun simctl launch booted com.adrianconley.liftiq -LiftIQDesignPreview
///         [-LiftIQDesignPreviewActiveSession] [-LiftIQDesignPreviewScrollBottom]
///         [-LiftIQDesignPreviewSelectWorkoutDay]
///
/// Nothing here is compiled into Release builds.
@MainActor
enum DesignPreview {
    static var isActive: Bool { arguments.contains("-LiftIQDesignPreview") }
    static var showsActiveSession: Bool { arguments.contains("-LiftIQDesignPreviewActiveSession") }
    static var scrollsToBottom: Bool { arguments.contains("-LiftIQDesignPreviewScrollBottom") }
    static var selectsWorkoutDay: Bool { arguments.contains("-LiftIQDesignPreviewSelectWorkoutDay") }
    private static var arguments: [String] { ProcessInfo.processInfo.arguments }

    /// Consumed by `DashboardView` instead of a Firebase load.
    private(set) static var dashboardSeed: DashboardViewModel?
    private static var previewUser: LiftIQUser?

    /// Firebase's auth listener reports "signed out" shortly after launch and
    /// clears the user; the preview root re-applies it once that has fired.
    static func reapplyUser(_ dependencies: AppDependencies) {
        dependencies.authService.currentUserId = previewUser?.id
        dependencies.authService.currentUser = previewUser
    }

    static func seed(_ dependencies: AppDependencies) {
        UserDefaults.standard.set(true, forKey: "liftiq_seen_getting_started")
        let now = Date()
        let calendar = Calendar.current

        let profile = UserProfile(
            experienceLevel: .intermediate, goals: [.hypertrophy], availableEquipment: Equipment.allCases,
            trainingDaysPerWeek: 4, sessionDurationMinutes: 60, injuries: [],
            bodyWeightKg: nil, heightCm: nil, dateOfBirth: nil, unitSystem: .imperial
        )
        previewUser = LiftIQUser(
            id: "preview", email: "preview@example.com", displayName: "Adrian",
            profile: profile, createdAt: now, updatedAt: now
        )
        reapplyUser(dependencies)

        func slot(_ id: String, sets: Int, _ min: Int, _ max: Int) -> PlannedExercise {
            PlannedExercise(id: "slot-\(id)", exerciseId: id, order: 1, sets: sets, repsMin: min, repsMax: max,
                            rirTarget: nil, rpeTarget: nil, restSeconds: 120, warmUpSets: nil, notes: nil, isOptional: false)
        }
        func day(_ id: String, _ number: Int, _ name: String, _ muscles: [MuscleGroup], _ slots: [PlannedExercise]) -> WorkoutTemplate {
            WorkoutTemplate(
                id: id, planId: "preview-plan", dayNumber: number, name: name, targetMuscleGroups: muscles,
                estimatedDurationMinutes: 55,
                exerciseGroups: slots.map { ExerciseGroup(id: "g-\($0.id)", groupType: .straight, exercises: [$0], restBetweenRoundsSeconds: nil) },
                notes: nil
            )
        }
        let lower = day("day-lower", 2, "Lower A", [.quads, .hamstrings, .glutes], [
            slot("barbell-back-squat", sets: 4, 6, 8), slot("romanian-deadlift-barbell", sets: 3, 8, 10),
            slot("front-squat", sets: 3, 8, 12), slot("leg-extension", sets: 3, 10, 15),
            slot("standing-calf-raise", sets: 3, 10, 15),
        ])
        let upper = day("day-upper", 1, "Upper A", [.chest, .back, .shoulders], [
            slot("barbell-bench-press", sets: 4, 6, 8), slot("barbell-row", sets: 4, 8, 10),
            slot("lateral-raise-dumbbell", sets: 3, 12, 15),
        ])
        let plan = WorkoutPlan(
            id: "preview-plan", userId: "preview", name: "Upper / Lower", templateType: .upperLower, goal: .hypertrophy,
            weekCount: 6, currentWeek: 1, workoutsPerWeek: 4, workouts: [upper, lower], deloadWeek: nil,
            isActive: true, createdAt: now.addingTimeInterval(-86_400 * 20), aiGenerated: true, aiPromptContext: nil
        )
        dependencies.workoutService.plans = [plan]
        dependencies.workoutService.activePlan = plan

        let weekStart = now.startOfWeek(using: calendar)
        let sessions: [WorkoutSession] = [(0, "Upper A", 3_120), (2, "Lower A", 3_300)].compactMap { offset, name, seconds in
            guard let start = calendar.date(byAdding: .day, value: offset, to: weekStart)?.addingTimeInterval(18 * 3_600),
                  start < now else { return nil }
            let log = ExerciseLog(
                id: "log-\(offset)", sessionId: "s-\(offset)", exerciseId: "barbell-back-squat", exerciseName: "Barbell Back Squat",
                order: 1, groupType: .straight,
                sets: (1...4).map { SetLog(id: "set-\(offset)-\($0)", setNumber: $0, setType: .working, weightKg: 100, reps: 8,
                                          rpe: nil, isPersonalRecord: false, completedAt: start) },
                notes: nil
            )
            return WorkoutSession(
                id: "s-\(offset)", userId: "preview", planId: plan.id, workoutTemplateId: offset == 0 ? upper.id : lower.id,
                workoutName: name, startedAt: start, completedAt: start.addingTimeInterval(Double(seconds)),
                status: .completed, exerciseLogs: [log], durationSeconds: seconds, notes: nil, mood: 3
            )
        }
        dependencies.workoutService.recentSessions = sessions.reversed()
        if showsActiveSession {
            dependencies.workoutService.activeSession = WorkoutSession(
                id: "active", userId: "preview", planId: plan.id, workoutTemplateId: lower.id, workoutName: "Lower A",
                startedAt: now.addingTimeInterval(-1_500), completedAt: nil, status: .inProgress, exerciseLogs: [],
                durationSeconds: 0, notes: nil, mood: nil
            )
        }

        let vm = DashboardViewModel(referenceDate: now, calendar: calendar)
        vm.todayWorkout = lower
        vm.weekStreak = 4
        vm.blockProgress = BlockProgress(blockNumber: 1, weekCount: 6, workoutsPerWeek: 4, completedSessions: 9)
        vm.weeklySessionCount = sessions.count
        vm.weeklyVolume = sessions.reduce(0) { $0 + $1.totalVolumeKg }
        vm.coachSuggestion = CoachSuggestion(planId: plan.id, lifts: [
            .init(slotId: "slot-front-squat", dayId: lower.id, dayName: lower.name, exerciseId: "front-squat",
                  name: "Front Squat", repsMin: 8, repsMax: 12, sessions: 3),
        ])
        if selectsWorkoutDay, let latest = sessions.last {
            vm.selectedDate = calendar.startOfDay(for: latest.startedAt)
        }
        dashboardSeed = vm
    }
}
#endif
