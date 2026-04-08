import Foundation

@Observable
final class ProgressService {
    private let progressRepository: ProgressRecordRepository
    private let prRepository: PersonalRecordRepository
    private let bodyRepository: BodyMeasurementRepository

    var recentPRs: [PersonalRecord] = []
    var bodyMeasurements: [BodyMeasurement] = []

    init(progressRepository: ProgressRecordRepository, prRepository: PersonalRecordRepository, bodyRepository: BodyMeasurementRepository) {
        self.progressRepository = progressRepository
        self.prRepository = prRepository
        self.bodyRepository = bodyRepository
    }

    func getProgressRecords(userId: String, exerciseId: String) async throws -> [ProgressRecord] {
        try await progressRepository.getRecords(userId: userId, exerciseId: exerciseId)
    }

    func loadRecentPRs(userId: String) async throws {
        recentPRs = try await prRepository.getRecords(userId: userId, limit: 20)
    }

    func loadBodyMeasurements(userId: String) async throws {
        bodyMeasurements = try await bodyRepository.getMeasurements(userId: userId)
    }

    func saveBodyMeasurement(_ measurement: BodyMeasurement) async throws {
        try await bodyRepository.saveMeasurement(measurement)
        try await loadBodyMeasurements(userId: measurement.userId)
    }

    func checkForPR(userId: String, exerciseId: String, exerciseName: String, setLog: SetLog, sessionId: String) async throws -> PersonalRecord? {
        let existingPRs = try await prRepository.getRecords(userId: userId, exerciseId: exerciseId)

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
            return pr
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
            return pr
        }

        return nil
    }
}
