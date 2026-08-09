import XCTest

final class LiftIQUITests: XCTestCase {

    func testAppLaunches() throws {
        let app = XCUIApplication()
        app.launch()

        // Verify the welcome screen appears (CI simulators cold-start slowly)
        XCTAssertTrue(app.staticTexts["LiftIQ"].waitForExistence(timeout: 30))
    }
}
