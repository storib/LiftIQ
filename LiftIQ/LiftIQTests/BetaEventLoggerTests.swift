import XCTest
@testable import LiftIQ

final class BetaEventLoggerTests: XCTestCase {

    private final class RecordingWriter: BetaEventWriting, @unchecked Sendable {
        struct Write { let name: String; let props: [String: any Sendable]; let appVersion: String; let build: String }
        private let lock = NSLock()
        private var writes: [Write] = []
        let expectation = XCTestExpectation(description: "write")

        var all: [Write] { lock.withLock { writes } }

        func write(name: String, props: [String: any Sendable], appVersion: String, build: String) async throws {
            lock.withLock { writes.append(Write(name: name, props: props, appVersion: appVersion, build: build)) }
            expectation.fulfill()
        }
    }

    func testDisabledLoggerNeverWrites() async {
        let writer = RecordingWriter()
        writer.expectation.isInverted = true
        let logger = BetaEventLogger(writer: writer, isEnabled: { false })

        logger.log("app_open")

        await fulfillment(of: [writer.expectation], timeout: 0.3)
        XCTAssertTrue(writer.all.isEmpty)
    }

    func testEnabledLoggerWritesWithVersionAndBuild() async {
        let writer = RecordingWriter()
        let logger = BetaEventLogger(writer: writer, isEnabled: { true })

        logger.log("session_started", ["source": "dashboard"])

        await fulfillment(of: [writer.expectation], timeout: 2)
        let write = writer.all.first
        XCTAssertEqual(write?.name, "session_started")
        XCTAssertEqual(write?.props["source"] as? String, "dashboard")
        XCTAssertFalse(write?.appVersion.isEmpty ?? true)
        XCTAssertFalse(write?.build.isEmpty ?? true)
    }
}
