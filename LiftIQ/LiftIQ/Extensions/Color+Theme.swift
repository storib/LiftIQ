import SwiftUI
import UIKit

/// LiftIQ colour tokens. Every value was chosen for a specific
/// foreground/background pairing (WCAG contrast, measured 2026-11):
///
/// - `AccentColor` (asset) — links, icons, selected tabs, toggles, tints.
///   Deep blue #315FD5 in light (5.0:1 on grouped background), bright
///   #7A9EFF in dark (≥5.4:1 on every dark surface). Never put white text
///   on it in dark mode — that pairing is only 3:1.
/// - `liftButtonFill` — the fill behind white text: #315FD5 light (5.6:1),
///   #3D68DD dark (5.0:1). Use for every filled primary button.
/// - Success / warning / danger use darker light-mode variants because the
///   system green and orange read at ~2.2:1 as text on white.
///
/// Colours that only distinguish things (superset groups, the tutorial's
/// page tints, guidance chips) are deliberately left as system hues.
extension Color {
    static let liftPrimary = Color.accentColor
    static let liftButtonFill = dynamic(light: 0x315FD5, dark: 0x3D68DD)
    static let liftBackground = Color(.systemGroupedBackground)
    static let liftCardBackground = Color(.secondarySystemGroupedBackground)
    /// Completed work. #1E7B34 light (5.3:1 on white); system green in dark.
    static let liftSuccess = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark ? .systemGreen : UIColor(hex: 0x1E7B34)
    })
    /// Needs attention. #C2410C light — kept apart from the PR amber; system
    /// orange in dark.
    static let liftWarning = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark ? .systemOrange : UIColor(hex: 0xC2410C)
    })
    /// Fill behind white text for attention actions (Resume, Finish at last
    /// set): 5.2:1 in both modes, where system orange was 2.2:1.
    static let liftWarningFill = dynamic(light: 0xC2410C, dark: 0xC2410C)
    /// Background of an attention card. An opaque warm surface rather than a
    /// translucent tint: #C2410C at 10% over the grouped grey read as rose.
    static let liftWarningSurface = dynamic(light: 0xFDF0E2, dark: 0x352617)
    /// Destructive and errors. #C4261D light (5.8:1 on white); system red in dark.
    static let liftDanger = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark ? .systemRed : UIColor(hex: 0xC4261D)
    })
    /// PR gold. Yellow is near-invisible on light surfaces, so light mode uses
    /// a darker amber (#B45309) while dark mode keeps the bright yellow.
    static let liftPR = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark ? .systemYellow : UIColor(hex: 0xB45309)
    })
    static let warmUpSet = Color.gray.opacity(0.5)
    static let workingSet = Color.primary

    private static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light) })
    }
}

private extension UIColor {
    convenience init(hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}

/// The two shapes most screens need, so cards and primary buttons stop
/// drifting between eight corner radii.
enum LiftLayout {
    static let cardRadius: CGFloat = 16
    static let controlRadius: CGFloat = 12
    static let cardPadding: CGFloat = 16
}

extension View {
    /// Standard neutral card. An attention surface (`.liftWarningSurface`)
    /// only for things that need action now — a session left running, not a
    /// suggestion.
    func liftCard(attention surface: Color? = nil) -> some View {
        padding(LiftLayout.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(surface ?? Color.liftCardBackground)
            .clipShape(RoundedRectangle(cornerRadius: LiftLayout.cardRadius))
    }
}

/// Full-width filled button with white text on `liftButtonFill` (or another
/// fill that clears 4.5:1 with white, e.g. `liftWarningFill`).
struct LiftFilledButtonStyle: ButtonStyle {
    var fill: Color = .liftButtonFill
    var font: Font = .headline
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(font)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(fill)
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: LiftLayout.controlRadius))
            .opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.5)
    }
}

extension ButtonStyle where Self == LiftFilledButtonStyle {
    static var liftFilled: LiftFilledButtonStyle { LiftFilledButtonStyle() }
    static func liftFilled(fill: Color, font: Font = .headline) -> LiftFilledButtonStyle {
        LiftFilledButtonStyle(fill: fill, font: font)
    }
}

/// Secondary full-width button: accent text on a 12% accent tint (4.8:1
/// light, 5.4:1 dark). For actions inside supporting cards, so they never
/// out-shout the screen's one filled button.
struct LiftTintedButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(Color.accentColor.opacity(0.12))
            .foregroundStyle(Color.accentColor)
            .clipShape(RoundedRectangle(cornerRadius: LiftLayout.controlRadius))
            .opacity(isEnabled ? (configuration.isPressed ? 0.7 : 1) : 0.5)
    }
}

extension ButtonStyle where Self == LiftTintedButtonStyle {
    static var liftTinted: LiftTintedButtonStyle { LiftTintedButtonStyle() }
}
