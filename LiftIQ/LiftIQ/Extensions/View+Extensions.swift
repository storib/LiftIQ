import SwiftUI

extension View {
    func cardStyle() -> some View {
        self
            .padding()
            .background(Color.liftCardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    func sectionHeader(_ title: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.secondary)
            self
        }
    }
}
