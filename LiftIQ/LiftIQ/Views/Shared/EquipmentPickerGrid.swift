import SwiftUI

/// Preset cards plus a per-item grid over a set of equipment. Shared by
/// onboarding and the gym-setup editor.
struct EquipmentPickerGrid: View {
    @Binding var selection: Set<Equipment>

    private let columns = [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
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
        let isActive = preset.equipment == selection
        return Button {
            selection = preset.equipment
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
                let isSelected = selection.contains(equipment)
                Button {
                    if isSelected {
                        selection.remove(equipment)
                    } else {
                        selection.insert(equipment)
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
                    .background(isSelected ? Color.accentColor.opacity(0.15) : Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(equipment.displayName)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(.horizontal)
    }
}
