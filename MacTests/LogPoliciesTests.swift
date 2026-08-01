import XCTest

final class UnknownControlTypeLogPolicyTests: XCTestCase {
    func testLogsEachTypeOnlyOnce() {
        var policy = UnknownControlTypeLogPolicy(capacity: 2)

        XCTAssertEqual(policy.record("pencil"), .logType("pencil"))
        XCTAssertEqual(policy.record("pencil"), .none)
        XCTAssertEqual(policy.record("proximity"), .logType("proximity"))
    }

    func testReportsCapacityOnceInsteadOfSilentlyDroppingLaterTypes() {
        var policy = UnknownControlTypeLogPolicy(capacity: 2)
        _ = policy.record("first")
        _ = policy.record("second")

        XCTAssertEqual(policy.record("third"), .logSuppression(limit: 2))
        XCTAssertEqual(policy.record("fourth"), .none)
    }
}

final class ThrottledFailureLogPolicyTests: XCTestCase {
    func testFlushReportsFailuresSuppressedAtTheEndOfABurst() {
        var policy = ThrottledFailureLogPolicy(interval: 1)

        XCTAssertEqual(policy.record(status: -1, at: 10),
                       .report(.init(status: -1, count: 1)))
        XCTAssertEqual(policy.record(status: -1, at: 10.25), .schedule(after: 0.75))
        XCTAssertEqual(policy.record(status: -2, at: 10.5), .none)
        XCTAssertEqual(policy.flush(at: 11), .init(status: -2, count: 2))
        XCTAssertNil(policy.flush(at: 12))
    }

    func testReportsImmediatelyAgainAfterAnIdleInterval() {
        var policy = ThrottledFailureLogPolicy(interval: 1)
        _ = policy.record(status: -1, at: 10)

        XCTAssertEqual(policy.record(status: -2, at: 11),
                       .report(.init(status: -2, count: 1)))
    }
}
