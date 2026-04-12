import SwiftUI

struct ExerciseSwapSheet: View {
    let currentExercise: Exercise?
    let onSelect: (Exercise) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ExerciseSearchView { exercise in
                onSelect(exercise)
                dismiss()
            }
            .navigationTitle("Swap Exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
}
