import XCTest
@testable import LiftIQ

final class UserProfileMemoryTests: XCTestCase {

    private func makeProfile(equipment: [Equipment] = [.barbell, .bench]) -> UserProfile {
        UserProfile(
            experienceLevel: .intermediate, goals: [.hypertrophy], availableEquipment: equipment,
            trainingDaysPerWeek: 3, sessionDurationMinutes: 60, injuries: [],
            bodyWeightKg: nil, heightCm: nil, dateOfBirth: nil, unitSystem: .imperial
        )
    }

    func testLegacyProfileJSONDecodesWithoutMemoryFields() throws {
        // A document written before memory existed has none of the new keys.
        let json = """
        {"experienceLevel":"beginner","goals":["strength"],"availableEquipment":["dumbbell"],
         "trainingDaysPerWeek":3,"sessionDurationMinutes":45,"injuries":[],"unitSystem":"metric"}
        """.data(using: .utf8)!
        let profile = try JSONDecoder().decode(UserProfile.self, from: json)
        XCTAssertNil(profile.gymSetups)
        XCTAssertNil(profile.exercisePreferences)
        XCTAssertNil(profile.weightIncrementsKg)
        XCTAssertEqual(profile.effectiveGymSetup.equipment, [.dumbbell])
        XCTAssertEqual(profile.effectiveWeightIncrements, .standard)
    }

    func testMemoryFieldsRoundTrip() throws {
        var profile = makeProfile()
        profile.gymSetups = [
            GymSetup(id: "a", name: "Home", equipment: [.dumbbell, .bench], isDefault: true),
            GymSetup(id: "b", name: "Work", equipment: [.machines, .cables], isDefault: false),
        ]
        profile.exercisePreferences = ["bench": ExercisePreference(usualAlternativeId: "db-press", avoided: nil, note: "Seat 4", lastUsedAt: nil)]
        profile.weightIncrementsKg = WeightIncrements(barbellKg: 1.25, dumbbellKg: 1, machineKg: 5)

        let data = try JSONEncoder().encode(profile)
        let decoded = try JSONDecoder().decode(UserProfile.self, from: data)

        XCTAssertEqual(decoded, profile)
        XCTAssertEqual(decoded.effectiveGymSetup.name, "Home")
        XCTAssertEqual(decoded.preference(for: "bench")?.note, "Seat 4")
    }

    func testEffectiveGymSetupFallsBackToFirstWhenNoDefault() {
        var profile = makeProfile()
        profile.gymSetups = [GymSetup(id: "a", name: "Only", equipment: [.bands], isDefault: false)]
        XCTAssertEqual(profile.effectiveGymSetup.id, "a")
    }

    func testAvoidedIds() {
        var profile = makeProfile()
        profile.exercisePreferences = [
            "leg-press": ExercisePreference(avoided: true),
            "squat": ExercisePreference(note: "belt"),
        ]
        XCTAssertEqual(profile.avoidedExerciseIds, ["leg-press"])
    }

    func testWeightIncrementsPickByEquipment() {
        let increments = WeightIncrements(barbellKg: 1.25, dumbbellKg: 1, machineKg: 5)
        let barbell = Exercise(id: "b", name: "B", primaryMuscleGroup: .chest, secondaryMuscleGroups: [], equipment: [.barbell, .bench], movementPattern: .horizontalPush, difficulty: .beginner, youtubeVideoId: "", instructions: "", tips: [], alternatives: [], isCompound: true, tags: [])
        let dumbbell = Exercise(id: "d", name: "D", primaryMuscleGroup: .chest, secondaryMuscleGroups: [], equipment: [.dumbbell], movementPattern: .horizontalPush, difficulty: .beginner, youtubeVideoId: "", instructions: "", tips: [], alternatives: [], isCompound: true, tags: [])
        let cable = Exercise(id: "c", name: "C", primaryMuscleGroup: .chest, secondaryMuscleGroups: [], equipment: [.cables], movementPattern: .isolation, difficulty: .beginner, youtubeVideoId: "", instructions: "", tips: [], alternatives: [], isCompound: false, tags: [])
        XCTAssertEqual(increments.increment(for: barbell), 1.25)
        XCTAssertEqual(increments.increment(for: dumbbell), 1)
        XCTAssertEqual(increments.increment(for: cable), 5)
        XCTAssertEqual(increments.increment(for: nil), 1.25)
    }
}

@MainActor
final class MemoryServiceTests: XCTestCase {

    private func makeProfile() -> UserProfile {
        UserProfile(
            experienceLevel: .intermediate, goals: [], availableEquipment: [.barbell],
            trainingDaysPerWeek: 3, sessionDurationMinutes: 60, injuries: [],
            bodyWeightKg: nil, heightCm: nil, dateOfBirth: nil, unitSystem: .metric
        )
    }

    func testSaveGymSetupsMirrorsDefaultIntoAvailableEquipment() async throws {
        let store = FakeProfileStore(profile: makeProfile())
        let memory = MemoryService(profileStore: store)

        try await memory.saveGymSetups([
            GymSetup(id: "a", name: "Home", equipment: [.dumbbell], isDefault: false),
            GymSetup(id: "b", name: "Gym", equipment: [.barbell, .machines], isDefault: true),
        ])

        XCTAssertEqual(store.currentProfile?.availableEquipment, [.barbell, .machines])
        XCTAssertEqual(memory.activeEquipment, [.barbell, .machines])
    }

    func testSaveGymSetupsEnforcesExactlyOneDefault() async throws {
        let store = FakeProfileStore(profile: makeProfile())
        let memory = MemoryService(profileStore: store)

        try await memory.saveGymSetups([
            GymSetup(id: "a", name: "A", equipment: [.bands], isDefault: false),
            GymSetup(id: "b", name: "B", equipment: [.cables], isDefault: false),
        ])
        XCTAssertEqual(store.currentProfile?.gymSetups?.map(\.isDefault), [true, false])

        try await memory.saveGymSetups([
            GymSetup(id: "a", name: "A", equipment: [.bands], isDefault: true),
            GymSetup(id: "b", name: "B", equipment: [.cables], isDefault: true),
        ])
        XCTAssertEqual(store.currentProfile?.gymSetups?.map(\.isDefault), [true, false])
    }

    func testPreferenceMutationsMergeAndPruneEmpty() async throws {
        let store = FakeProfileStore(profile: makeProfile())
        let memory = MemoryService(profileStore: store)

        await memory.recordUsualAlternative(for: "bench", replacement: "db-press")
        try await memory.setNote("  Seat 4  ", for: "bench")
        try await memory.setAvoided(true, for: "leg-press")
        XCTAssertEqual(memory.preferences["bench"]?.usualAlternativeId, "db-press")
        XCTAssertEqual(memory.preferences["bench"]?.note, "Seat 4")
        XCTAssertTrue(memory.preferences["leg-press"]?.isAvoided ?? false)

        try await memory.setAvoided(false, for: "leg-press")
        XCTAssertNil(memory.preferences["leg-press"], "an empty preference is pruned")

        try await memory.setNote("", for: "bench")
        XCTAssertNil(memory.preferences["bench"]?.note)
        XCTAssertEqual(memory.preferences["bench"]?.usualAlternativeId, "db-press")
    }

    func testRecordUsualAlternativeIsBestEffort() async {
        let store = FakeProfileStore(profile: makeProfile())
        store.updateError = URLError(.notConnectedToInternet)
        let memory = MemoryService(profileStore: store)
        await memory.recordUsualAlternative(for: "bench", replacement: "db-press")
        XCTAssertTrue(memory.preferences.isEmpty)
    }
}
