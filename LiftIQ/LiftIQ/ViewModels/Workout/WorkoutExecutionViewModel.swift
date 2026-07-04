import Foundation
import Observation
import UserNotifications

@MainActor
@Observable
final class WorkoutExecutionViewModel: Identifiable {
    let id = UUID().uuidString

    // MARK: - Session State

    var session: WorkoutSession
    var exerciseDetails: [String: Exercise] = [:]
    var previousLogs: [String: ExerciseLog] = [:]
    var progressionSuggestions: [String: ProgressionSuggestion] = [:]

    // ProgressionService is stateless; owning an instance here keeps the VM
    // testable without DI plumbing through start(...).
    let progressionService = ProgressionService()

    // MARK: - Input State (parallel arrays for TextField bindings)

    var weightInputs: [[String]] = []
    var repsInputs: [[String]] = []
    var rpeInputs: [[String]] = []

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

    var restTimerActive = false
    var restSecondsRemaining: Int = 0
    var restTotalSeconds: Int = 0

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

    // Both timers derive their displayed values from wall-clock dates so the
    // countdown survives backgrounding (foreground Timers suspend).
    private var elapsedTimer: Timer?
    private var restTimer: Timer?
    private var restEndDate: Date?
    private var hasStarted = false
    private static let restNotificationId = "liftiq.rest-timer-complete"

    // MARK: - Init (new session from template)

    init(template: WorkoutTemplate, userId: String, planId: String?) {
        self.session = Self.createSession(from: template, userId: userId, planId: planId)
        self.templateGroups = template.exerciseGroups
        buildGroupMap(from: template)
        initializeInputArrays()
    }

    // MARK: - Init (resume existing session)

    init(existingSession: WorkoutSession) {
        self.session = existingSession
        self.elapsedSeconds = max(0, Int(Date().timeIntervalSince(existingSession.startedAt)))
        initializeInputArrays()
        // Mark sets that have real data as completed
        for exerciseLog in session.exerciseLogs {
            for setLog in exerciseLog.sets where setLog.weightKg > 0 && setLog.reps > 0 {
                completedSetIds.insert(setLog.id)
            }
        }
    }

    // MARK: - Session Creation

    static func createSession(from template: WorkoutTemplate, userId: String, planId: String?) -> WorkoutSession {
        var exerciseLogs: [ExerciseLog] = []
        var order = 0

        for group in template.exerciseGroups {
            for planned in group.exercises {
                var sets: [SetLog] = []
                for setNum in 1...planned.sets {
                    sets.append(SetLog(
                        id: UUID().uuidString,
                        setNumber: setNum,
                        setType: .working,
                        weightKg: 0,
                        reps: 0,
                        rpe: nil,
                        isPersonalRecord: false,
                        completedAt: nil
                    ))
                }

                let fallbackName = planned.exerciseId
                    .replacingOccurrences(of: "_", with: " ")
                    .replacingOccurrences(of: "-", with: " ")
                    .capitalized

                exerciseLogs.append(ExerciseLog(
                    id: UUID().uuidString,
                    sessionId: "",
                    exerciseId: planned.exerciseId,
                    exerciseName: fallbackName,
                    order: order,
                    groupType: group.groupType,
                    sets: sets,
                    notes: nil
                ))
                order += 1
            }
        }

        let sessionId = UUID().uuidString
        // Backfill sessionId into exercise logs
        for i in exerciseLogs.indices {
            exerciseLogs[i].sessionId = sessionId
        }

        return WorkoutSession(
            id: sessionId,
            userId: userId,
            planId: planId,
            workoutTemplateId: template.id,
            workoutName: template.name,
            startedAt: Date(),
            completedAt: nil,
            status: .inProgress,
            exerciseLogs: exerciseLogs,
            durationSeconds: 0,
            notes: nil,
            mood: nil
        )
    }

    // MARK: - Start

    func start(
        workoutService: WorkoutService,
        exerciseService: ExerciseService,
        progressService: ProgressService,
        userId: String,
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

    // MARK: - Set Completion

    func completeSet(
        exerciseLogIndex: Int,
        setIndex: Int,
        workoutService: WorkoutService,
        progressService: ProgressService,
        userId: String
    ) async {
        guard exerciseLogIndex < session.exerciseLogs.count,
              setIndex < session.exerciseLogs[exerciseLogIndex].sets.count else { return }

        // Parse inputs, adopting the previous-session ghost values when the
        // fields were left empty (the placeholders read as "repeat last time").
        var weightDisplay = Double(weightInputs[exerciseLogIndex][setIndex]) ?? 0
        var reps = Int(repsInputs[exerciseLogIndex][setIndex]) ?? 0
        let rpe = Double(rpeInputs[exerciseLogIndex][setIndex])

        let exerciseId = session.exerciseLogs[exerciseLogIndex].exerciseId
        if weightDisplay <= 0 || reps <= 0,
           let prevLog = previousLogs[exerciseId], setIndex < prevLog.sets.count {
            let prevSet = prevLog.sets[setIndex]
            if weightDisplay <= 0 && prevSet.weightKg > 0 {
                weightDisplay = UnitConversionService.convertWeight(prevSet.weightKg, to: unitSystem)
                weightInputs[exerciseLogIndex][setIndex] = weightDisplay.formatted(decimals: 1)
            }
            if reps <= 0 && prevSet.reps > 0 {
                reps = prevSet.reps
                repsInputs[exerciseLogIndex][setIndex] = "\(prevSet.reps)"
            }
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

        let setId = session.exerciseLogs[exerciseLogIndex].sets[setIndex].id
        completedSetIds.insert(setId)

        // Feedback and rest start immediately; PR detection and persistence
        // follow so a slow connection never delays the gym-floor loop.
        Haptics.medium()
        let restInfo = restDuration(forExerciseLogIndex: exerciseLogIndex, setIndex: setIndex)
        if restInfo.shouldTrigger {
            startRestTimer(seconds: restInfo.seconds)
        }

        // Check for PR against the session-cached records
        let exerciseLog = session.exerciseLogs[exerciseLogIndex]
        let setLog = exerciseLog.sets[setIndex]
        if setLog.setType == .working {
            do {
                let existing = try await existingPRs(
                    for: exerciseLog.exerciseId,
                    userId: userId,
                    progressService: progressService
                )
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
    private func existingPRs(for exerciseId: String, userId: String, progressService: ProgressService) async throws -> [PersonalRecord] {
        if let cached = prCache[exerciseId] { return cached }
        let records = try await progressService.getExercisePRs(userId: userId, exerciseId: exerciseId)
        prCache[exerciseId] = records
        return records
    }

    func uncompleteSet(
        exerciseLogIndex: Int,
        setIndex: Int,
        workoutService: WorkoutService,
        progressService: ProgressService
    ) async {
        guard exerciseLogIndex < session.exerciseLogs.count,
              setIndex < session.exerciseLogs[exerciseLogIndex].sets.count else { return }

        let exerciseLog = session.exerciseLogs[exerciseLogIndex]
        let setLog = exerciseLog.sets[setIndex]
        let setId = session.exerciseLogs[exerciseLogIndex].sets[setIndex].id
        completedSetIds.remove(setId)

        if setLog.isPersonalRecord {
            let recordsToDelete = sessionPRs.filter { pr in
                pr.sessionId == session.id &&
                pr.exerciseId == exerciseLog.exerciseId &&
                ((pr.type == .weight && abs(pr.value - setLog.weightKg) < 0.001) ||
                 (pr.type == .estimated1RM && abs(pr.value - setLog.estimated1RM) < 0.001))
            }

            for record in recordsToDelete {
                try? await progressService.deleteRecord(record)
            }

            let recordIds = Set(recordsToDelete.map(\.id))
            sessionPRs.removeAll { recordIds.contains($0.id) }
            prCache[exerciseLog.exerciseId]?.removeAll { recordIds.contains($0.id) }
            if let currentPR = newPR, recordIds.contains(currentPR.id) {
                newPR = nil
            }
        }

        session.exerciseLogs[exerciseLogIndex].sets[setIndex].weightKg = 0
        session.exerciseLogs[exerciseLogIndex].sets[setIndex].reps = 0
        session.exerciseLogs[exerciseLogIndex].sets[setIndex].rpe = nil
        session.exerciseLogs[exerciseLogIndex].sets[setIndex].isPersonalRecord = false
        session.exerciseLogs[exerciseLogIndex].sets[setIndex].completedAt = nil

        weightInputs[exerciseLogIndex][setIndex] = ""
        repsInputs[exerciseLogIndex][setIndex] = ""
        rpeInputs[exerciseLogIndex][setIndex] = ""

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

        session.exerciseLogs[exerciseLogIndex].sets.append(SetLog(
            id: UUID().uuidString,
            setNumber: newSetNumber,
            setType: .working,
            weightKg: 0,
            reps: 0,
            rpe: nil,
            isPersonalRecord: false,
            completedAt: nil
        ))

        weightInputs[exerciseLogIndex].append("")
        repsInputs[exerciseLogIndex].append("")
        rpeInputs[exerciseLogIndex].append("")
    }

    func removeSet(exerciseLogIndex: Int, setIndex: Int) {
        guard exerciseLogIndex < session.exerciseLogs.count,
              session.exerciseLogs[exerciseLogIndex].sets.count > 1,
              setIndex < session.exerciseLogs[exerciseLogIndex].sets.count else { return }

        let setId = session.exerciseLogs[exerciseLogIndex].sets[setIndex].id
        completedSetIds.remove(setId)
        session.exerciseLogs[exerciseLogIndex].sets.remove(at: setIndex)
        weightInputs[exerciseLogIndex].remove(at: setIndex)
        repsInputs[exerciseLogIndex].remove(at: setIndex)
        rpeInputs[exerciseLogIndex].remove(at: setIndex)

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

    func swapExercise(
        newExercise: Exercise,
        workoutService: WorkoutService,
        userId: String
    ) async {
        guard let index = swapTargetExerciseLogIndex,
              index < session.exerciseLogs.count else { return }

        let oldExerciseId = session.exerciseLogs[index].exerciseId

        // Update exercise info
        session.exerciseLogs[index].exerciseId = newExercise.id
        session.exerciseLogs[index].exerciseName = newExercise.name
        exerciseDetails[newExercise.id] = newExercise

        // Reset sets
        for setIndex in session.exerciseLogs[index].sets.indices {
            let setId = session.exerciseLogs[index].sets[setIndex].id
            completedSetIds.remove(setId)
            session.exerciseLogs[index].sets[setIndex].weightKg = 0
            session.exerciseLogs[index].sets[setIndex].reps = 0
            session.exerciseLogs[index].sets[setIndex].rpe = nil
            session.exerciseLogs[index].sets[setIndex].isPersonalRecord = false
            session.exerciseLogs[index].sets[setIndex].completedAt = nil
        }

        // Reset inputs
        let setCount = session.exerciseLogs[index].sets.count
        weightInputs[index] = Array(repeating: "", count: setCount)
        repsInputs[index] = Array(repeating: "", count: setCount)
        rpeInputs[index] = Array(repeating: "", count: setCount)

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

    // MARK: - Rest Timer

    func startRestTimer(seconds: Int) {
        guard seconds > 0 else { return }
        restTimer?.invalidate()
        restEndDate = Date().addingTimeInterval(TimeInterval(seconds))
        restSecondsRemaining = seconds
        restTotalSeconds = seconds
        restTimerActive = true
        scheduleRestEndNotification(after: seconds)

        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            MainActor.assumeIsolated {
                self.tickRestTimer()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        restTimer = timer
    }

    private func tickRestTimer() {
        guard let endDate = restEndDate else {
            restTimer?.invalidate()
            return
        }
        let remaining = max(0, Int(endDate.timeIntervalSinceNow.rounded(.up)))
        restSecondsRemaining = remaining
        if remaining <= 0 {
            restTimer?.invalidate()
            restEndDate = nil
            restTimerActive = false
            Haptics.success()
        }
    }

    func skipRestTimer() {
        restTimer?.invalidate()
        restEndDate = nil
        restSecondsRemaining = 0
        restTimerActive = false
        cancelRestEndNotification()
    }

    func adjustRestTimer(by seconds: Int) {
        guard let endDate = restEndDate else { return }
        let newEnd = endDate.addingTimeInterval(TimeInterval(seconds))
        let remaining = max(0, Int(newEnd.timeIntervalSinceNow.rounded(.up)))
        if remaining <= 0 {
            skipRestTimer()
            return
        }
        restEndDate = newEnd
        restSecondsRemaining = remaining
        restTotalSeconds = max(restTotalSeconds, remaining)
        scheduleRestEndNotification(after: remaining)
    }

    /// Re-syncs displayed timer values from the wall clock. Called when the
    /// app returns to the foreground, since Timers suspend in the background.
    func refreshTimersFromWallClock() {
        elapsedSeconds = max(0, Int(Date().timeIntervalSince(session.startedAt)))
        if restTimerActive {
            tickRestTimer()
        }
    }

    // MARK: - Rest-End Notification

    private func scheduleRestEndNotification(after seconds: Int) {
        guard seconds > 0 else { return }
        let identifier = Self.restNotificationId
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = "Rest complete"
            content.body = "Time for your next set."
            content.sound = .default
            let trigger = UNTimeIntervalNotificationTrigger(
                timeInterval: TimeInterval(seconds),
                repeats: false
            )
            UNUserNotificationCenter.current()
                .add(UNNotificationRequest(identifier: identifier, content: content, trigger: trigger))
        }
    }

    private func cancelRestEndNotification() {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [Self.restNotificationId])
    }

    // MARK: - Finish / Abandon

    func finishWorkout(workoutService: WorkoutService) async {
        stopTimers()
        session.durationSeconds = elapsedSeconds

        do {
            session = try await workoutService.completeSession(session)
            showingSummary = true
        } catch {
            errorMessage = "Failed to complete workout: \(error.localizedDescription)"
        }
    }

    func abandonWorkout(workoutService: WorkoutService) async {
        stopTimers()
        session.durationSeconds = elapsedSeconds

        do {
            try await workoutService.abandonSession(session)
        } catch {
            errorMessage = "Failed to abandon workout: \(error.localizedDescription)"
        }
    }

    func saveMoodAndNotes(mood: Int?, notes: String?, workoutService: WorkoutService) async {
        session.mood = mood
        session.notes = notes
        do {
            try await workoutService.updateSession(session)
        } catch {}
    }

    func stopTimers() {
        elapsedTimer?.invalidate()
        elapsedTimer = nil
        restTimer?.invalidate()
        restTimer = nil
        restEndDate = nil
        cancelRestEndNotification()
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
        Formatters.durationString(from: elapsedSeconds)
    }

    var isAnySetCompleted: Bool {
        !completedSetIds.isEmpty
    }

    // MARK: - Private Helpers

    private func buildGroupMap(from template: WorkoutTemplate) {
        var logIndex = 0
        for (groupIndex, group) in template.exerciseGroups.enumerated() {
            for _ in group.exercises {
                exerciseGroupMap[logIndex] = groupIndex
                logIndex += 1
            }
        }
    }

    private func initializeInputArrays() {
        weightInputs = session.exerciseLogs.map { log in
            log.sets.map { set in
                set.weightKg > 0 ? "\(UnitConversionService.convertWeight(set.weightKg, to: unitSystem).formatted(decimals: 1))" : ""
            }
        }
        repsInputs = session.exerciseLogs.map { log in
            log.sets.map { set in
                set.reps > 0 ? "\(set.reps)" : ""
            }
        }
        rpeInputs = session.exerciseLogs.map { log in
            log.sets.map { set in
                if let rpe = set.rpe { return "\(rpe.formatted(decimals: 1))" }
                return ""
            }
        }
    }

    private func convertWeightInputs(from oldUnit: UnitSystem, to newUnit: UnitSystem) {
        guard !weightInputs.isEmpty else { return }

        for exerciseIndex in weightInputs.indices {
            for setIndex in weightInputs[exerciseIndex].indices {
                guard let oldValue = Double(weightInputs[exerciseIndex][setIndex]), oldValue > 0 else { continue }
                let kg = UnitConversionService.convertToKg(oldValue, from: oldUnit)
                let newValue = UnitConversionService.convertWeight(kg, to: newUnit)
                weightInputs[exerciseIndex][setIndex] = newValue.formatted(decimals: 1)
            }
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
                    weightInputs[i][j] = displayWeight.formatted(decimals: 1)
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
