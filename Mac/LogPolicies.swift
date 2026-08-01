import Foundation

struct UnknownControlTypeLogPolicy {
    enum Action: Equatable {
        case logType(String)
        case logSuppression(limit: Int)
        case none
    }

    private let capacity: Int
    private var loggedTypes: Set<String> = []
    private var reportedSuppression = false

    init(capacity: Int = 16) {
        precondition(capacity > 0)
        self.capacity = capacity
    }

    mutating func record(_ type: String) -> Action {
        if loggedTypes.contains(type) { return .none }
        guard loggedTypes.count < capacity else {
            guard !reportedSuppression else { return .none }
            reportedSuppression = true
            return .logSuppression(limit: capacity)
        }
        loggedTypes.insert(type)
        return .logType(type)
    }
}

struct ThrottledFailureLogPolicy {
    struct Report: Equatable {
        let status: Int32
        let count: Int
    }

    enum Action: Equatable {
        case report(Report)
        case schedule(after: TimeInterval)
        case none
    }

    private let interval: TimeInterval
    private var lastReportAt: TimeInterval?
    private var pendingCount = 0
    private var latestStatus: Int32 = 0
    private var reportScheduled = false

    init(interval: TimeInterval = 1) {
        precondition(interval > 0)
        self.interval = interval
    }

    mutating func record(status: Int32, at time: TimeInterval) -> Action {
        pendingCount += 1
        latestStatus = status

        guard let lastReportAt else {
            return .report(takeReport(at: time))
        }
        if !reportScheduled, time - lastReportAt >= interval {
            return .report(takeReport(at: time))
        }
        guard !reportScheduled else { return .none }
        reportScheduled = true
        return .schedule(after: max(0, lastReportAt + interval - time))
    }

    mutating func flush(at time: TimeInterval) -> Report? {
        reportScheduled = false
        guard pendingCount > 0 else { return nil }
        return takeReport(at: time)
    }

    private mutating func takeReport(at time: TimeInterval) -> Report {
        let report = Report(status: latestStatus, count: pendingCount)
        pendingCount = 0
        lastReportAt = time
        return report
    }
}
