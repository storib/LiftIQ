import XCTest

final class LiftIQUITests: XCTestCase {

    func testAppLaunches() throws {
        let app = XCUIApplication()
        app.launch()

        // Verify the welcome screen appears
        XCTAssertTrue(app.staticTexts["LiftIQ"].exists)
    }
}
