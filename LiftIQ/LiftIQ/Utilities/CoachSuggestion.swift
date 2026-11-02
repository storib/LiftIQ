import Foundation

/// One plan slot's current progression suggestion, judged only against the
/// history logged *for that slot* — see `DashboardViewModel.currentSuggestions`.
struct PlanSlotSuggestion: Equatable {
    let dayId: String
    let dayName: String
    let planned: PlannedExercise
    let suggestion: ProgressionSuggestion
}

/// The Dashboard's "want the AI to suggest a change?" card: offered when one
/// or more of the active plan's lifts are stalled, so the AI's ability to
/// edit the plan shows up where it is useful instead of waiting behind a
/// toolbar button nobody opens (beta: zero Modify-with-AI calls in a month
/// of steady training).
///
/// The trigger is the existing acute stall signal from `ProgressionService`
/// (even the best top set missed the rep floor at the same weight for
/// `Constants.stallThreshold` sessions running) — a description of the logs,
/// never a plateau verdict, and no new detector (see `StrengthTrend` for why
/// short windows can't make that claim). It is evaluated per plan slot: a lift
/// on a heavy day and a high-rep day has two prescriptions, and heavy-day sets
/// judged against the high-rep floor would read as misses. The back-off the
/// exercise card already suggests is one answer to a stall; this offers the
/// other one — change the exercise or its rep range — and nothing happens
/// until the lifter reviews the AI's proposal and taps Save Plan.
struct CoachSuggestion: Equatable {
    struct Lift: Equatable {
        let slotId: String
        let dayId: String
        let dayName: String
        let exerciseId: String
        let name: String
        let repsMin: Int
        let repsMax: Int
        /// Consecutive sessions the stall has lasted.
        let sessions: Int

        /// Snooze identity. The prescription is part of it, so a slot whose
        /// rep range or exercise changed is a different suggestion.
        func snoozeKey(planId: String) -> String {
            CoachSuggestion.snoozeKey(planId: planId, dayId: dayId, slot: slotId, exerciseId: exerciseId,
                                      repsMin: repsMin, repsMax: repsMax)
        }
    }

    let planId: String
    /// Stalled, un-snoozed lifts in plan order, at most `maxLifts`.
    let lifts: [Lift]

    /// Enough to keep the request focused; more than this reads as "rewrite
    /// my program", which is the program-refresh card's job.
    static let maxLifts = 4

    /// "Not now" means not now: a still-stalled lift comes back after this.
    static let snoozeDays = 21

    static func snoozeKey(planId: String, dayId: String, slot: String, exerciseId: String,
                          repsMin: Int, repsMax: Int) -> String {
        "\(planId)|\(dayId)|\(slot)|\(exerciseId)|\(repsMin)-\(repsMax)"
    }

    var snoozeKeys: [String] { lifts.map { $0.snoozeKey(planId: planId) } }

    var title: String {
        lifts.count == 1
            ? "\(lifts[0].name) has been stuck"
            : "\(lifts.count) lifts have been stuck"
    }

    var detail: String {
        if lifts.count == 1 {
            let lift = lifts[0]
            return "Same weight, short of your \(lift.repsMin)-\(lift.repsMax) reps on \(lift.dayName), \(lift.sessions) sessions running."
        }
        return lifts.map { "\($0.name) (\($0.dayName))" }.joined(separator: ", ")
            + " — same weight, short of the rep range, \(Constants.stallThreshold)+ sessions each."
    }

    /// The plan-scope request sent to `modifyWorkout`. Descriptive about what
    /// happened, names the day so only that slot changes, and explicit that
    /// nothing else should; the server keeps exercises inside the equipment.
    var instruction: String {
        let named = lifts
            .map { "\($0.name) on \($0.dayName) (\($0.repsMin)-\($0.repsMax) reps, \($0.sessions) sessions)" }
            .joined(separator: ", ")
        return "These lifts have been stuck: at the same weight for several sessions running, "
            + "even my best set has come in under the bottom of the rep range — \(named). "
            + "For each one, change only that exercise on that day: swap it for a similar exercise that trains "
            + "the same muscles, or adjust its sets and rep range if that suits it better. "
            + "Keep every other exercise, day and setting exactly as it is."
    }

    /// Every currently stalled slot, in plan order.
    static func stalledLifts(slots: [PlanSlotSuggestion], names: [String: String]) -> [Lift] {
        slots.compactMap { slot in
            guard case .stall(_, let sessions) = slot.suggestion.reason else { return nil }
            return Lift(
                slotId: slot.planned.id,
                dayId: slot.dayId,
                dayName: slot.dayName,
                exerciseId: slot.planned.exerciseId,
                name: names[slot.planned.exerciseId] ?? slot.planned.exerciseId,
                repsMin: slot.planned.repsMin,
                repsMax: slot.planned.repsMax,
                sessions: sessions
            )
        }
    }

    /// The card to show, if any: stalled lifts minus snoozed ones.
    static func evaluate(planId: String, stalled: [Lift], isSnoozed: (String) -> Bool) -> CoachSuggestion? {
        let live = stalled.filter { !isSnoozed($0.snoozeKey(planId: planId)) }
        guard !live.isEmpty else { return nil }
        return CoachSuggestion(planId: planId, lifts: Array(live.prefix(maxLifts)))
    }

    /// Snooze keys for the same slots in the plan the AI edit produced, so a
    /// slot whose rep range was just changed isn't re-offered immediately on
    /// history logged under the old prescription.
    func editedSnoozeKeys(in edited: WorkoutPlan) -> [String] {
        lifts.compactMap { lift in
            guard let day = edited.workouts.first(where: { $0.id == lift.dayId }),
                  let slot = day.exerciseGroups.flatMap(\.exercises).first(where: { $0.id == lift.slotId })
            else { return nil }
            return Self.snoozeKey(planId: edited.id, dayId: day.id, slot: slot.id, exerciseId: slot.exerciseId,
                                  repsMin: slot.repsMin, repsMax: slot.repsMax)
        }
    }
}

/// Device-local snoozes for coach suggestions, keyed by user id so accounts
/// sharing a device never hide each other's cards — the same scoping as
/// `WeeklyInsightsStore`. A snooze ends after `CoachSuggestion.snoozeDays`,
/// or as soon as the lift is seen un-stalled (`forgetRecovered`), so a lift
/// that recovers and stalls again months later is offered again. Disposable:
/// losing it only means a card may show once more.
struct CoachSuggestionStore {
    private let defaults: UserDefaults
    private static let prefix = "liftiq.coachSuggestion.snoozed."
    static let maxEntries = 60

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func isSnoozed(_ key: String, userId: String, now: Date = Date()) -> Bool {
        guard let at = entries(userId: userId)[key] else { return false }
        return now.timeIntervalSince1970 - at < Double(CoachSuggestion.snoozeDays) * 86_400
    }

    func snooze(_ keys: [String], userId: String, now: Date = Date()) {
        var entries = entries(userId: userId)
        for key in keys { entries[key] = now.timeIntervalSince1970 }
        save(entries, userId: userId)
    }

    /// Drops this plan's snoozes for slots that are no longer stalled: the
    /// lift recovered (or the slot changed), so a future stall is new.
    func forgetRecovered(planId: String, stillStalled: Set<String>, userId: String) {
        let entries = entries(userId: userId)
        let kept = entries.filter { key, _ in !key.hasPrefix(planId + "|") || stillStalled.contains(key) }
        if kept.count != entries.count { save(kept, userId: userId) }
    }

    func clear(userId: String) {
        defaults.removeObject(forKey: Self.prefix + userId)
    }

    private func entries(userId: String) -> [String: Double] {
        defaults.dictionary(forKey: Self.prefix + userId) as? [String: Double] ?? [:]
    }

    private func save(_ entries: [String: Double], userId: String) {
        let newest = entries.sorted { $0.value > $1.value }.prefix(Self.maxEntries)
        defaults.set(Dictionary(uniqueKeysWithValues: newest.map { ($0.key, $0.value) }), forKey: Self.prefix + userId)
    }
}
