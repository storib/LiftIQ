import Foundation

@MainActor
@Observable
final class ProgressService {
    private let progressRepository: ProgressRecordRepository
    private let prRepository: PersonalRecordRepository

    var recentPRs: [PersonalRecord] = []

    init(progressRepository: ProgressRecordRepository, prRepository: PersonalRecordRepository) {
        self.progressRepository = progressRepository
        self.prRepository = prRepository
    }

    func getProgressRecords(userId: String, exerciseId: String) async throws -> [ProgressRecord] {
        try await progressRepository.getRecords(userId: userId, exerciseId: exerciseId)
    }

    func loadRecentPRs(userId: String) async throws {
        recentPRs = try await prRepository.getRecords(userId: userId, limit: 20)
    }

    /// Deletes by id rather than record value so callers can roll back PRs
    /// they no longer hold in memory (e.g. a resumed session, where the ids
    /// were persisted on the SetLog but the records were never re-fetched).
    func deleteRecord(userId: String, recordId: String) async throws {
        try await prRepository.deleteRecord(userId: userId, recordId: recordId)
    }

    /// Fetches an exercise's existing PRs. PR values only ever increase, so
    /// the most recent records of each type contain the current bests and a
    /// bounded query is safe.
    func getExercisePRs(userId: String, exerciseId: String) async throws -> [PersonalRecord] {
        try await prRepository.getRecords(userId: userId, exerciseId: exerciseId, limit: 50)
    }

    /// Compares a completed set against `existingPRs` (typically the caller's
    /// session-scoped cache) and persists any new records. No Firestore reads.
    /// Weighted sets earn weight/e1RM records; unweighted (bodyweight) sets
    /// earn reps records instead — zero-value weight PRs would be rejected by
    /// the Firestore rules and read as broken in the UI.
    func checkForPRs(userId: String, exerciseId: String, exerciseName: String, setLog: SetLog, sessionId: String, existingPRs: [PersonalRecord]) async throws -> [PersonalRecord] {
        var newPRs: [PersonalRecord] = []

        func record(type: PRType, value: Double, previous: Double?) async throws {
            let pr = PersonalRecord(
                id: UUID().uuidString,
                userId: userId,
                exerciseId: exerciseId,
                exerciseName: exerciseName,
                type: type,
                value: value,
                previousValue: previous,
                achievedAt: Date(),
                sessionId: sessionId
            )
            try await prRepository.saveRecord(pr)
            newPRs.append(pr)
        }

        if setLog.weightKg > 0 {
            let bestWeight = existingPRs.filter { $0.type == .weight }.max(by: { $0.value < $1.value })
            if setLog.weightKg > (bestWeight?.value ?? 0) {
                try await record(type: .weight, value: setLog.weightKg, previous: bestWeight?.value)
            }

            let best1RM = existingPRs.filter { $0.type == .estimated1RM }.max(by: { $0.value < $1.value })
            if setLog.estimated1RM > (best1RM?.value ?? 0) {
                try await record(type: .estimated1RM, value: setLog.estimated1RM, previous: best1RM?.value)
            }
        } else if setLog.reps > 0 {
            let bestReps = existingPRs.filter { $0.type == .reps }.max(by: { $0.value < $1.value })
            if Double(setLog.reps) > (bestReps?.value ?? 0) {
                try await record(type: .reps, value: Double(setLog.reps), previous: bestReps?.value)
            }
        }

        return newPRs
    }
}
