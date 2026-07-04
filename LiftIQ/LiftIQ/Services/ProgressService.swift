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

    func deleteRecord(_ record: PersonalRecord) async throws {
        try await prRepository.deleteRecord(userId: record.userId, recordId: record.id)
    }

    /// Fetches an exercise's existing PRs. PR values only ever increase, so
    /// the most recent records of each type contain the current bests and a
    /// bounded query is safe.
    func getExercisePRs(userId: String, exerciseId: String) async throws -> [PersonalRecord] {
        try await prRepository.getRecords(userId: userId, exerciseId: exerciseId, limit: 50)
    }

    /// Compares a completed set against `existingPRs` (typically the caller's
    /// session-scoped cache) and persists any new records. No Firestore reads.
    func checkForPRs(userId: String, exerciseId: String, exerciseName: String, setLog: SetLog, sessionId: String, existingPRs: [PersonalRecord]) async throws -> [PersonalRecord] {
        var newPRs: [PersonalRecord] = []

        let bestWeight = existingPRs.filter { $0.type == .weight }.max(by: { $0.value < $1.value })
        if bestWeight == nil || setLog.weightKg > (bestWeight?.value ?? 0) {
            let pr = PersonalRecord(
                id: UUID().uuidString,
                userId: userId,
                exerciseId: exerciseId,
                exerciseName: exerciseName,
                type: .weight,
                value: setLog.weightKg,
                previousValue: bestWeight?.value,
                achievedAt: Date(),
                sessionId: sessionId
            )
            try await prRepository.saveRecord(pr)
            newPRs.append(pr)
        }

        let best1RM = existingPRs.filter { $0.type == .estimated1RM }.max(by: { $0.value < $1.value })
        if best1RM == nil || setLog.estimated1RM > (best1RM?.value ?? 0) {
            let pr = PersonalRecord(
                id: UUID().uuidString,
                userId: userId,
                exerciseId: exerciseId,
                exerciseName: exerciseName,
                type: .estimated1RM,
                value: setLog.estimated1RM,
                previousValue: best1RM?.value,
                achievedAt: Date(),
                sessionId: sessionId
            )
            try await prRepository.saveRecord(pr)
            newPRs.append(pr)
        }

        return newPRs
    }
}
