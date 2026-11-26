import Foundation
import TalosOrchestration
import TalosProjectLibrary
import TalosUI
import Testing

/// The Monitor's sub-function and time-range filters; the project filter is
/// the shell's selection, so it is not covered here.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Essential-Tools#monitor-screen
@Suite("Monitor filter")
struct MonitorFilterTests {
    private static let now = Date(timeIntervalSince1970: 10_000_000)
    private static let day: TimeInterval = 86400

    private static func record(_ subFunction: SubFunction, startedAt: Date) -> StoredSessionRecord {
        StoredSessionRecord(
            id: UUID(), project: ProjectIdentifier(rawValue: "p1"), subFunction: subFunction,
            agentName: "claude-code", outcome: .succeeded, startedAt: startedAt, duration: 1,
            toolCallCount: 0, approvalCount: 0, denialCount: 0, retryCount: 0, tokenOverheadRatio: 0
        )
    }

    @Test("Each preset ends now and starts its span earlier")
    func presetIntervals() {
        let start = { (range: MonitorTimeRange) in range.interval(endingAt: Self.now).start }
        #expect(start(.last24Hours) == Self.now.addingTimeInterval(-Self.day))
        #expect(start(.last7Days) == Self.now.addingTimeInterval(-7 * Self.day))
        #expect(start(.last30Days) == Self.now.addingTimeInterval(-30 * Self.day))
        #expect(MonitorTimeRange.allTime.interval(endingAt: Self.now).start == .distantPast)
        #expect(MonitorTimeRange.last7Days.interval(endingAt: Self.now).end == Self.now)
    }

    @Test("The time range drops sessions that started before it")
    func timeRangeDropsOlderSessions() {
        let recent = Self.record(.assistant, startedAt: Self.now.addingTimeInterval(-Self.day / 2))
        let old = Self.record(.assistant, startedAt: Self.now.addingTimeInterval(-2 * Self.day))
        let kept = MonitorFilter(timeRange: .last24Hours).apply(to: [recent, old], now: Self.now)
        #expect(kept.map(\.id) == [recent.id])
    }

    @Test("The sub-function filter keeps only that sub-function; All keeps every one")
    func subFunctionMatching() {
        #expect(MonitorSubFunctionFilter.automator.includes(.automator))
        #expect(!MonitorSubFunctionFilter.automator.includes(.assistant))
        #expect(MonitorSubFunctionFilter.all.includes(.advisor))
        #expect(MonitorFilter().timeRange == .last7Days)
    }
}
