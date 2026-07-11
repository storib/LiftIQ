import SwiftUI

struct SetRowView: View {
    @Environment(\.colorScheme) private var colorScheme

    let exerciseLogIndex: Int
    let setIndex: Int
    let setNumber: Int
    let setType: SetType
    @Binding var weightText: String
    @Binding var repsText: String
    @Binding var rpeText: String
    let previousWeight: Double?
    let previousReps: Int?
    let isBodyweight: Bool
    let unitSystem: UnitSystem
    let isCompleted: Bool
    let isPersonalRecord: Bool
    var focusedField: FocusState<SetFieldFocus?>.Binding
    let onComplete: () -> Void
    let onUncomplete: () -> Void
    let onSetTypeChange: (SetType) -> Void

    var body: some View {
        HStack(spacing: 8) {
            // Set number / type label
            Menu {
                ForEach(SetType.allCases) { type in
                    Button {
                        onSetTypeChange(type)
                    } label: {
                        Label(type.displayName, systemImage: type == setType ? "checkmark" : "")
                    }
                }
            } label: {
                Text(setLabel)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(setLabelColor)
                    .frame(width: 32)
                    // Hit-area expansion only; the glyph and column width stay as-is.
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
            }

            // Weight input
            inputSurface(width: 60, field: .weight) {
                ZStack {
                    if weightText.isEmpty, let prev = previousWeight, prev > 0 {
                        Text(prev.formatted())
                            .foregroundStyle(.tertiary)
                            .font(.subheadline)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                            .accessibilityHidden(true)
                    } else if weightText.isEmpty && isBodyweight {
                        // Bodyweight movements need no load; typing a weight
                        // records *added* load (dip belt, vest).
                        Text("BW")
                            .foregroundStyle(.tertiary)
                            .font(.subheadline)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                            .accessibilityHidden(true)
                    }
                    TextField("", text: $weightText)
                        .keyboardType(.decimalPad)
                        .font(.subheadline)
                        .multilineTextAlignment(.center)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .focused(focusedField, equals: focusTarget(.weight))
                        .accessibilityLabel(isBodyweight ? "Added weight, optional" : "Weight")
                }
            }

            Text(UnitConversionService.weightLabel(for: unitSystem))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .frame(width: 18)

            // Reps input
            inputSurface(width: 44, field: .reps) {
                ZStack {
                    if repsText.isEmpty, let prev = previousReps, prev > 0 {
                        Text("\(prev)")
                            .foregroundStyle(.tertiary)
                            .font(.subheadline)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                            .accessibilityHidden(true)
                    }
                    TextField("", text: $repsText)
                        .keyboardType(.numberPad)
                        .font(.subheadline)
                        .multilineTextAlignment(.center)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .focused(focusedField, equals: focusTarget(.reps))
                        .accessibilityLabel("Reps")
                }
            }

            // RPE input (only for working sets)
            if setType == .working {
                inputSurface(width: 36, horizontalPadding: 6, field: .rpe) {
                    TextField("RPE", text: $rpeText)
                        .keyboardType(.decimalPad)
                        .font(.caption)
                        .multilineTextAlignment(.center)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .focused(focusedField, equals: focusTarget(.rpe))
                        .accessibilityLabel("RPE")
                }
            } else {
                Spacer()
                    .frame(width: 48)
            }

            Spacer()

            // Completion checkbox
            Button {
                if isCompleted {
                    onUncomplete()
                } else {
                    onComplete()
                }
            } label: {
                Image(systemName: checkboxIcon)
                    .font(.title3)
                    .foregroundStyle(checkboxColor)
                    // 44pt hit area without growing the glyph; trailing alignment
                    // keeps the icon lined up with the header's checkmark column.
                    .frame(minWidth: 44, minHeight: 44, alignment: .trailing)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isCompleted ? "Mark set \(setNumber) incomplete" : "Complete set \(setNumber)")
            .accessibilityValue(checkboxAccessibilityValue)
        }
        .padding(.horizontal, 12)
        // No vertical padding: the 44pt tap targets set the row height, which
        // keeps the row at the same overall height it had before.
        .background(rowBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(rowStrokeColor, lineWidth: 1)
        )
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isCompleted)
        // Stopgap for accessibility sizes: the fixed-width numeric columns clip
        // digits past xxLarge, so clamp the row and let minimumScaleFactor
        // absorb the rest until the row is rebuilt as a Grid.
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
    }

    // MARK: - Computed Helpers

    private func focusTarget(_ field: SetFieldFocus.Field) -> SetFieldFocus {
        SetFieldFocus(exerciseLogIndex: exerciseLogIndex, setIndex: setIndex, field: field)
    }

    private func inputSurface<Content: View>(
        width: CGFloat,
        horizontalPadding: CGFloat = 8,
        field: SetFieldFocus.Field,
        @ViewBuilder content: () -> Content
    ) -> some View {
        let isFocused = focusedField.wrappedValue == focusTarget(field)
        return content()
            .frame(width: width)
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, 6)
            .background(inputBackground(isFocused: isFocused))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(inputBorder(isFocused: isFocused), lineWidth: isFocused ? 1.5 : 1)
            }
            .shadow(
                color: inputShadow(isFocused: isFocused),
                radius: isFocused ? 4 : 2,
                y: isFocused ? 2 : 1
            )
            .animation(.easeOut(duration: 0.16), value: isFocused)
    }

    private func inputBackground(isFocused: Bool) -> Color {
        if isFocused { return Color.accentColor.opacity(colorScheme == .dark ? 0.16 : 0.08) }
        return colorScheme == .dark
            ? Color.white.opacity(0.07)
            : Color(.tertiarySystemBackground)
    }

    private func inputBorder(isFocused: Bool) -> Color {
        if isFocused { return Color.accentColor.opacity(0.8) }
        return colorScheme == .dark
            ? Color.white.opacity(0.13)
            : Color.black.opacity(0.06)
    }

    private func inputShadow(isFocused: Bool) -> Color {
        if isFocused { return Color.accentColor.opacity(colorScheme == .dark ? 0.24 : 0.14) }
        return Color.black.opacity(colorScheme == .dark ? 0.32 : 0.08)
    }

    private var checkboxAccessibilityValue: String {
        if isPersonalRecord { return "Completed, personal record" }
        return isCompleted ? "Completed" : "Not completed"
    }

    private var setLabel: String {
        switch setType {
        case .warmUp: return "W"
        case .dropSet: return "D"
        case .failureSet: return "F"
        case .working: return "\(setNumber)"
        }
    }

    private var setLabelColor: Color {
        switch setType {
        case .warmUp: return Color.warmUpSet
        case .dropSet: return Color.liftWarning
        case .failureSet: return Color.liftDanger
        case .working: return .primary
        }
    }

    private var checkboxIcon: String {
        if isPersonalRecord { return "star.circle.fill" }
        return isCompleted ? "checkmark.circle.fill" : "circle"
    }

    private var checkboxColor: Color {
        if isPersonalRecord { return Color.liftPR }
        return isCompleted ? Color.liftSuccess : .secondary
    }

    private var rowBackground: AnyShapeStyle {
        if isPersonalRecord {
            return AnyShapeStyle(
                LinearGradient(
                    colors: [Color.liftPR.opacity(0.14), Color.liftPR.opacity(0.06)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
        }
        if isCompleted {
            return AnyShapeStyle(
                LinearGradient(
                    colors: [Color.liftSuccess.opacity(0.12), Color.liftSuccess.opacity(0.05)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
        }
        if setType == .warmUp { return AnyShapeStyle(Color.warmUpSet.opacity(0.1)) }
        return AnyShapeStyle(Color.clear)
    }

    private var rowStrokeColor: Color {
        if isPersonalRecord { return Color.liftPR.opacity(0.25) }
        if isCompleted { return Color.liftSuccess.opacity(0.2) }
        return .clear
    }
}
