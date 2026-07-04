import Foundation

/// Light plausibility check used to gate auth form submission.
/// Firebase remains the source of truth for real address validation.
enum EmailValidator {
    static func isPlausible(_ email: String) -> Bool {
        email.range(
            of: #"^[^\s@]+@[^\s@]+\.[^\s@]{2,}$"#,
            options: .regularExpression
        ) != nil
    }
}
