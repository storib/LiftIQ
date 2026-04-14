import SwiftUI

struct EquipmentView: View {
    @Bindable var viewModel: OnboardingViewModel

    let columns = [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        VStack(spacing: 24) {
            Text("Available Equipment")
                .font(.title2.bold())
            Text("Select everything you have access to")
                .foregroundStyle(.secondary)

            ScrollView {
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
        .padding(.top, 32)
    }
}
