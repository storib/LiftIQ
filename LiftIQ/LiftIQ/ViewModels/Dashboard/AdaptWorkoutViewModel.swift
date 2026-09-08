import Foundation
import Observation

/// Drives the "adapt today's workout" sheet: gathers the context the pure
/// engine needs, walks the lifter through the one choice each kind needs,
/// and produces an `AdaptedWorkout` for the dashboard to hold until Start.
/// The AI is only reached for a different gym with slots nothing in the
/// catalog can cover.
@MainActor
@Observable
final class AdaptWorkoutViewModel {
    enum Step: Equatable {
        case pickMinutes
        case pickBusyExercise
        case pickCandidate(exerciseId: String)
        case pickSetup
        case needsConsent
        case loadingAI
        case preview
        case error(String)
    }

    static let lastMinutesKey = "liftiq.lastAdaptMinutes"
    static let minuteChoices = [20, 30, 45]

    let kind: WorkoutAdaptationKind
    private(set) var step: Step
    var targetMinutes: Int
    private(set) var result: AdaptedWorkout?
    private(set) var candidates: [WorkoutAdapter.SwapCandidate] = []
    private(set) var isPreparing = false

    /// Slots the deterministic gym swap couldn't cover; the AI or a drop
    /// resolves them.
    private(set) var unresolved: [PlannedExercise] = []
    private var partial: AdaptedWorkout?
    private var chosenSetup: GymSetup?

    let template: WorkoutTemplate
    let profile: UserProfile
    private let userId: String
    private let exerciseService: any ExerciseServicing
    private let workoutService: any WorkoutServicing
    private let aiService: AIService?
    private let memory: (any MemoryServicing)?
    private let betaEvents: any BetaEventLogging
    private let hasAIConsent: () -> Bool
    private var context: WorkoutAdapter.Context

    init(
        kind: WorkoutAdaptationKind,
        template: WorkoutTemplate,
        profile: UserProfile,
        userId: String,
        exerciseService: any ExerciseServicing,
        workoutService: any WorkoutServicing,
        aiService: AIService? = nil,
        memory: (any MemoryServicing)? = nil,
        betaEvents: any BetaEventLogging = NoopBetaEventLogger(),
        hasAIConsent: @escaping () -> Bool = { AIConsentManager.hasConsented }
    ) {
        self.kind = kind
        self.template = template
        self.profile = profile
        self.userId = userId
        self.exerciseService = exerciseService
        self.workoutService = workoutService
        self.aiService = aiService
        self.memory = memory
        self.betaEvents = betaEvents
        self.hasAIConsent = hasAIConsent
        self.targetMinutes = UserDefaults.standard.object(forKey: Self.lastMinutesKey) as? Int ?? 30
        self.context = WorkoutAdapter.Context(
            exercises: Dictionary(uniqueKeysWithValues: exerciseService.exercises.map { ($0.id, $0) }),
            preferences: profile.exercisePreferences ?? [:],
            lastLogs: [:],
            userRestOverride: profile.defaultRestSeconds,
            defaultRestSeconds: profile.effectiveDefaultRestSeconds
        )
        switch kind {
        case .shortOnTime: step = .pickMinutes
        case .equipmentBusy: step = .pickBusyExercise
        case .differentGym: step = .pickSetup
        }
    }

    // MARK: - Derived

    var workoutExercises: [(planned: PlannedExercise, exercise: Exercise?)] {
        template.exerciseGroups.flatMap(\.exercises).map { ($0, context.exercises[$0.exerciseId]) }
    }

    var otherSetups: [GymSetup] {
        profile.effectiveGymSetups.filter { !$0.isDefault }
    }

    var minutesBefore: Int { WorkoutAdapter.estimatedMinutes(template, context: context) }

    // MARK: - Preparation

    /// One history fetch for every exercise a candidate list could show, so
    /// "you've done this" and last weights are ready before any step needs them.
    func prepare() async {
        isPreparing = true
        defer { isPreparing = false }
        if context.exercises.isEmpty {
            try? await exerciseService.loadExercises()
            context.exercises = Dictionary(uniqueKeysWithValues: exerciseService.exercises.map { ($0.id, $0) })
        }
        let workoutIds = Set(template.exerciseGroups.flatMap(\.exercises).map(\.exerciseId))
        let muscles = Set(workoutIds.compactMap { context.exercises[$0]?.primaryMuscleGroup })
        let candidateIds = Set(context.exercises.values.filter { muscles.contains($0.primaryMuscleGroup) }.map(\.id))
        let recent = (try? await workoutService.getRecentExerciseLogs(
            userId: userId, exerciseIds: workoutIds.union(candidateIds), excludingSessionId: nil, limit: 1
        )) ?? [:]
        context.lastLogs = recent.compactMapValues(\.first)
    }

    // MARK: - Short on time

    func applyMinutes() {
        UserDefaults.standard.set(targetMinutes, forKey: Self.lastMinutesKey)
        result = WorkoutAdapter.shortOnTime(template, targetMinutes: targetMinutes, context: context)
        step = .preview
    }

    // MARK: - Equipment busy

    func chooseBusy(exerciseId: String) {
        candidates = WorkoutAdapter.candidates(
            replacing: exerciseId, in: template,
            equipment: Set(profile.effectiveGymSetup.equipment), context: context
        )
        step = .pickCandidate(exerciseId: exerciseId)
    }

    func chooseCandidate(_ candidate: WorkoutAdapter.SwapCandidate) {
        guard case .pickCandidate(let exerciseId) = step else { return }
        let why = candidate.reasons.isEmpty ? "Same muscle group" : candidate.reasons.joined(separator: " · ")
        result = WorkoutAdapter.equipmentBusy(
            template, exerciseId: exerciseId, replacement: candidate.exercise,
            reason: "Equipment busy — \(why.lowercased())", context: context
        )
        step = .preview
    }

    // MARK: - Different gym

    func chooseSetup(_ setup: GymSetup) async {
        chosenSetup = setup
        switch WorkoutAdapter.differentGym(template, setup: setup, context: context) {
        case .adapted(let adapted):
            result = adapted
            step = .preview
        case .needsAI(let partialResult, let slots):
            partial = partialResult
            unresolved = slots
            if hasAIConsent(), aiService != nil {
                await runAIFallback()
            } else {
                step = .needsConsent
            }
        }
    }

    /// Consent granted (or already held): send the partially adapted workout
    /// with the setup's equipment as `availableEquipment`, so the server's
    /// own filter can only return exercises this gym has.
    func runAIFallback() async {
        guard let partial, let setup = chosenSetup, let aiService else {
            dropUnresolved()
            return
        }
        step = .loadingAI
        var equipmentProfile = profile
        equipmentProfile.availableEquipment = setup.equipment
        let names = unresolved.map { context.exercises[$0.exerciseId]?.name ?? $0.exerciseId }
        let avoided = profile.avoidedExerciseIds.compactMap { context.exercises[$0]?.name }
        var instruction = "I'm training at a different gym today with only: "
            + setup.equipment.map(\.displayName).joined(separator: ", ")
            + ". Replace only these exercises, which need equipment I don't have: "
            + names.joined(separator: ", ")
            + ". Keep everything else exactly as it is."
        if !avoided.isEmpty {
            instruction += " Do not use: " + avoided.joined(separator: ", ") + "."
        }
        do {
            let modification = try await aiService.modifyWorkout(
                scope: .workout, instruction: instruction, plan: nil,
                workout: partial.template, profile: equipmentProfile
            )
            guard let aiWorkout = modification.workout else { throw AIServiceError.invalidResponse }
            let missing = Set(setup.equipment)
            let aiChanges = WorkoutAdapter.diff(
                original: partial.template, aiResult: aiWorkout, context: context,
                reason: "Replaced by AI — no matching equipment at \(setup.name)"
            )
            var merged = partial
            merged.template = aiWorkout
            merged.changes += aiChanges
            merged.record.changes = merged.changes
            merged.record.usedAI = true
            merged.minutesAfter = WorkoutAdapter.estimatedMinutes(aiWorkout, context: context)
            _ = missing
            result = merged
            step = .preview
        } catch {
            step = .error(error.localizedDescription)
        }
    }

    /// No consent, or no AI: leave the unresolvable exercises out.
    func dropUnresolved() {
        guard let partial, let setup = chosenSetup else { return }
        result = WorkoutAdapter.removingUnresolved(partial, unresolved: unresolved, setupName: setup.name, context: context)
        step = .preview
    }

    func retryFromError() {
        if partial != nil { step = .needsConsent } else {
            switch kind {
            case .shortOnTime: step = .pickMinutes
            case .equipmentBusy: step = .pickBusyExercise
            case .differentGym: step = .pickSetup
            }
        }
    }

    // MARK: - Outcome

    /// Hands the adaptation back and remembers what it can: the chosen
    /// busy-equipment swap becomes that exercise's usual alternative.
    func accept() async -> AdaptedWorkout? {
        guard let result else { return nil }
        betaEvents.log("adapt_chosen", [
            "kind": kind.rawValue, "accepted": true, "changesCount": result.changes.count,
            "usedAI": result.record.usedAI, "targetMinutes": result.record.targetMinutes ?? -1,
        ])
        if kind == .equipmentBusy,
           let change = result.changes.first(where: { $0.kind == .swappedExercise }),
           let replacement = change.replacementExerciseId {
            await memory?.recordUsualAlternative(for: change.exerciseId, replacement: replacement)
        }
        return result
    }

    func cancel() {
        betaEvents.log("adapt_chosen", [
            "kind": kind.rawValue, "accepted": false,
            "changesCount": result?.changes.count ?? 0, "usedAI": result?.record.usedAI ?? false,
        ])
    }
}
