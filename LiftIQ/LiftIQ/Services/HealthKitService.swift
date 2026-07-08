import Foundation
import HealthKit
import Observation

enum HealthKitError: LocalizedError {
    case authorizationDenied

    var errorDescription: String? {
        switch self {
        case .authorizationDenied:
            return "Health access was declined. To sync workouts, allow LiftIQ in the Health app under Sharing → Apps."
        }
    }
}

/// Mirrors completed sessions into Apple Health as strength-training
/// workouts. Sync is a device-local preference (UserDefaults, not the user
/// profile), and every Health call is best-effort — a Health failure must
/// never break a workout flow.
@MainActor
@Observable
final class HealthKitService {
    private let store = HKHealthStore()
    private static let syncEnabledKey = "liftiq.healthKitSyncEnabled"

    private(set) var isSyncEnabled: Bool

    var isAvailable: Bool {
        HKHealthStore.isHealthDataAvailable()
    }

    init() {
        isSyncEnabled = UserDefaults.standard.bool(forKey: Self.syncEnabledKey)
    }

    func enableSync() async throws {
        // requestAuthorization succeeds even when the user declines; the
        // share status is the real signal.
        try await store.requestAuthorization(toShare: [HKObjectType.workoutType()], read: [])
        guard store.authorizationStatus(for: HKObjectType.workoutType()) == .sharingAuthorized else {
            throw HealthKitError.authorizationDenied
        }
        isSyncEnabled = true
        UserDefaults.standard.set(true, forKey: Self.syncEnabledKey)
    }

    func disableSync() {
        isSyncEnabled = false
        UserDefaults.standard.set(false, forKey: Self.syncEnabledKey)
    }

    /// Saves a completed session as an HKWorkout, tagged with the session id
    /// so a later session delete can find and remove it.
    func exportSession(_ session: WorkoutSession) async {
        guard isSyncEnabled,
              isAvailable,
              store.authorizationStatus(for: HKObjectType.workoutType()) == .sharingAuthorized,
              let completedAt = session.completedAt,
              completedAt > session.startedAt else { return }

        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .traditionalStrengthTraining
        let builder = HKWorkoutBuilder(healthStore: store, configuration: configuration, device: .local())
        do {
            try await builder.beginCollection(at: session.startedAt)
            try await builder.addMetadata([HKMetadataKeyExternalUUID: session.id])
            try await builder.endCollection(at: completedAt)
            _ = try await builder.finishWorkout()
        } catch {
            // Best-effort; the session itself is already saved.
        }
    }

    /// Best-effort removal of the HKWorkout exported for a deleted session.
    /// Only samples this app wrote can be deleted, which is exactly the set
    /// tagged with our external UUID.
    func deleteExportedSession(sessionId: String) async {
        guard isAvailable else { return }
        let predicate = HKQuery.predicateForObjects(
            withMetadataKey: HKMetadataKeyExternalUUID,
            allowedValues: [sessionId]
        )
        do {
            let samples: [HKSample] = try await withCheckedThrowingContinuation { continuation in
                let query = HKSampleQuery(
                    sampleType: HKObjectType.workoutType(),
                    predicate: predicate,
                    limit: HKObjectQueryNoLimit,
                    sortDescriptors: nil
                ) { _, samples, error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume(returning: samples ?? [])
                    }
                }
                store.execute(query)
            }
            guard !samples.isEmpty else { return }
            try await store.delete(samples)
        } catch {
            // Best-effort cleanup.
        }
    }
}
