import Foundation
import HealthKit
import Observation

enum HealthKitError: LocalizedError {
    case sharingAuthorizationDenied

    var errorDescription: String? {
        switch self {
        case .sharingAuthorizationDenied:
            return "Health access was declined. To sync workouts, allow LiftIQ in the Health app under Sharing → Apps."
        }
    }
}

/// Mirrors completed sessions into Apple Health and optionally reads external
/// workouts for the dashboard. Both preferences and imported data stay local
/// to the device; Health failures never break a workout flow.
@MainActor
@Observable
final class HealthKitService {
    private let store = HKHealthStore()
    private static let syncEnabledKey = "liftiq.healthKitSyncEnabled"
    private static let activityImportEnabledKey = "liftiq.healthKitActivityImportEnabled"

    private(set) var isSyncEnabled: Bool
    private(set) var isActivityImportEnabled: Bool

    var isAvailable: Bool {
        HKHealthStore.isHealthDataAvailable()
    }

    init() {
        isSyncEnabled = UserDefaults.standard.bool(forKey: Self.syncEnabledKey)
        isActivityImportEnabled = UserDefaults.standard.bool(forKey: Self.activityImportEnabledKey)
    }

    func enableSync() async throws {
        // requestAuthorization succeeds even when the user declines; the
        // share status is the real signal.
        try await store.requestAuthorization(toShare: [HKObjectType.workoutType()], read: [])
        guard store.authorizationStatus(for: HKObjectType.workoutType()) == .sharingAuthorized else {
            throw HealthKitError.sharingAuthorizationDenied
        }
        isSyncEnabled = true
        UserDefaults.standard.set(true, forKey: Self.syncEnabledKey)
    }

    func disableSync() {
        isSyncEnabled = false
        UserDefaults.standard.set(false, forKey: Self.syncEnabledKey)
    }

    func enableActivityImport() async throws {
        try await store.requestAuthorization(toShare: [], read: [HKObjectType.workoutType()])
        // HealthKit intentionally does not reveal read-denial status. A
        // successful request means the preference can be enabled; a declined
        // user simply receives no samples.
        isActivityImportEnabled = true
        UserDefaults.standard.set(true, forKey: Self.activityImportEnabledKey)
    }

    func disableActivityImport() {
        isActivityImportEnabled = false
        UserDefaults.standard.set(false, forKey: Self.activityImportEnabledKey)
    }

    func fetchExternalActivities(from startDate: Date, to endDate: Date) async throws -> [ExternalActivity] {
        guard isActivityImportEnabled, isAvailable, endDate > startDate else { return [] }

        let predicate = HKQuery.predicateForSamples(
            withStart: startDate,
            end: endDate,
            options: [.strictStartDate]
        )
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
        let workouts: [HKWorkout] = try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: HKObjectType.workoutType(),
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sort]
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: samples as? [HKWorkout] ?? [])
                }
            }
            store.execute(query)
        }

        let ownBundleIdentifier = Bundle.main.bundleIdentifier
        return workouts.compactMap { workout in
            let source = workout.sourceRevision.source
            guard source.bundleIdentifier != ownBundleIdentifier else { return nil }
            return ExternalActivity(
                id: workout.uuid.uuidString,
                kind: Self.kind(for: workout.workoutActivityType),
                startedAt: workout.startDate,
                endedAt: workout.endDate,
                sourceName: source.name,
                activeEnergyKilocalories: workout.totalEnergyBurned?.doubleValue(for: .kilocalorie()),
                distanceMeters: workout.totalDistance?.doubleValue(for: .meter())
            )
        }
    }

    private static func kind(for activityType: HKWorkoutActivityType) -> ExternalActivity.Kind {
        switch activityType {
        case .walking: return .walking
        case .running: return .running
        case .cycling: return .cycling
        case .hiking: return .hiking
        case .swimming: return .swimming
        case .traditionalStrengthTraining, .functionalStrengthTraining: return .strengthTraining
        case .highIntensityIntervalTraining: return .highIntensityIntervalTraining
        case .yoga: return .yoga
        case .pilates: return .pilates
        case .rowing: return .rowing
        case .elliptical: return .elliptical
        case .stairClimbing: return .stairClimbing
        case .dance: return .dance
        case .coreTraining: return .coreTraining
        default: return .other
        }
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
