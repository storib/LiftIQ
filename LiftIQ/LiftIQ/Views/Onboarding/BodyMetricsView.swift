import SwiftUI

struct BodyMetricsView: View {
    @Bindable var viewModel: OnboardingViewModel

    var body: some View {
        VStack(spacing: 24) {
            Text("Body Metrics")
                .font(.title2.bold())
            Text("Help us tailor your program (Optional)")
                .foregroundStyle(.secondary)

            VStack(spacing: 20) {
                // Unit system toggle
                Picker("Unit System", selection: $viewModel.unitSystem) {
                    Text("Metric (kg/cm)").tag(UnitSystem.metric)
                    Text("Imperial (lb/in)").tag(UnitSystem.imperial)
                }
                .pickerStyle(.segmented)

                // Body weight
                VStack(alignment: .leading, spacing: 8) {
                    Text("Body Weight")
                        .font(.subheadline.weight(.semibold))
                    HStack {
                        TextField("0", text: $viewModel.bodyWeight)
                            .keyboardType(.decimalPad)
                            .padding()
                            .background(Color(.secondarySystemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        Text(viewModel.unitSystem == .metric ? "kg" : "lb")
                            .foregroundStyle(.secondary)
                            .frame(width: 30)
                    }
                }

                // Height
                VStack(alignment: .leading, spacing: 8) {
                    Text("Height")
                        .font(.subheadline.weight(.semibold))
                    HStack {
                        TextField("0", text: $viewModel.height)
                            .keyboardType(.decimalPad)
                            .padding()
                            .background(Color(.secondarySystemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        Text(viewModel.unitSystem == .metric ? "cm" : "in")
                            .foregroundStyle(.secondary)
                            .frame(width: 30)
                    }
                }
            }
            .padding(.horizontal)

            Spacer()
        }
        .padding(.top, 32)
    }
}
