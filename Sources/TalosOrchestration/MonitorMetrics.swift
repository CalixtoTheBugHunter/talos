import Foundation
import TalosAdapters
import TalosProjectLibrary

/// The read half of the session record store. Holding only this, a consumer
/// can query records and has no path to write or delete one.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Decision-Log#engineering-decisions
public protocol SessionRecordReading: Sendable {
    func records(project: ProjectIdentifier, from start: Date, to end: Date) async throws -> [StoredSessionRecord]
}

/// One project's Monitor data over a time range, as aggregates only: no
/// per-session record and no transcript text, so a guideline that later reads
/// it costs a bounded handful of tokens rather than the history itself.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Essential-Tools#monitor-screen
public struct MonitorMetrics: Equatable, Sendable {
    public let sessionCount: Int
    public let outcomes: SessionMetricsSummary
    public let totalDuration: TimeInterval
    public let toolCallCount: Int
    public let approvalCount: Int
    public let denialCount: Int
    public let retryCount: Int
    /// Sessions whose agent reported a token count, and those it did not. An
    /// unavailable count is counted here and never added as zero.
    /// https://github.com/CalixtoTheBugHunter/talos/wiki/Essential-Tools#when-the-log-format-changes
    public let measuredTokenSessionCount: Int
    public let unavailableTokenSessionCount: Int
    public let inputTokens: Int
    public let outputTokens: Int
    public let cacheCreationTokens: Int
    public let cacheReadTokens: Int
    public let overhead: OverheadAggregate

    public init(records: [StoredSessionRecord]) {
        sessionCount = records.count
        outcomes = SessionMetricsSummary(records: records)
        totalDuration = records.reduce(0) { $0 + $1.duration }
        toolCallCount = records.reduce(0) { $0 + $1.toolCallCount }
        approvalCount = records.reduce(0) { $0 + $1.approvalCount }
        denialCount = records.reduce(0) { $0 + $1.denialCount }
        retryCount = records.reduce(0) { $0 + $1.retryCount }
        overhead = OverheadAggregate(records: records)

        let counts = records.compactMap { record -> TokenCounts? in
            guard case let .measured(counts, _)? = record.tokenReport else { return nil }
            return counts
        }
        measuredTokenSessionCount = counts.count
        unavailableTokenSessionCount = records.count - counts.count
        inputTokens = counts.reduce(0) { $0 + $1.input }
        outputTokens = counts.reduce(0) { $0 + $1.output }
        cacheCreationTokens = counts.reduce(0) { $0 + ($1.cacheCreation ?? 0) }
        cacheReadTokens = counts.reduce(0) { $0 + ($1.cacheRead ?? 0) }
    }
}

/// The read-only query a guideline's prompt assembly may later consume.
/// Inert at MVP: nothing assembles its output into a prompt.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Essential-Tools#monitor-screen
public struct MonitorMetricsReader: Sendable {
    private let source: any SessionRecordReading

    public init(source: any SessionRecordReading) {
        self.source = source
    }

    public func metrics(project: ProjectIdentifier, from start: Date, to end: Date) async throws -> MonitorMetrics {
        try await MonitorMetrics(records: source.records(project: project, from: start, to: end))
    }
}
