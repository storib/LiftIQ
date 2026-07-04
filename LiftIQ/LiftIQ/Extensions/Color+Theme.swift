import SwiftUI
import UIKit

extension Color {
    static let liftPrimary = Color("AccentColor")
    static let liftSecondary = Color.blue.opacity(0.8)
    static let liftBackground = Color(.systemGroupedBackground)
    static let liftCardBackground = Color(.secondarySystemGroupedBackground)
    static let liftSuccess = Color.green
    static let liftWarning = Color.orange
    static let liftDanger = Color.red
    /// PR gold. Yellow is near-invisible on light surfaces, so light mode uses
    /// a darker amber (#B45309) while dark mode keeps the bright yellow.
    static let liftPR = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor.systemYellow
            : UIColor(red: 0xB4 / 255, green: 0x53 / 255, blue: 0x09 / 255, alpha: 1)
    })
    static let warmUpSet = Color.gray.opacity(0.5)
    static let workingSet = Color.primary
}
