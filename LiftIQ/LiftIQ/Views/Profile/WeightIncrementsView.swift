import SwiftUI

/// Smallest loadable step per equipment class. Progression suggests the
/// next weight in these steps, so a lifter with 1.25 kg plates or 2.5 lb
/// microplates can say so.
struct WeightIncrementsView: View {
    @Environment(AppDependencies.self) private var dependencies

    @State private var barbell: Double = 0
    @State private var dumbbell: Double = 0
    @State private var machine: Double = 0
    @State private var isSaving = false
    @State private var errorMessage: String?

    private var unitSystem: UnitSystem {
        dependencies.authService.currentUser?.profile.unitSystem ?? .imperial
    }

    /// Plate-realistic steps in the display unit.
    private var choices: [Double] {
        unitSystem == .metric ? [1, 1.25, 2, 2.5, 5] : [2.5, 5, 10]
    }

    private var unitLabel: String { UnitConversionService.weightLabel(for: unitSystem) }

    var body: some View {
        List {
            Section {
                row("Barbell", value: $barbell)
                row("Dumbbell", value: $dumbbell)
                row("Machine & cable", value: $machine)
            } footer: {
                Text("LiftIQ suggests the next weight in these steps. Pick what your gym's plates and stacks actually allow.")
            }
            Section {
                Button("Reset to Defaults") {
                    Task { await save(nil) }
                }
            }
        }
        .navigationTitle("Weight Increments")
        .navigationBarTitleDisplayMode(.inline)
        .disabled(isSaving)
        .onAppear(perform: load)
        .alert("Couldn't Save", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func row(_ title: String, value: Binding<Double>) -> some View {
        Picker(title, selection: Binding(
            get: { nearestChoice(value.wrappedValue) },
            set: { newValue in
                value.wrappedValue = newValue
                Task { await save(current()) }
            }
        )) {
            ForEach(choices, id: \.self) { choice in
                Text("\(choice.formatted(decimals: 2)) \(unitLabel)").tag(choice)
            }
        }
    }

    private func nearestChoice(_ value: Double) -> Double {
        choices.min { abs($0 - value) < abs($1 - value) } ?? value
    }

    private func load() {
        let increments = dependencies.authService.currentUser?.profile.effectiveWeightIncrements ?? .standard
        barbell = UnitConversionService.convertWeight(increments.barbellKg, to: unitSystem)
        dumbbell = UnitConversionService.convertWeight(increments.dumbbellKg, to: unitSystem)
        machine = UnitConversionService.convertWeight(increments.machineKg, to: unitSystem)
    }

    private func current() -> WeightIncrements {
        WeightIncrements(
            barbellKg: UnitConversionService.convertToKg(nearestChoice(barbell), from: unitSystem),
            dumbbellKg: UnitConversionService.convertToKg(nearestChoice(dumbbell), from: unitSystem),
            machineKg: UnitConversionService.convertToKg(nearestChoice(machine), from: unitSystem)
        )
    }

    private func save(_ increments: WeightIncrements?) async {
        isSaving = true
        defer { isSaving = false }
        do {
            try await dependencies.memoryService.setWeightIncrements(increments)
            load()
        } catch {
            errorMessage = error.localizedDescription
            load()
        }
    }
}
