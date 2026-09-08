import XCTest
@testable import LiftIQ

@MainActor
final class RestTimerControllerTests: XCTestCase {

    private final class TestClock {
        var now: Date
        init(_ now: Date) { self.now = now }
    }

    private func makeTimer() -> (RestTimerController, TestClock) {
        let clock = TestClock(Date(timeIntervalSince1970: 1_700_000_000))
        return (RestTimerController(now: { clock.now }), clock)
    }

    func testBackgroundExpiryFinishesTimerSilently() {
        // Rest ended while backgrounded (the local notification already rang):
        // returning to the foreground must close the timer out, not re-ring it
        // through the normal tick path.
        let (controller, clock) = makeTimer()
        defer { controller.stop() }
        controller.start(seconds: 60)
        XCTAssertTrue(controller.isActive)
        XCTAssertEqual(controller.secondsRemaining, 60)

        clock.now += 120
        controller.refreshFromWallClock()

        XCTAssertFalse(controller.isActive)
        XCTAssertEqual(controller.secondsRemaining, 0)
    }

    func testRefreshMidRestResyncsFromWallClock() {
        let (controller, clock) = makeTimer()
        defer { controller.stop() }
        controller.start(seconds: 60)

        clock.now += 25
        controller.refreshFromWallClock()

        XCTAssertTrue(controller.isActive)
        XCTAssertEqual(controller.secondsRemaining, 35)
    }

    func testAdjustRecomputesRemainingFromWallClock() {
        let (controller, clock) = makeTimer()
        defer { controller.stop() }
        controller.start(seconds: 60)

        clock.now += 30
        controller.adjust(by: 30)

        XCTAssertEqual(controller.secondsRemaining, 60)
        XCTAssertTrue(controller.isActive)
    }

    func testAdjustPastZeroSkips() {
        let (controller, clock) = makeTimer()
        defer { controller.stop() }
        controller.start(seconds: 60)

        clock.now += 30
        controller.adjust(by: -60)

        XCTAssertFalse(controller.isActive)
        XCTAssertEqual(controller.secondsRemaining, 0)
    }

    func testOnStateChangeFiresOnTransitionsNotTicks() {
        let (controller, clock) = makeTimer()
        defer { controller.stop() }
        var changes = 0
        controller.onStateChange = { changes += 1 }

        controller.start(seconds: 60)
        XCTAssertEqual(changes, 1)
        XCTAssertNotNil(controller.endDate)

        clock.now += 10
        controller.refreshFromWallClock()     // mid-rest tick: no transition
        XCTAssertEqual(changes, 1)

        controller.adjust(by: 30)
        XCTAssertEqual(changes, 2)

        clock.now += 200
        controller.refreshFromWallClock()     // expiry
        XCTAssertEqual(changes, 3)
        XCTAssertNil(controller.endDate)

        controller.start(seconds: 30)
        controller.skip()
        XCTAssertEqual(changes, 5)

        controller.start(seconds: 30)
        controller.stop()
        XCTAssertEqual(changes, 7)
    }
}
