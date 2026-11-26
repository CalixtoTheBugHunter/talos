import Foundation
import TalosOrchestration
import TalosProjectLibrary

/// The Monitor's time-range presets. Each one ends at the moment it is asked
/// for, so reloading after a session ends includes that session.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Essential-Tools#monitor-screen
public enum MonitorTimeRange: String, CaseIterable, Identifiable, Sendable {
    case last24Hours
    case last7Days
    case last30Days
    case allTime

    public var id: String {
        rawValue
    }

    public var title: String {
        switch self {
        case .last24Hours: "Last 24 hours"
        case .last7Days: "Last 7 days"
        case .last30Days: "Last 30 days"
        case .allTime: "All time"
        }
    }

    /// The closed interval the store query reads, ending at `now`.
    public func interval(endingAt now: Date) -> DateInterval {
        let start: Date = switch self {
        case .last24Hours: now.addingTimeInterval(-Self.day)
        case .last7Days: now.addingTimeInterval(-Self.week * Self.day)
        case .last30Days: now.addingTimeInterval(-Self.month * Self.day)
        case .allTime: .distantPast
        }
        return DateInterval(start: start, end: now)
    }

    private static let day: TimeInterval = 86400
    private static let week: TimeInterval = 7
    private static let month: TimeInterval = 30
}

/// The Monitor's sub-function filter. Advisor and Self-improver are absent:
/// both are "Coming soon" and record no sessions, so an option for either
/// could only ever show nothing.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Foundations-Content-and-Voice#the-lexicon
public enum MonitorSubFunctionFilter: String, CaseIterable, Identifiable, Sendable {
    case all
    case assistant
    case automator

    public var id: String {
        rawValue
    }

    public var title: String {
        switch self {
        case .all: "All sub-functions"
        case .assistant: "Assistant"
        case .automator: "Automator"
        }
    }

    public func includes(_ subFunction: SubFunction) -> Bool {
        switch self {
        case .all: true
        case .assistant: subFunction == .assistant
        case .automator: subFunction == .automator
        }
    }
}

/// What the Monitor is showing. The project is chosen in the shell; this is
/// the rest of the filter.
public struct MonitorFilter: Equatable, Hashable, Sendable {
    public var timeRange: MonitorTimeRange
    public var subFunction: MonitorSubFunctionFilter

    public init(timeRange: MonitorTimeRange = .last7Days, subFunction: MonitorSubFunctionFilter = .all) {
        self.timeRange = timeRange
        self.subFunction = subFunction
    }

    /// The records this filter keeps, by sub-function and by start time.
    public func apply(to records: [StoredSessionRecord], now: Date) -> [StoredSessionRecord] {
        let interval = timeRange.interval(endingAt: now)
        return records.filter { subFunction.includes($0.subFunction) && interval.contains($0.startedAt) }
    }
}
