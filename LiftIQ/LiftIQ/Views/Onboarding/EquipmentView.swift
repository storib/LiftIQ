import SwiftUI

struct EquipmentView: View {
    @Bindable var viewModel: OnboardingViewModel

    var body: some View {
        VStack(spacing: 24) {
            Text("Available Equipment")
                .font(.title2.bold())
            Text("Pick a setup, or customize below")
                .foregroundStyle(.secondary)

            ScrollView {
                EquipmentPickerGrid(selection: $viewModel.selectedEquipment)
                    .padding(.vertical, 8)
            }
        }
        .padding(.top, 32)
    }
}

enum EquipmentPreset: String, CaseIterable, Identifiable {
    case fullGym
    case homeGym
    case dumbbellsAndBench
    case bodyweightOnly

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fullGym: return "Full Gym"
        case .homeGym: return "Home Gym"
        case .dumbbellsAndBench: return "Dumbbells + Bench"
        case .bodyweightOnly: return "Bodyweight Only"
        }
    }

    var subtitle: String {
        switch self {
        case .fullGym: return "Everything available"
        case .homeGym: return "Barbell, dumbbells, bench, pull-up bar"
        case .dumbbellsAndBench: return "Dumbbells, bench, pull-up bar"
        case .bodyweightOnly: return "Body and pull-up bar"
        }
    }

    var icon: String {
        switch self {
        case .fullGym: return "building.2.fill"
        case .homeGym: return "house.fill"
        case .dumbbellsAndBench: return "dumbbell.fill"
        case .bodyweightOnly: return "figure.stand"
        }
    }

    var equipment: Set<Equipment> {
        switch self {
        case .fullGym:
            return Set(Equipment.allCases)
        case .homeGym:
            return [.barbell, .dumbbell, .bench, .pullUpBar, .ezBar, .bodyweight]
        case .dumbbellsAndBench:
            return [.dumbbell, .bench, .pullUpBar, .bodyweight]
        case .bodyweightOnly:
            return [.bodyweight, .pullUpBar]
        }
    }
}
