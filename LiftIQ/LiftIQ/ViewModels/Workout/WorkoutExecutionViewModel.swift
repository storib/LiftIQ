import Foundation
import Observation

@Observable
final class WorkoutExecutionViewModel: Identifiable {
    let id = UUID().uuidString

    // MARK: - Session State

    var session: WorkoutSession
    var exerciseDetails: [String: Exercise] = [:]
    var previousLogs: [String: ExerciseLog] = [:]

    // MARK: - Input State (parallel arrays for TextField bindings)

    var weightInputs: [[String]] = []
    var repsInputs: [[String]] = []
    var rpeInputs: [[String]] = []

    // MARK: - UI State

    var isLoading = false
    var errorMessage: String?
    var elapsedSeconds: Int = 0
    var unitSystem: UnitSystem = .metric {
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

    // MARK: - Navigation

    var showingSummary = false
    var showingExerciseSwap = false
    var showingAbandonConfirmation = false
    var swapTargetExerciseLogIndex: Int?

    // MARK: - Group Mapping (for superset rest logic)

    var exerciseGroupMap: [Int: Int] = [:]   // exerciseLogIndex -> group index
    var templateGroups: [ExerciseGroup] = []

    // MARK: - Timers

    private var elapsedTimer: Timer?
    private var restTimer: Timer?
    private var hasStarted = false

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
        userUnitSystem: UnitSystem
    ) async {
        guard !hasStarted else { return }
        hasStarted = true
        isLoading = true
        unitSystem = userUnitSystem

        do {
            try await exerciseService.loadExercises()

            // Persist the initial session
            try await workoutService.startSession(session)

            // Load exercise details and previous logs
            let exerciseIds = Set(session.exerciseLogs.map(\.exerciseId))
            for exerciseId in exerciseIds {
                if let exercise = exerciseService.getExercise(id: exerciseId) {
                    exerciseDetails[exerciseId] = exercise
                    // Update exercise name in logs
                    for i in session.exerciseLogs.indices where session.exerciseLogs[i].exerciseId == exerciseId {
                        session.exerciseLogs[i].exerciseName = exercise.name
                    }
                }

                if let previousLog = try await workoutService.getPreviousExerciseLog(userId: userId, exerciseId: exerciseId) {
                    previousLogs[exerciseId] = previousLog
                }
            }

            // Pre-fill weights from previous session
            prefillFromPreviousSession()

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

        // Parse inputs
        let weightDisplay = Double(weightInputs[exerciseLogIndex][setIndex]) ?? 0
        let reps = Int(repsInputs[exerciseLogIndex][setIndex]) ?? 0
        let rpe = Double(rpeInputs[exerciseLogIndex][setIndex])

        guard weightDisplay > 0 && reps > 0 else { return }

        // Convert to kg for storage
        let weightKg = UnitConversionService.convertToKg(weightDisplay, from: unitSystem)

        // Update the set log
        session.exerciseLogs[exerciseLogIndex].sets[setIndex].weightKg = weightKg
        session.exerciseLogs[exerciseLogIndex].sets[setIndex].reps = reps
        session.exerciseLogs[exerciseLogIndex].sets[setIndex].rpe = rpe
        session.exerciseLogs[exerciseLogIndex].sets[setIndex].completedAt = Date()

        let setId = session.exerciseLogs[exerciseLogIndex].sets[setIndex].id
        completedSetIds.insert(setId)

        // Check for PR
        let exerciseLog = session.exerciseLogs[exerciseLogIndex]
        let setLog = exerciseLog.sets[setIndex]
        if setLog.setType == .working {
            do {
                let prs = try await progressService.checkForPRs(
                    userId: userId,
                    exerciseId: exerciseLog.exerciseId,
                    exerciseName: exerciseLog.exerciseName,
                    setLog: setLog,
                    sessionId: session.id
                )
                if !prs.isEmpty {
                    session.exerciseLogs[exerciseLogIndex].sets[setIndex].isPersonalRecord = true
                    sessionPRs.append(contentsOf: prs)
                    newPR = prs.first
                    Haptics.success()
                } else {
                    Haptics.medium()
                }
            } catch {
                Haptics.medium()
            }
        } else {
            Haptics.medium()
        }

        // Persist session
        session.durationSeconds = elapsedSeconds
        do {
            try await workoutService.updateSession(session)
        } catch {
            errorMessage = "Failed to save: \(error.localizedDescription)"
        }

        // Start rest timer
        let restInfo = restDuration(forExerciseLogIndex: exerciseLogIndex, setIndex: setIndex)
        if restInfo.shouldTrigger {
            startRestTimer(seconds: restInfo.seconds)
        }
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
        do {
            if let prevLog = try await workoutService.getPreviousExerciseLog(userId: userId, exerciseId: newExercise.id) {
                previousLogs[newExercise.id] = prevLog
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
        restSecondsRemaining = seconds
        restTotalSeconds = seconds
        restTimerActive = true

        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            if self.restSecondsRemaining > 0 {
                self.restSecondsRemaining -= 1
            }
            if self.restSecondsRemaining <= 0 {
                timer.invalidate()
                self.restTimerActive = false
                Haptics.success()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        restTimer = timer
    }

    func skipRestTimer() {
        restTimer?.invalidate()
        restSecondsRemaining = 0
        restTimerActive = false
    }

    func adjustRestTimer(by seconds: Int) {
        restSecondsRemaining = max(0, restSecondsRemaining + seconds)
        restTotalSeconds = max(restTotalSeconds, restSecondsRemaining)
        if restSecondsRemaining <= 0 {
            skipRestTimer()
        }
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

    private func prefillFromPreviousSession() {
        for i in session.exerciseLogs.indices {
            let exerciseId = session.exerciseLogs[i].exerciseId
            guard let prevLog = previousLogs[exerciseId] else { continue }

            for j in session.exerciseLogs[i].sets.indices {
                guard j < prevLog.sets.count,
                      session.exerciseLogs[i].sets[j].weightKg == 0 else { continue }

                let prevSet = prevLog.sets[j]
                let displayWeight = UnitConversionService.convertWeight(prevSet.weightKg, to: unitSystem)
                weightInputs[i][j] = displayWeight > 0 ? "\(displayWeight.formatted(decimals: 1))" : ""
            }
        }
    }

    private func startElapsedTimer() {
        elapsedTimer?.invalidate()
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            self.elapsedSeconds += 1
            self.session.durationSeconds = self.elapsedSeconds
        }
        RunLoop.main.add(timer, forMode: .common)
        elapsedTimer = timer
    }

    private func restDuration(forExerciseLogIndex exerciseLogIndex: Int, setIndex: Int) -> (shouldTrigger: Bool, seconds: Int) {
        let exerciseLog = session.exerciseLogs[exerciseLogIndex]

        // For straight sets, always trigger rest
        if exerciseLog.groupType == .straight {
            // Check if this is the last set — no rest after last set of exercise
            let isLastSet = setIndex == exerciseLog.sets.count - 1
            let allCompleted = exerciseLog.sets.allSatisfy { completedSetIds.contains($0.id) }
            if isLastSet && allCompleted { return (false, 0) }

            guard let groupIndex = exerciseGroupMap[exerciseLogIndex],
                  groupIndex < templateGroups.count else {
                return (true, Constants.defaultRestSeconds)
            }
            let group = templateGroups[groupIndex]
            let planned = group.exercises.first { $0.exerciseId == exerciseLog.exerciseId }
            return (true, planned?.restSeconds ?? Constants.defaultRestSeconds)
        }

        // For supersets/circuits: rest only after all exercises in the group complete the current round
        guard let groupIndex = exerciseGroupMap[exerciseLogIndex] else {
            return (true, Constants.defaultRestSeconds)
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
        let restSeconds = group.restBetweenRoundsSeconds ?? Constants.defaultRestSeconds
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
