import XCTest
@testable import LiftIQ

@MainActor
final class AdaptWorkoutTests: XCTestCase {

    // MARK: - Fixtures

    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)

    private func exercise(_ id: String, muscle: MuscleGroup = .chest, equipment: [Equipment] = [.barbell, .bench],
                          pattern: MovementPattern = .horizontalPush, compound: Bool = true) -> Exercise {
        Exercise(id: id, name: id.capitalized, primaryMuscleGroup: muscle, secondaryMuscleGroups: [], equipment: equipment,
                 movementPattern: pattern, difficulty: .intermediate, youtubeVideoId: "", instructions: "", tips: [],
                 alternatives: [], isCompound: compound, tags: [])
    }

    private var catalog: [Exercise] {
        [
            exercise("bench"),
            exercise("db-press", equipment: [.dumbbell, .bench]),
            exercise("push-up", equipment: [.bodyweight]),
            exercise("cable-fly", equipment: [.cables], pattern: .isolation, compound: false),
            exercise("pushdown", muscle: .triceps, equipment: [.cables], pattern: .isolation, compound: false),
            exercise("dips", muscle: .triceps, equipment: [.bodyweight], pattern: .verticalPush),
            exercise("lateral-raise", muscle: .shoulders, equipment: [.dumbbell], pattern: .isolation, compound: false),
        ]
    }

    private func planned(_ exerciseId: String, sets: Int = 3, optional: Bool = false) -> PlannedExercise {
        PlannedExercise(id: "slot-\(exerciseId)", exerciseId: exerciseId, order: 1, sets: sets, repsMin: 8, repsMax: 12,
                        rirTarget: nil, rpeTarget: nil, restSeconds: 90, warmUpSets: nil, notes: nil, isOptional: optional)
    }

    private func template(id: String = "day-1", _ ids: [String]) -> WorkoutTemplate {
        WorkoutTemplate(id: id, planId: "plan-1", dayNumber: 1, name: "Push", targetMuscleGroups: [.chest], estimatedDurationMinutes: 60,
                        exerciseGroups: ids.map { ExerciseGroup(id: "g-\($0)", groupType: .straight, exercises: [planned($0, optional: $0 == "lateral-raise")], restBetweenRoundsSeconds: nil) },
                        notes: nil)
    }

    private func profile(setups: [GymSetup]? = nil, preferences: [String: ExercisePreference]? = nil) -> UserProfile {
        var p = UserProfile(experienceLevel: .intermediate, goals: [.hypertrophy], availableEquipment: Equipment.allCases,
                            trainingDaysPerWeek: 3, sessionDurationMinutes: 60, injuries: [], bodyWeightKg: nil, heightCm: nil,
                            dateOfBirth: nil, unitSystem: .metric)
        p.gymSetups = setups
        p.exercisePreferences = preferences
        return p
    }

    private func makePlan(workouts: [WorkoutTemplate], id: String = "plan-1") -> WorkoutPlan {
        WorkoutPlan(id: id, userId: "u1", name: "Plan", templateType: .ppl, goal: .hypertrophy, weekCount: 6, currentWeek: 1,
                    workoutsPerWeek: workouts.count, workouts: workouts, deloadWeek: nil, isActive: true, createdAt: t0,
                    aiGenerated: true, aiPromptContext: nil)
    }

    private func completedSession(templateId: String, at: Date) -> WorkoutSession {
        WorkoutSession(id: UUID().uuidString, userId: "u1", planId: "plan-1", workoutTemplateId: templateId, workoutName: "Day",
                       startedAt: at, completedAt: at.addingTimeInterval(3600), status: .completed, exerciseLogs: [],
                       durationSeconds: 3600, notes: nil, mood: nil)
    }

    private func makeAdaptVM(kind: WorkoutAdaptationKind, template: WorkoutTemplate, profile: UserProfile,
                             memory: FakeMemoryService? = nil, events: FakeBetaEventLogger? = nil,
                             consent: Bool = false) -> AdaptWorkoutViewModel {
        AdaptWorkoutViewModel(
            kind: kind, template: template, profile: profile, userId: "u1",
            exerciseService: FakeExerciseService(exercises: catalog), workoutService: FakeWorkoutService(),
            aiService: nil, memory: memory, betaEvents: events ?? FakeBetaEventLogger(), hasAIConsent: { consent }
        )
    }

    // MARK: - Dashboard adaptation guard

    func testAdaptationSurvivesReloadOnSameDayButDropsWhenDayAdvancesOrPlanChanges() async {
        let day1 = template(id: "day-1", ["bench", "cable-fly"])
        let day2 = template(id: "day-2", ["dips"])
        let workout = FakeWorkoutService()
        workout.plans = [makePlan(workouts: [day1, day2])]
        workout.activePlan = workout.plans[0]
        let vm = DashboardViewModel(referenceDate: t0)
        await vm.load(workoutService: workout, healthKitService: FakeHealthKitService(), userId: "u1", referenceDate: t0)
        XCTAssertEqual(vm.todayWorkout?.id, "day-1")

        let adapted = WorkoutAdapter.shortOnTime(day1, targetMinutes: 10, context: .init(exercises: Dictionary(uniqueKeysWithValues: catalog.map { ($0.id, $0) })))
        vm.adaptedWorkout = adapted
        XCTAssertEqual(vm.effectiveTodayWorkout?.exerciseGroups.count, adapted.template.exerciseGroups.count)

        // Same recommended day after a reload: adaptation survives.
        await vm.load(workoutService: workout, healthKitService: FakeHealthKitService(), userId: "u1", referenceDate: t0)
        XCTAssertNotNil(vm.adaptedWorkout)

        // Day 1 completed → next is day 2 → the day-1 adaptation is dropped.
        workout.recentSessions = [completedSession(templateId: "day-1", at: t0.addingTimeInterval(60))]
        await vm.load(workoutService: workout, healthKitService: FakeHealthKitService(), userId: "u1", referenceDate: t0.addingTimeInterval(120))
        XCTAssertEqual(vm.todayWorkout?.id, "day-2")
        XCTAssertNil(vm.adaptedWorkout)
        XCTAssertEqual(vm.effectiveTodayWorkout?.id, "day-2")

        // Choosing a different day via "Change" clears too.
        vm.adaptedWorkout = WorkoutAdapter.shortOnTime(day2, targetMinutes: 5, context: .init(exercises: [:]))
        vm.selectWorkout(day1)
        XCTAssertNil(vm.adaptedWorkout)

        // A plan swap with the same day id still drops it.
        vm.adaptedWorkout = adapted
        workout.plans = [makePlan(workouts: [day1], id: "plan-2")]
        workout.activePlan = workout.plans[0]
        workout.recentSessions = []
        await vm.load(workoutService: workout, healthKitService: FakeHealthKitService(), userId: "u1", referenceDate: t0)
        XCTAssertNil(vm.adaptedWorkout)
    }

    // MARK: - AdaptWorkoutViewModel flows

    func testShortOnTimeFlowProducesPreviewAndLogsAcceptance() async {
        let events = FakeBetaEventLogger()
        let vm = makeAdaptVM(kind: .shortOnTime, template: template(["bench", "cable-fly", "pushdown", "lateral-raise"]),
                             profile: profile(), events: events)
        XCTAssertEqual(vm.step, .pickMinutes)
        await vm.prepare()
        vm.targetMinutes = 15
        vm.applyMinutes()

        XCTAssertEqual(vm.step, .preview)
        XCTAssertFalse(vm.result?.changes.isEmpty ?? true)
        XCTAssertEqual(vm.result?.record.kind, .shortOnTime)
        XCTAssertEqual(vm.result?.record.targetMinutes, 15)
        XCTAssertEqual(UserDefaults.standard.integer(forKey: AdaptWorkoutViewModel.lastMinutesKey), 15)

        let accepted = await vm.accept()
        XCTAssertNotNil(accepted)
        let event = events.names("adapt_chosen").first
        XCTAssertEqual(event?.props["kind"] as? String, "shortOnTime")
        XCTAssertEqual(event?.props["accepted"] as? Bool, true)
    }

    func testEquipmentBusyFlowRanksUsualAlternativeAndRemembersChoice() async {
        let memory = FakeMemoryService()
        let vm = makeAdaptVM(kind: .equipmentBusy, template: template(["bench", "pushdown"]),
                             profile: profile(preferences: ["bench": ExercisePreference(usualAlternativeId: "push-up")]),
                             memory: memory)
        await vm.prepare()
        vm.chooseBusy(exerciseId: "bench")
        guard case .pickCandidate(let id) = vm.step else { return XCTFail("expected candidate step") }
        XCTAssertEqual(id, "bench")
        XCTAssertEqual(vm.candidates.first?.id, "push-up")
        XCTAssertTrue(vm.candidates.first?.isUsualAlternative ?? false)

        vm.chooseCandidate(vm.candidates[1])   // db-press
        XCTAssertEqual(vm.step, .preview)
        XCTAssertEqual(vm.result?.template.exerciseGroups[0].exercises[0].exerciseId, "db-press")
        XCTAssertEqual(vm.result?.changes.first?.kind, .swappedExercise)

        _ = await vm.accept()
        XCTAssertEqual(memory.recordedAlternatives.first?.exerciseId, "bench")
        XCTAssertEqual(memory.recordedAlternatives.first?.replacement, "db-press")
    }

    func testDifferentGymWithoutAIOffersConsentThenDropsUnresolved() async {
        let bands = GymSetup(id: "bands", name: "Bands", equipment: [.bands], isDefault: false)
        let vm = makeAdaptVM(kind: .differentGym, template: template(["bench"]),
                             profile: profile(setups: [GymSetup(id: "main", name: "Gym", equipment: Equipment.allCases, isDefault: true), bands]))
        await vm.prepare()
        XCTAssertEqual(vm.otherSetups.map(\.id), ["bands"])

        await vm.chooseSetup(bands)
        XCTAssertEqual(vm.step, .needsConsent, "no chest exercise fits bands only, and there is no AI/consent")
        XCTAssertEqual(vm.unresolved.map(\.exerciseId), ["bench"])

        vm.dropUnresolved()
        XCTAssertEqual(vm.step, .preview)
        XCTAssertTrue(vm.result?.template.exerciseGroups.isEmpty ?? false)
        XCTAssertEqual(vm.result?.changes.first?.kind, .removedExercise)
        XCTAssertEqual(vm.result?.record.gymSetupId, "bands")
    }

    func testDifferentGymResolvesWithoutAIWhenCatalogCovers() async {
        let home = GymSetup(id: "home", name: "Home", equipment: [.dumbbell, .bench, .bodyweight], isDefault: false)
        let vm = makeAdaptVM(kind: .differentGym, template: template(["bench", "pushdown"]),
                             profile: profile(setups: [GymSetup(id: "main", name: "Gym", equipment: Equipment.allCases, isDefault: true), home]))
        await vm.prepare()
        await vm.chooseSetup(home)
        XCTAssertEqual(vm.step, .preview)
        XCTAssertEqual(vm.result?.changes.count, 2)
        XCTAssertEqual(vm.result?.record.usedAI, false)
    }

    // MARK: - Session carries the adaptation

    func testStartPersistsSessionAdaptation() async {
        let workout = FakeWorkoutService()
        let day = template(["bench", "cable-fly"])
        let adapted = WorkoutAdapter.shortOnTime(day, targetMinutes: 10, context: .init(exercises: Dictionary(uniqueKeysWithValues: catalog.map { ($0.id, $0) })))
        let events = FakeBetaEventLogger()
        let vm = WorkoutExecutionViewModel(
            template: adapted.template, userId: "u1", planId: "plan-1",
            workoutService: workout, exerciseService: FakeExerciseService(exercises: catalog),
            progressService: FakeProgressService(), progressionService: ProgressionService(),
            startSource: "dashboard", betaEvents: events
        )
        defer { vm.stopTimers() }
        vm.session.adaptation = adapted.record

        await vm.start(userUnitSystem: .metric)

        XCTAssertEqual(workout.startedSessions.first?.adaptation?.kind, .shortOnTime)
        XCTAssertEqual(events.names("session_started").first?.props["adapted"] as? String, "shortOnTime")
    }

    // MARK: - Review fixes

    func testResumeRebuildsPrescriptionsFromTheSessionTemplateOverride() async {
        // Plan day rests 180 s; the adapted session shortened it to 90 s.
        var planDay = template(["bench", "cable-fly"])
        planDay.exerciseGroups[0].exercises[0].restSeconds = 180
        var adaptedDay = planDay
        adaptedDay.exerciseGroups[0].exercises[0].restSeconds = 90
        let workout = FakeWorkoutService()
        workout.plans = [makePlan(workouts: [planDay])]
        workout.activePlan = workout.plans[0]

        var existing = WorkoutSession.create(from: adaptedDay, userId: "u1", planId: "plan-1")
        existing.templateOverride = adaptedDay
        let vm = WorkoutExecutionViewModel(
            existingSession: existing, workoutService: workout, exerciseService: FakeExerciseService(exercises: catalog),
            progressService: FakeProgressService(), progressionService: ProgressionService()
        )
        defer { vm.stopTimers() }

        await vm.start(userUnitSystem: .metric)

        XCTAssertEqual(vm.plannedExercise(for: "bench")?.restSeconds, 90)
        XCTAssertEqual(vm.restDuration(forExerciseLogIndex: 0, setIndex: 2).seconds, 90)
    }

    func testResumeWithoutOverrideStillUsesThePlan() async {
        var planDay = template(["bench", "cable-fly"])
        planDay.exerciseGroups[0].exercises[0].restSeconds = 180
        let workout = FakeWorkoutService()
        workout.plans = [makePlan(workouts: [planDay])]
        let existing = WorkoutSession.create(from: planDay, userId: "u1", planId: "plan-1")
        let vm = WorkoutExecutionViewModel(
            existingSession: existing, workoutService: workout, exerciseService: FakeExerciseService(exercises: catalog),
            progressService: FakeProgressService(), progressionService: ProgressionService()
        )
        defer { vm.stopTimers() }
        await vm.start(userUnitSystem: .metric)
        XCTAssertEqual(vm.plannedExercise(for: "bench")?.restSeconds, 180)
    }

    func testApplyPreStartAdaptationStampsRecordAndTemplate() {
        let day = template(["bench", "cable-fly"])
        let adapted = WorkoutAdapter.shortOnTime(day, targetMinutes: 10, context: .init(exercises: Dictionary(uniqueKeysWithValues: catalog.map { ($0.id, $0) })))
        let vm = WorkoutExecutionViewModel(
            template: adapted.template, userId: "u1", planId: "plan-1",
            workoutService: FakeWorkoutService(), exerciseService: FakeExerciseService(exercises: catalog),
            progressService: FakeProgressService(), progressionService: ProgressionService()
        )
        vm.applyPreStartAdaptation(adapted)
        XCTAssertEqual(vm.session.adaptation?.kind, .shortOnTime)
        XCTAssertEqual(vm.session.templateOverride, adapted.template)
    }

    func testActiveEquipmentFollowsTheAdaptedGym() {
        let home = GymSetup(id: "home", name: "Home", equipment: [.dumbbell, .bench], isDefault: false)
        let main = GymSetup(id: "main", name: "Gym", equipment: Equipment.allCases, isDefault: true)
        let p = profile(setups: [main, home])
        var session = completedSession(templateId: "day-1", at: t0)
        XCTAssertEqual(session.activeEquipment(in: p), Set(Equipment.allCases))

        session.adaptation = WorkoutAdaptation(kind: .differentGym, gymSetupId: "home", changes: [], usedAI: false, acceptedAt: t0)
        XCTAssertEqual(session.activeEquipment(in: p), [.dumbbell, .bench])

        // A setup deleted since the session started falls back to the default.
        session.adaptation?.gymSetupId = "gone"
        XCTAssertEqual(session.activeEquipment(in: p), Set(Equipment.allCases))
        XCTAssertEqual(session.activeEquipment(in: nil), Set(Equipment.allCases))
    }

    func testEmptyWorkoutAfterRemovalIsNotAcceptable() async {
        let bands = GymSetup(id: "bands", name: "Bands", equipment: [.bands], isDefault: false)
        let events = FakeBetaEventLogger()
        let vm = makeAdaptVM(kind: .differentGym, template: template(["bench"]),
                             profile: profile(setups: [GymSetup(id: "main", name: "Gym", equipment: Equipment.allCases, isDefault: true), bands]),
                             events: events)
        await vm.prepare()
        await vm.chooseSetup(bands)
        vm.dropUnresolved()

        XCTAssertEqual(vm.result?.isUsable, false)
        let accepted = await vm.accept()
        XCTAssertNil(accepted, "an empty workout must never be handed to Start")
        XCTAssertTrue(events.names("adapt_chosen").isEmpty)
    }

    func testMidWorkoutAIEditRefreshesTheTemplateOverrideForResume() async {
        // Adapted to 90 s rest, then changed to 120 s through a mid-workout
        // AI edit; a relaunch must resume with 120, not the older snapshot.
        var planDay = template(["bench", "cable-fly"])
        planDay.exerciseGroups[0].exercises[0].restSeconds = 180
        var adaptedDay = planDay
        adaptedDay.exerciseGroups[0].exercises[0].restSeconds = 90
        let workout = FakeWorkoutService()
        workout.plans = [makePlan(workouts: [planDay])]
        workout.activePlan = workout.plans[0]
        let exercises = FakeExerciseService(exercises: catalog)

        let vm = WorkoutExecutionViewModel(
            template: adaptedDay, userId: "u1", planId: "plan-1",
            workoutService: workout, exerciseService: exercises,
            progressService: FakeProgressService(), progressionService: ProgressionService()
        )
        vm.applyPreStartTemplateOverride(adaptedDay)
        await vm.start(userUnitSystem: .metric)
        XCTAssertEqual(vm.plannedExercise(for: "bench")?.restSeconds, 90)

        var edited = adaptedDay
        edited.exerciseGroups[0].exercises[0].restSeconds = 120
        await vm.applyModifiedWorkout(edited)
        vm.stopTimers()
        XCTAssertEqual(vm.session.templateOverride?.exerciseGroups[0].exercises[0].restSeconds, 120)
        XCTAssertEqual(workout.updatedSessions.last?.templateOverride?.exerciseGroups[0].exercises[0].restSeconds, 120,
                       "the override must be in the document that was saved")

        // Relaunch: resume from what was persisted.
        let resumed = WorkoutExecutionViewModel(
            existingSession: workout.updatedSessions.last!, workoutService: workout, exerciseService: exercises,
            progressService: FakeProgressService(), progressionService: ProgressionService()
        )
        defer { resumed.stopTimers() }
        await resumed.start(userUnitSystem: .metric)
        XCTAssertEqual(resumed.plannedExercise(for: "bench")?.restSeconds, 120)
    }
}
