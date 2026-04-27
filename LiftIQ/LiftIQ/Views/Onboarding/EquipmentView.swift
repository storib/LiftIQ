import SwiftUI

struct EquipmentView: View {
    @Bindable var viewModel: OnboardingViewModel

    private let columns = [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        VStack(spacing: 24) {
            Text("Available Equipment")
                .font(.title2.bold())
            Text("Pick a setup, or customize below")
                .foregroundStyle(.secondary)

            ScrollView {
                VStack(spacing: 20) {
                    presetGrid

                    Divider()
                        .padding(.horizontal)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Customize")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal)
                        equipmentGrid
                    }
                }
                .padding(.vertical, 8)
            }
        }
        .padding(.top, 32)
    }

    private var presetGrid: some View {
        let presetColumns = [GridItem(.flexible()), GridItem(.flexible())]
        return LazyVGrid(columns: presetColumns, spacing: 12) {
            ForEach(EquipmentPreset.allCases) { preset in
                presetCard(preset)
            }
        }
        .padding(.horizontal)
    }

    private func presetCard(_ preset: EquipmentPreset) -> some View {
        let isActive = preset.equipment == viewModel.selectedEquipment
        return Button {
            viewModel.selectedEquipment = preset.equipment
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: preset.icon)
                    .font(.title3)
                Text(preset.title)
                    .font(.subheadline.weight(.semibold))
                Text(preset.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2, reservesSpace: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(isActive ? Color.accentColor.opacity(0.15) : Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isActive ? Color.accentColor : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }

    private var equipmentGrid: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(Equipment.allCases) { equipment in
                Button {
                    if viewModel.selectedEquipment.contains(equipment) {
                        viewModel.selectedEquipment.remove(equipment)
                    } else {
                        viewModel.selectedEquipment.insert(equipment)
                    }
                } label: {
                    VStack(spacing: 8) {
                        Image(systemName: equipment.icon)
                            .font(.title2)
                        Text(equipment.displayName)
                            .font(.caption)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, minHeight: 80)
                    .padding(.vertical, 8)
                    .background(viewModel.selectedEquipment.contains(equipment) ? Color.accentColor.opacity(0.15) : Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(viewModel.selectedEquipment.contains(equipment) ? Color.accentColor : Color.clear, lineWidth: 2)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal)
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
