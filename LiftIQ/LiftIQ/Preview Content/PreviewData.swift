import Foundation

enum PreviewData {
    static let user = LiftIQUser(
        id: "preview-user",
        email: "john@example.com",
        displayName: "John",
        profile: UserProfile(
            experienceLevel: .intermediate,
            goals: [.hypertrophy],
            availableEquipment: [.barbell, .dumbbell, .cables, .machines, .pullUpBar],
            trainingDaysPerWeek: 4,
            sessionDurationMinutes: 60,
            injuries: [],
            bodyWeightKg: 80,
            heightCm: 178,
            dateOfBirth: nil,
            unitSystem: .metric
        ),
        createdAt: Date(),
        updatedAt: Date()
    )

    static let exercise = Exercise(
        id: "bench-press",
        name: "Barbell Bench Press",
        primaryMuscleGroup: .chest,
        secondaryMuscleGroups: [.triceps, .frontDelts],
        equipment: [.barbell, .bench],
        movementPattern: .horizontalPush,
        difficulty: .beginner,
        youtubeVideoId: "rT7DgCr-3pg",
        instructions: "Lie on a flat bench, grip the bar slightly wider than shoulder-width. Lower the bar to your chest, then press back up.",
        tips: ["Keep your feet flat on the floor", "Retract your shoulder blades", "Drive through your heels"],
        alternatives: ["dumbbell-bench-press", "machine-chest-press"],
        isCompound: true,
        tags: ["chest", "compound", "barbell"]
    )

    static let setLog = SetLog(
        id: "set-1",
        setNumber: 1,
        setType: .working,
        weightKg: 80,
        reps: 8,
        rpe: 7.5,
        isPersonalRecord: false,
        completedAt: Date()
    )

    static let exerciseLog = ExerciseLog(
        id: "log-1",
        sessionId: "session-1",
        exerciseId: "bench-press",
        exerciseName: "Barbell Bench Press",
        order: 1,
        groupType: .straight,
        sets: [setLog],
        notes: nil
    )

    static let workoutSession = WorkoutSession(
        id: "session-1",
        userId: "preview-user",
        planId: "plan-1",
        workoutTemplateId: "template-1",
        workoutName: "Push Day A",
        startedAt: Date().addingTimeInterval(-3600),
        completedAt: nil,
        status: .inProgress,
        exerciseLogs: [exerciseLog],
        durationSeconds: 3600,
        notes: nil,
        mood: nil
    )
}
