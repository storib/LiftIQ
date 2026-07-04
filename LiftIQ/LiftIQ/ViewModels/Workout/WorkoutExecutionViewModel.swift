import Foundation
import Observation

/// Text-field backing storage for a single set row. Keyed by SetLog.id in
/// `WorkoutExecutionViewModel.setInputs`, so adding/removing/reordering sets
/// can never desynchronize inputs from their sets.
struct SetInput: Hashable {
    var weight = ""
    var reps = ""
    var rpe = ""
}

extension Dictionary where Value == SetInput {
    /// Writable defaulting subscript usable from SwiftUI Bindings.
    /// The stdlib `[key, default:]` subscript takes its default as
    /// `@autoclosure`, which cannot appear in a key path, so
    /// `$viewModel.setInputs[id, default: SetInput()]` does not compile.
    /// This overload takes a plain value and forms a writable key path:
    /// `$viewModel.setInputs[setId: id].weight`.
    subscript(setId key: Key) -> SetInput {
        get { self[key] ?? SetInput() }
        set { self[key] = newValue }
    }
}

@MainActor
@Observable
final class WorkoutExecutionViewModel: Identifiable {
    let id = UUID().uuidString

    // MARK: - Dependencies

    private let workoutService: any WorkoutServicing
    private let exerciseService: any ExerciseServicing
    private let progressService: any ProgressServicing
    let progressionService: ProgressionService
    let userId: String

    // MARK: - Session State

    var session: WorkoutSession
    var exerciseDetails: [String: Exercise] = [:]
    var previousLogs: [String: ExerciseLog] = [:]
    var progressionSuggestions: [String: ProgressionSuggestion] = [:]

    // MARK: - Input State (keyed by SetLog.id)

    var setInputs: [String: SetInput] = [:]

    // MARK: - UI State

    var isLoading = false
    var errorMessage: String?
    var elapsedSeconds: Int = 0
    var unitSystem: UnitSystem = .imperial {
        didSet {
            guard unitSystem != oldValue else { return }
            convertWeightInputs(from: oldValue, to: unitSystem)
        }
    }
    var completedSetIds: Set<String> = []

    // MARK: - Rest Timer

    let restTimer = RestTimerController()

    // MARK: - PR Tracking

    var newPR: PersonalRecord?
    var sessionPRs: [PersonalRecord] = []

    // Session-scoped cache of each exercise's existing PRs so completing a
    // set doesn't re-query Firestore on every checkmark tap.
    private var prCache: [String: [PersonalRecord]] = [:]

    // MARK: - Navigation

    var showingSummary = false
    var showingExerciseSwap = false
    var showingAbandonConfirmation = false
    var swapTargetExerciseLogIndex: Int?

    // MARK: - Group Mapping (for superset rest logic)

    var exerciseGroupMap: [Int: Int] = [:]   // exerciseLogIndex -> group index
    var templateGroups: [ExerciseGroup] = []

    // Fallback rest duration when a planned exercise has no restSeconds set.
    // Sourced from the user's profile via start(...).
    var userDefaultRestSeconds: Int = 60

    // Optional: when set before presenting, the view scrolls to the matching
    // exercise log on first appear (used for deep-links from program day view).
    var scrollToExerciseLogIndex: Int?

    // MARK: - Timers

    // Derives its displayed value from wall-clock dates so the count survives
    // backgrounding (foreground Timers suspend). Rest is in RestTimerController.
    private var elapsedTimer: Timer?
    private var hasStarted = false

    // MARK: - Init (new session from template)

    init(
        template: WorkoutTemplate,
        userId: String,
        planId: String?,
        workoutService: any WorkoutServicing,
        exerciseService: any ExerciseServicing,
        progressService: any ProgressServicing,
        progressionService: ProgressionService
    ) {
        self.workoutService = workoutService
        self.exerciseService = exerciseService
        self.progressService = progressService
        self.progressionService = progressionService
        self.userId = userId
        self.session = WorkoutSession.create(from: template, userId: userId, planId: planId)
        self.templateGroups = template.exerciseGroups
        buildGroupMap(from: template.exerciseGroups)
        initializeInputs()
    }

    // MARK: - Init (resume existing session)

    init(
        existingSession: WorkoutSession,
        workoutService: any WorkoutServicing,
        exerciseService: any ExerciseServicing,
        progressService: any ProgressServicing,
        progressionService: ProgressionService
    ) {
        self.workoutService = workoutService
        self.exerciseService = exerciseService
        self.progressService = progressService
        self.progressionService = progressionService
        self.userId = existingSession.userId
        self.session = existingSession
        self.elapsedSeconds = max(0, Int(Date().timeIntervalSince(existingSession.startedAt)))
        initializeInputs()
        // Mark sets that have real data as completed
        for exerciseLog in session.exerciseLogs {
            for setLog in exerciseLog.sets where setLog.weightKg > 0 && setLog.reps > 0 {
                completedSetIds.insert(setLog.id)
            }
        }
    }

    // MARK: - Start

    func start(
        userUnitSystem: UnitSystem,
        userDefaultRestSeconds: Int = 60
    ) async {
        guard !hasStarted else { return }
        hasStarted = true
        isLoading = true
        unitSystem = userUnitSystem
        self.userDefaultRestSeconds = userDefaultRestSeconds

        do {
            try await exerciseService.loadExercises()

            // Persist the initial session
            try await workoutService.startSession(session)

            // Load exercise details from the in-memory catalog.
            let exerciseIds = Set(session.exerciseLogs.map(\.exerciseId))
            for exerciseId in exerciseIds {
                if let exercise = exerciseService.getExercise(id: exerciseId) {
                    exerciseDetails[exerciseId] = exercise
                    // Update exercise name in logs
                    for i in session.exerciseLogs.indices where session.exerciseLogs[i].exerciseId == exerciseId {
                        session.exerciseLogs[i].exerciseName = exercise.name
                    }
                }
            }

            // Resumed sessions arrive without template context; rebuild it
            // from the plan so superset rest and progression suggestions work.
            await rebuildTemplateContextIfNeeded()

            // One bounded history fetch serves previous logs and progression
            // input for every exercise (sessions embed their logs, so a
            // per-exercise query would re-download the same documents).
            let recentLogsByExerciseId = (try? await workoutService.getRecentExerciseLogs(
                userId: userId,
                exerciseIds: exerciseIds,
                excludingSessionId: session.id,
                limit: 5
            )) ?? [:]
            for (exerciseId, recent) in recentLogsByExerciseId {
                if let mostRecent = recent.first {
                    previousLogs[exerciseId] = mostRecent
                }
            }

            computeSuggestions(recentLogs: recentLogsByExerciseId)

            // Pre-fill weights from suggestions (with previous-session fallback)
            prefillFromSuggestions()

            // Start elapsed timer
            startElapsedTimer()
        } catch {
            hasStarted = false
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    /// Resume path: `init(existingSession:)` has no template, so the group
    /// map and templateGroups start empty. Look the template back up via the
    /// session's plan. Best effort — when the plan or template is gone the
    /// session simply behaves as straight sets (the pre-existing behavior).
    private func rebuildTemplateContextIfNeeded() async {
        guard templateGroups.isEmpty, let planId = session.planId else { return }
        try? await workoutService.loadPlans(userId: userId)
        guard let plan = workoutService.plans.first(where: { $0.id == planId }),
              let template = plan.workouts.first(where: { $0.id == session.workoutTemplateId })
        else { return }
        templateGroups = template.exerciseGroups
        buildGroupMap(from: template.exerciseGroups)
    }

    // MARK: - Set Completion

    func completeSet(exerciseLogIndex: Int, setIndex: Int) async {
        guard exerciseLogIndex < session.exerciseLogs.count,
              setIndex < session.exerciseLogs[exerciseLogIndex].sets.count else { return }

        let setId = session.exerciseLogs[exerciseLogIndex].sets[setIndex].id
        var input = setInputs[setId] ?? SetInput()

        // Parse inputs, adopting the previous-session ghost values when the
        // fields were left empty (the placeholders read as "repeat last time").
        var weightDisplay = Double(input.weight) ?? 0
        var reps = Int(input.reps) ?? 0
        let rpe = Double(input.rpe)

        let exerciseId = session.exerciseLogs[exerciseLogIndex].exerciseId
        if weightDisplay <= 0 || reps <= 0,
           let prevLog = previousLogs[exerciseId], setIndex < prevLog.sets.count {
            let prevSet = prevLog.sets[setIndex]
            if weightDisplay <= 0 && prevSet.weightKg > 0 {
                weightDisplay = UnitConversionService.convertWeight(prevSet.weightKg, to: unitSystem)
                input.weight = weightDisplay.formatted(decimals: 1)
            }
            if reps <= 0 && prevSet.reps > 0 {
                reps = prevSet.reps
                input.reps = "\(prevSet.reps)"
            }
            setInputs[setId] = input
        }

        guard weightDisplay > 0 && reps > 0 else {
            Haptics.error()
            return
        }

        // Convert to kg for storage
        let weightKg = UnitConversionService.convertToKg(weightDisplay, from: unitSystem)

        // Update the set log
        session.exerciseLogs[exerciseLogIndex].sets[setIndex].weightKg = weightKg
        session.exerciseLogs[exerciseLogIndex].sets[setIndex].reps = reps
        session.exerciseLogs[exerciseLogIndex].sets[setIndex].rpe = rpe
        session.exerciseLogs[exerciseLogIndex].sets[setIndex].completedAt = Date()

        completedSetIds.insert(setId)

        // Feedback and rest start immediately; PR detection and persistence
        // follow so a slow connection never delays the gym-floor loop.
        Haptics.medium()
        let restInfo = restDuration(forExerciseLogIndex: exerciseLogIndex, setIndex: setIndex)
        if restInfo.shouldTrigger {
            restTimer.start(seconds: restInfo.seconds)
        }

        // Check for PR against the session-cached records
        let exerciseLog = session.exerciseLogs[exerciseLogIndex]
        let setLog = exerciseLog.sets[setIndex]
        if setLog.setType == .working {
            do {
                let existing = try await existingPRs(for: exerciseLog.exerciseId)
                let prs = try await progressService.checkForPRs(
                    userId: userId,
                    exerciseId: exerciseLog.exerciseId,
                    exerciseName: exerciseLog.exerciseName,
                    setLog: setLog,
                    sessionId: session.id,
                    existingPRs: existing
                )
                if !prs.isEmpty {
                    prCache[exerciseLog.exerciseId, default: []].append(contentsOf: prs)
                    session.exerciseLogs[exerciseLogIndex].sets[setIndex].isPersonalRecord = true
                    session.exerciseLogs[exerciseLogIndex].sets[setIndex].personalRecordIds = prs.map(\.id)
                    sessionPRs.append(contentsOf: prs)
                    newPR = prs.first
                    Haptics.success()
                }
            } catch {
                // PR detection is best-effort; the set itself persists below.
            }
        }

        // Persist session
        session.durationSeconds = elapsedSeconds
        do {
            try await workoutService.updateSession(session)
        } catch {
            errorMessage = "Failed to save: \(error.localizedDescription)"
        }
    }

    /// Returns (and lazily fetches) the exercise's pre-session PRs.
    private func existingPRs(for exerciseId: String) async throws -> [PersonalRecord] {
        if let cached = prCache[exerciseId] { return cached }
        let records = try await progressService.getExercisePRs(userId: userId, exerciseId: exerciseId)
        prCache[exerciseId] = records
        return records
    }

    /// Deletes the PR documents a set created and clears every piece of local
    /// PR state that references them. Every path that un-completes, resets, or
    /// removes a completed set must go through here. Works from the ids
    /// persisted on the SetLog — not `sessionPRs` — so it also covers resumed
    /// sessions where the in-memory records were never re-fetched. Deletion is
    /// best effort per record; a failed delete never blocks the edit itself.
    private func rollBackPersonalRecords(exerciseLogIndex: Int, setIndex: Int) async {
        guard exerciseLogIndex < session.exerciseLogs.count,
              setIndex < session.exerciseLogs[exerciseLogIndex].sets.count,
              let recordIds = session.exerciseLogs[exerciseLogIndex].sets[setIndex].personalRecordIds,
              !recordIds.isEmpty else { return }

        for recordId in recordIds {
            try? await progressService.deleteRecord(userId: userId, recordId: recordId)
        }

        let idSet = Set(recordIds)
        let exerciseId = session.exerciseLogs[exerciseLogIndex].exerciseId
        sessionPRs.removeAll { idSet.contains($0.id) }
        prCache[exerciseId]?.removeAll { idSet.contains($0.id) }
        if let currentPR = newPR, idSet.contains(currentPR.id) {
            newPR = nil
        }
        session.exerciseLogs[exerciseLogIndex].sets[setIndex].personalRecordIds = nil
        session.exerciseLogs[exerciseLogIndex].sets[setIndex].isPersonalRecord = false
    }

    func uncompleteSet(exerciseLogIndex: Int, setIndex: Int) async {
        guard exerciseLogIndex < session.exerciseLogs.count,
              setIndex < session.exerciseLogs[exerciseLogIndex].sets.count else { return }

        let setId = session.exerciseLogs[exerciseLogIndex].sets[setIndex].id
        completedSetIds.remove(setId)

        // Roll back exactly the records this set created (identity-based via
        // the ids stamped on the set, so it works on resumed sessions and
        // equal-weight sets can't delete each other's PRs).
        await rollBackPersonalRecords(exerciseLogIndex: exerciseLogIndex, setIndex: setIndex)

        session.exerciseLogs[exerciseLogIndex].sets[setIndex].weightKg = 0
        session.exerciseLogs[exerciseLogIndex].sets[setIndex].reps = 0
        session.exerciseLogs[exerciseLogIndex].sets[setIndex].rpe = nil
        session.exerciseLogs[exerciseLogIndex].sets[setIndex].isPersonalRecord = false
        session.exerciseLogs[exerciseLogIndex].sets[setIndex].personalRecordIds = nil
        session.exerciseLogs[exerciseLogIndex].sets[setIndex].completedAt = nil

        setInputs[setId] = SetInput()

        session.durationSeconds = elapsedSeconds
        do {
            try await workoutService.updateSession(session)
        } catch {
            errorMessage = "Failed to save: \(error.localizedDescription)"
        }
    }

    // MARK: - Set Management

    func addSet(exerciseLogIndex: Int) {
        guard exerciseLogIndex < session.exerciseLogs.count else { return }

        let currentSets = session.exerciseLogs[exerciseLogIndex].sets
        let newSetNumber = (currentSets.last?.setNumber ?? 0) + 1

        let newSet = SetLog(
            id: UUID().uuidString,
            setNumber: newSetNumber,
            setType: .working,
            weightKg: 0,
            reps: 0,
            rpe: nil,
            isPersonalRecord: false,
            completedAt: nil
        )
        session.exerciseLogs[exerciseLogIndex].sets.append(newSet)
        setInputs[newSet.id] = SetInput()
    }

    func removeSet(exerciseLogIndex: Int, setIndex: Int) async {
        guard exerciseLogIndex < session.exerciseLogs.count,
              session.exerciseLogs[exerciseLogIndex].sets.count > 1,
              setIndex < session.exerciseLogs[exerciseLogIndex].sets.count else { return }

        // A removed set's PRs must not outlive it.
        await rollBackPersonalRecords(exerciseLogIndex: exerciseLogIndex, setIndex: setIndex)

        let setId = session.exerciseLogs[exerciseLogIndex].sets[setIndex].id
        completedSetIds.remove(setId)
        session.exerciseLogs[exerciseLogIndex].sets.remove(at: setIndex)
        setInputs.removeValue(forKey: setId)

        // Renumber
        for i in session.exerciseLogs[exerciseLogIndex].sets.indices {
            session.exerciseLogs[exerciseLogIndex].sets[i].setNumber = i + 1
        }
    }

    func updateSetType(exerciseLogIndex: Int, setIndex: Int, newType: SetType) {
        guard exerciseLogIndex < session.exerciseLogs.count,
              setIndex < session.exerciseLogs[exerciseLogIndex].sets.count else { return }
        session.exerciseLogs[exerciseLogIndex].sets[setIndex].setType = newType
    }

    // MARK: - Exercise Swap

    func requestSwap(exerciseLogIndex: Int) {
        swapTargetExerciseLogIndex = exerciseLogIndex
        showingExerciseSwap = true
    }

    func swapExercise(newExercise: Exercise) async {
        guard let index = swapTargetExerciseLogIndex,
              index < session.exerciseLogs.count else { return }

        let oldExerciseId = session.exerciseLogs[index].exerciseId

        // Swapping resets every set, so any PRs those sets earned must be
        // deleted first (while the log still carries the old exerciseId).
        for setIndex in session.exerciseLogs[index].sets.indices {
            await rollBackPersonalRecords(exerciseLogIndex: index, setIndex: setIndex)
        }

        // Update exercise info
        session.exerciseLogs[index].exerciseId = newExercise.id
        session.exerciseLogs[index].exerciseName = newExercise.name
        exerciseDetails[newExercise.id] = newExercise

        // Reset sets and their inputs
        for setIndex in session.exerciseLogs[index].sets.indices {
            let setId = session.exerciseLogs[index].sets[setIndex].id
            completedSetIds.remove(setId)
            session.exerciseLogs[index].sets[setIndex].weightKg = 0
            session.exerciseLogs[index].sets[setIndex].reps = 0
            session.exerciseLogs[index].sets[setIndex].rpe = nil
            session.exerciseLogs[index].sets[setIndex].isPersonalRecord = false
            session.exerciseLogs[index].sets[setIndex].personalRecordIds = nil
            session.exerciseLogs[index].sets[setIndex].completedAt = nil
            setInputs[setId] = SetInput()
        }

        previousLogs.removeValue(forKey: oldExerciseId)
        progressionSuggestions.removeValue(forKey: oldExerciseId)
        do {
            let recentByExercise = try await workoutService.getRecentExerciseLogs(
                userId: userId,
                exerciseIds: [newExercise.id],
                excludingSessionId: session.id,
                limit: 5
            )
            let recent = recentByExercise[newExercise.id] ?? []
            if let mostRecent = recent.first {
                previousLogs[newExercise.id] = mostRecent
            }
            // Recompute the suggestion for just the new exerciseId
            if let planned = plannedExercise(for: newExercise.id), !recent.isEmpty,
               let suggestion = progressionService.suggest(
                   for: planned,
                   previousLogs: recent,
                   exerciseInfo: exerciseDetails[newExercise.id]
               ) {
                progressionSuggestions[newExercise.id] = suggestion
            }
        } catch {}

        // Persist
        do {
            try await workoutService.updateSession(session)
        } catch {
            errorMessage = "Failed to save swap: \(error.localizedDescription)"
        }

        swapTargetExerciseLogIndex = nil
    }

    // MARK: - Rest Timer (delegated to RestTimerController)

    func startRestTimer(seconds: Int) {
        restTimer.start(seconds: seconds)
    }

    func skipRestTimer() {
        restTimer.skip()
    }

    func adjustRestTimer(by seconds: Int) {
        restTimer.adjust(by: seconds)
    }

    /// Re-syncs displayed timer values from the wall clock. Called when the
    /// app returns to the foreground, since Timers suspend in the background.
    func refreshTimersFromWallClock() {
        elapsedSeconds = max(0, Int(Date().timeIntervalSince(session.startedAt)))
        restTimer.refreshFromWallClock()
    }

    // MARK: - Finish / Abandon

    func finishWorkout() async {
        stopTimers()
        session.durationSeconds = elapsedSeconds

        do {
            session = try await workoutService.completeSession(session)
            showingSummary = true
        } catch {
            errorMessage = "Failed to complete workout: \(error.localizedDescription)"
        }
    }

    func abandonWorkout() async {
        stopTimers()
        session.durationSeconds = elapsedSeconds

        // An abandoned session's sets don't count, so its PRs must not stick
        // around either. Collect ids from the sets (survives resume, when
        // sessionPRs is empty) plus anything in memory. Best effort per
        // record; deletion failures shouldn't block abandoning the session.
        var recordIds = Set(sessionPRs.map(\.id))
        for log in session.exerciseLogs {
            for set in log.sets {
                recordIds.formUnion(set.personalRecordIds ?? [])
            }
        }
        for recordId in recordIds {
            try? await progressService.deleteRecord(userId: userId, recordId: recordId)
        }
        sessionPRs.removeAll()
        newPR = nil

        do {
            try await workoutService.abandonSession(session)
        } catch {
            errorMessage = "Failed to abandon workout: \(error.localizedDescription)"
        }
    }

    func saveMoodAndNotes(mood: Int?, notes: String?) async {
        session.mood = mood
        session.notes = notes
        do {
            try await workoutService.updateSession(session)
        } catch {}
    }

    func stopTimers() {
        elapsedTimer?.invalidate()
        elapsedTimer = nil
        restTimer.stop()
    }

    // MARK: - Computed Properties

    var completedSetsCount: Int {
        completedSetIds.count
    }

    var totalSetsCount: Int {
        session.exerciseLogs.reduce(0) { $0 + $1.sets.count }
    }

    var progressFraction: Double {
        guard totalSetsCount > 0 else { return 0 }
        return Double(completedSetsCount) / Double(totalSetsCount)
    }

    var elapsedFormatted: String {
        Formatters.elapsedString(from: elapsedSeconds)
    }

    var isAnySetCompleted: Bool {
        !completedSetIds.isEmpty
    }

    // MARK: - Private Helpers

    private func buildGroupMap(from groups: [ExerciseGroup]) {
        exerciseGroupMap.removeAll()
        var logIndex = 0
        for (groupIndex, group) in groups.enumerated() {
            for _ in group.exercises {
                exerciseGroupMap[logIndex] = groupIndex
                logIndex += 1
            }
        }
    }

    private func initializeInputs() {
        setInputs.removeAll()
        for log in session.exerciseLogs {
            for set in log.sets {
                var input = SetInput()
                if set.weightKg > 0 {
                    input.weight = UnitConversionService.convertWeight(set.weightKg, to: unitSystem).formatted(decimals: 1)
                }
                if set.reps > 0 {
                    input.reps = "\(set.reps)"
                }
                if let rpe = set.rpe {
                    input.rpe = rpe.formatted(decimals: 1)
                }
                setInputs[set.id] = input
            }
        }
    }

    private func convertWeightInputs(from oldUnit: UnitSystem, to newUnit: UnitSystem) {
        for (setId, input) in setInputs {
            guard let oldValue = Double(input.weight), oldValue > 0 else { continue }
            let kg = UnitConversionService.convertToKg(oldValue, from: oldUnit)
            let newValue = UnitConversionService.convertWeight(kg, to: newUnit)
            setInputs[setId]?.weight = newValue.formatted(decimals: 1)
        }
    }

    /// Pure helper: given recent logs per exerciseId, populate
    /// `progressionSuggestions` by routing each through `ProgressionService`.
    /// Exposed (not private) so tests can drive it directly without async I/O.
    func computeSuggestions(recentLogs: [String: [ExerciseLog]]) {
        progressionSuggestions.removeAll()
        let seenExerciseIds = Set(session.exerciseLogs.map(\.exerciseId))
        for exerciseId in seenExerciseIds {
            guard let logs = recentLogs[exerciseId], !logs.isEmpty,
                  let planned = plannedExercise(for: exerciseId) else { continue }
            if let suggestion = progressionService.suggest(
                for: planned,
                previousLogs: logs,
                exerciseInfo: exerciseDetails[exerciseId]
            ) {
                progressionSuggestions[exerciseId] = suggestion
            }
        }
    }

    func plannedExercise(for exerciseId: String) -> PlannedExercise? {
        for group in templateGroups {
            if let p = group.exercises.first(where: { $0.exerciseId == exerciseId }) {
                return p
            }
        }
        return nil
    }

    private func prefillFromSuggestions() {
        for i in session.exerciseLogs.indices {
            let exerciseId = session.exerciseLogs[i].exerciseId
            let suggestion = progressionSuggestions[exerciseId]
            let prevLog = previousLogs[exerciseId]

            for j in session.exerciseLogs[i].sets.indices {
                guard session.exerciseLogs[i].sets[j].weightKg == 0 else { continue }

                // Priority: suggestion's weight > previous session's weight at same set index > empty
                var weightKg: Double = 0
                if let s = suggestion, s.suggestedWeight > 0 {
                    weightKg = s.suggestedWeight
                } else if let prev = prevLog, j < prev.sets.count {
                    weightKg = prev.sets[j].weightKg
                }

                if weightKg > 0 {
                    let displayWeight = UnitConversionService.convertWeight(weightKg, to: unitSystem)
                    setInputs[session.exerciseLogs[i].sets[j].id, default: SetInput()].weight = displayWeight.formatted(decimals: 1)
                }
            }
        }
    }

    private func startElapsedTimer() {
        elapsedTimer?.invalidate()
        // Derives from startedAt instead of counting ticks, and deliberately
        // does NOT touch `session` — mutating it here re-rendered every
        // exercise card once per second for the whole workout.
        // `durationSeconds` is stamped at each persistence point instead.
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            MainActor.assumeIsolated {
                self.elapsedSeconds = max(0, Int(Date().timeIntervalSince(self.session.startedAt)))
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        elapsedTimer = timer
    }

    func restDuration(forExerciseLogIndex exerciseLogIndex: Int, setIndex: Int) -> (shouldTrigger: Bool, seconds: Int) {
        let exerciseLog = session.exerciseLogs[exerciseLogIndex]

        // For straight sets, always trigger rest
        if exerciseLog.groupType == .straight {
            // Check if this is the last set — no rest after last set of exercise
            let isLastSet = setIndex == exerciseLog.sets.count - 1
            let allCompleted = exerciseLog.sets.allSatisfy { completedSetIds.contains($0.id) }
            if isLastSet && allCompleted { return (false, 0) }

            guard let groupIndex = exerciseGroupMap[exerciseLogIndex],
                  groupIndex < templateGroups.count else {
                return (true, userDefaultRestSeconds)
            }
            let group = templateGroups[groupIndex]
            let planned = group.exercises.first { $0.exerciseId == exerciseLog.exerciseId }
            return (true, planned?.restSeconds ?? userDefaultRestSeconds)
        }

        // For supersets/circuits: rest only after all exercises in the group complete the current round
        guard let groupIndex = exerciseGroupMap[exerciseLogIndex] else {
            return (true, userDefaultRestSeconds)
        }

        // Find all exercise log indices in this group
        let groupLogIndices = exerciseGroupMap.filter { $0.value == groupIndex }.map(\.key).sorted()

        // The current "round" is the set index (set 0 = round 0, etc.)
        let round = setIndex

        // Check if all exercises in the group have completed this round
        for logIndex in groupLogIndices {
            guard logIndex < session.exerciseLogs.count,
                  round < session.exerciseLogs[logIndex].sets.count else { continue }
            let setId = session.exerciseLogs[logIndex].sets[round].id
            if !completedSetIds.contains(setId) {
                return (false, 0) // Not all exercises done for this round
            }
        }

        // All done for this round — trigger rest
        let group = templateGroups[groupIndex]
        let restSeconds = group.restBetweenRoundsSeconds ?? userDefaultRestSeconds
        return (true, restSeconds)
    }

    // MARK: - Group Info Helpers

    func groupIndex(for exerciseLogIndex: Int) -> Int? {
        exerciseGroupMap[exerciseLogIndex]
    }

    func exerciseLogIndices(forGroupIndex groupIndex: Int) -> [Int] {
        exerciseGroupMap.filter { $0.value == groupIndex }.map(\.key).sorted()
    }

    func isFirstInGroup(_ exerciseLogIndex: Int) -> Bool {
        guard let gi = exerciseGroupMap[exerciseLogIndex] else { return true }
        let indices = exerciseLogIndices(forGroupIndex: gi)
        return indices.first == exerciseLogIndex
    }

    func groupType(for exerciseLogIndex: Int) -> GroupType {
        guard let gi = exerciseGroupMap[exerciseLogIndex],
              gi < templateGroups.count else { return .straight }
        return templateGroups[gi].groupType
    }
}
