import Foundation
import TalosAdapters
import TalosOrchestration
import TalosProjectLibrary
import TalosUI
import Testing

/// The chart plots only what the agent reported: a session with no token count
/// is counted as not plotted, never drawn as a zero bar.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Foundations-Content-and-Voice#cost-copy
@Suite("Monitor token chart")
struct MonitorTokenChartTests {
    private static func record(_ report: TokenReport?) -> StoredSessionRecord {
        StoredSessionRecord(
            id: UUID(), project: ProjectIdentifier(rawValue: "p1"), subFunction: .assistant,
            agentName: "claude-code", outcome: .succeeded, startedAt: .now, duration: 1,
            toolCallCount: 0, approvalCount: 0, denialCount: 0, retryCount: 0, tokenOverheadRatio: 0,
            tokenReport: report
        )
    }

    @Test("Measured sessions are plotted with every reported token; the rest are counted, not zeroed")
    func plotsOnlyMeasuredSessions() {
        let data = MonitorTokenChartData(records: [
            Self.record(.measured(TokenCounts(input: 10, output: 5, cacheCreation: 3, cacheRead: 2), model: "m")),
            Self.record(.unavailable(TokenUsageUnavailable(reason: .unrecognizedFormat, agentVersion: "1"))),
            Self.record(nil),
            Self.record(.measured(TokenCounts(input: 7, output: 0), model: "m"))
        ])
        #expect(data.points.map(\.totalTokens) == [20, 7])
        #expect(data.points.map(\.label) == ["Session 1", "Session 4"])
        #expect(data.notPlottedCount == 2)
        #expect(
            data.summary
                == "Tokens per session: 2 sessions plotted; 2 not plotted (no token count). Each value is listed below."
        )
    }

    @Test("With nothing missing the summary names no exclusion")
    func summaryWithoutExclusion() {
        let report = TokenReport.measured(TokenCounts(input: 1, output: 0), model: "m")
        let data = MonitorTokenChartData(records: [Self.record(report)])
        #expect(data.summary == "Tokens per session: 1 session plotted. Each value is listed below.")
    }
}
