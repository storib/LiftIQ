import XCTest
@testable import LiftIQ

final class AuthValidationTests: XCTestCase {

    // MARK: - EmailValidator

    func testAcceptsOrdinaryEmails() {
        XCTAssertTrue(EmailValidator.isPlausible("adrian@example.com"))
        XCTAssertTrue(EmailValidator.isPlausible("first.last+tag@sub.domain.co"))
    }

    func testRejectsImplausibleEmails() {
        XCTAssertFalse(EmailValidator.isPlausible(""))
        XCTAssertFalse(EmailValidator.isPlausible("no-at-sign.com"))
        XCTAssertFalse(EmailValidator.isPlausible("missing@domain"))
        XCTAssertFalse(EmailValidator.isPlausible("spaces in@mail.com"))
        XCTAssertFalse(EmailValidator.isPlausible("trailing@dot."))
    }

    // MARK: - PasswordStrength

    func testShortPasswordsAreWeak() {
        XCTAssertEqual(PasswordStrength.evaluate(""), .weak)
        XCTAssertEqual(PasswordStrength.evaluate("abc12"), .weak)
        XCTAssertEqual(PasswordStrength.evaluate("abcdef"), .weak)
    }

    func testMixedMediumPasswordsAreFair() {
        XCTAssertEqual(PasswordStrength.evaluate("abcd1234"), .fair)
        XCTAssertEqual(PasswordStrength.evaluate("lowercaseonly"), .fair)
    }

    func testLongMixedPasswordsAreStrong() {
        XCTAssertEqual(PasswordStrength.evaluate("Abcdef123456"), .strong)
        XCTAssertEqual(PasswordStrength.evaluate("Correct-Horse-9"), .strong)
    }

    // MARK: - SignUpViewModel form validation

    @MainActor
    func testFormInvalidUntilAllFieldsValid() {
        let vm = SignUpViewModel()
        XCTAssertFalse(vm.isFormValid)

        vm.displayName = "Adrian"
        vm.email = "adrian@example.com"
        vm.password = "secret1"
        vm.confirmPassword = "secret1"
        XCTAssertTrue(vm.isFormValid)
    }

    @MainActor
    func testFormInvalidWithBadEmail() {
        let vm = SignUpViewModel()
        vm.displayName = "Adrian"
        vm.email = "not-an-email"
        vm.password = "secret1"
        vm.confirmPassword = "secret1"
        XCTAssertFalse(vm.isFormValid)
    }

    @MainActor
    func testFormInvalidWithMismatchedPasswords() {
        let vm = SignUpViewModel()
        vm.displayName = "Adrian"
        vm.email = "adrian@example.com"
        vm.password = "secret1"
        vm.confirmPassword = "secret2"
        XCTAssertFalse(vm.isFormValid)
        XCTAssertTrue(vm.passwordMismatch)
    }

    // MARK: - ForgotPasswordViewModel

    @MainActor
    func testForgotPasswordSubmitGating() {
        let vm = ForgotPasswordViewModel()
        XCTAssertFalse(vm.canSubmit)

        vm.email = "  adrian@example.com  "
        XCTAssertEqual(vm.trimmedEmail, "adrian@example.com")
        XCTAssertTrue(vm.canSubmit)

        vm.email = "nope"
        XCTAssertFalse(vm.canSubmit)
    }

    @MainActor
    func testTrimmingHandlesPastedNewlines() {
        let forgot = ForgotPasswordViewModel()
        forgot.email = "adrian@example.com\n"
        XCTAssertEqual(forgot.trimmedEmail, "adrian@example.com")
        XCTAssertTrue(forgot.canSubmit)

        let signUp = SignUpViewModel()
        signUp.email = "adrian@example.com\n"
        XCTAssertTrue(signUp.isEmailValid)
    }
}
