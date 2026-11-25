import Foundation
import TalosAdapters
import TalosOrchestration
import TalosProjectLibrary
import Testing

/// Talos-added token overhead as
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Essential-Tools#how-token-overhead-is-computed
/// fixes it: injected tokens over the agent's own session total, pooled across
/// sessions, with the exclusion counted rather than silent.
@Suite("Token overhead")
struct TokenOverheadTests {
    private static func report(
        input: Int, output: Int, cacheCreation: Int? = nil, cacheRead: Int? = nil
    ) -> TokenReport {
        .measured(
            TokenCounts(input: input, output: output, cacheCreation: cacheCreation, cacheRead: cacheRead),
            model: "test-model"
        )
    }

    private static func record(
        injected: InjectedTokens?,
        report: TokenReport?
    ) -> StoredSessionRecord {
        StoredSessionRecord(
            id: UUID(),
            project: ProjectIdentifier(rawValue: "p1"),
            subFunction: .assistant,
            agentName: "claude-code",
            outcome: .succeeded,
            startedAt: Date(timeIntervalSince1970: 1000),
            duration: 1,
            toolCallCount: 0,
            approvalCount: 0,
            denialCount: 0,
            retryCount: 0,
            tokenOverheadRatio: 0,
            tokenReport: report,
            injectedTokens: injected
        )
    }

    private static func injected(_ total: Int) -> InjectedTokens {
        InjectedTokens(bySource: [.guideline: total], framing: 0)
    }

    @Test("A session's overhead is injected tokens over the agent's whole reported total, cache included")
    func sessionRatioCountsEveryReportedToken() throws {
        let overhead = try #require(SessionOverhead(
            injected: Self.injected(100),
            report: Self.report(input: 400, output: 100, cacheCreation: 300, cacheRead: 200)
        ))
        #expect(overhead.sessionTokens == 1000)
        #expect(overhead.ratio == 0.1)
    }

    @Test("Injected tokens are the parts plus the framing, in a fixed order with framing last")
    func injectedTotalAndOrder() {
        let injected = InjectedTokens(bySource: [.memories: 5, .guideline: 10], framing: 3)
        #expect(injected.total == 18)
        #expect(injected.orderedSources.map(\.label) == ["guideline", "memories", "framing"])
    }

    @Test("The aggregate is pooled, not a mean of ratios: a tiny session cannot move it like a large one")
    func aggregateIsPooled() throws {
        let tiny = Self.record(injected: Self.injected(100), report: Self.report(input: 1000, output: 0))
        let large = Self.record(injected: Self.injected(10), report: Self.report(input: 100_000, output: 0))
        let aggregate = OverheadAggregate(records: [tiny, large])

        let ratio = try #require(aggregate.ratio)
        // The mean of 10% and 0.01% would be ~5%; the pooled figure is 110 / 101,000.
        #expect(ratio < 0.002)
        #expect(aggregate.measuredCount == 2)
        #expect(aggregate.excludedCount == 0)
    }

    @Test("A session with no agent token count is excluded and counted, never read as zero")
    func unmeasurableSessionsAreExcludedAndCounted() throws {
        let measured = Self.record(injected: Self.injected(10), report: Self.report(input: 1000, output: 0))
        let noReport = Self.record(injected: Self.injected(10), report: nil)
        let unparsed = Self.record(
            injected: Self.injected(10),
            report: .unavailable(TokenUsageUnavailable(reason: .unrecognizedFormat, agentVersion: "2.1.246"))
        )
        let noInjectedRecord = Self.record(injected: nil, report: Self.report(input: 1000, output: 0))

        let aggregate = OverheadAggregate(records: [measured, noReport, unparsed, noInjectedRecord])

        #expect(aggregate.measuredCount == 1)
        #expect(aggregate.excludedCount == 3)
        #expect(try #require(aggregate.ratio) == 0.01)
    }

    @Test("A set with nothing measurable has no ratio, not a zero")
    func nothingMeasurableHasNoRatio() {
        let aggregate = OverheadAggregate(records: [Self.record(injected: Self.injected(10), report: nil)])
        #expect(aggregate.ratio == nil)
        #expect(aggregate.exceedsBudget == false)
    }

    @Test("A resumed turn injects nothing: it is measured at zero, not excluded")
    func resumedTurnIsMeasuredAtZero() throws {
        let resumed = Self.record(
            injected: AssembledContext.none(rawPromptTokenEstimate: 10).injectedTokens,
            report: Self.report(input: 500, output: 500)
        )
        let aggregate = OverheadAggregate(records: [resumed])
        #expect(aggregate.measuredCount == 1)
        #expect(try #require(aggregate.ratio) == 0)
    }

    /// "< 5% of session tokens" — so exactly 5% already breaches it.
    /// https://github.com/CalixtoTheBugHunter/talos/wiki/Vision-and-Principles#budgets-that-make-the-above-testable
    @Test("The budget is exceeded at exactly 5% and not at just under it")
    func budgetBoundary() {
        #expect(TokenOverheadBudget.isExceeded(injected: 50, sessionTokens: 1000))
        #expect(TokenOverheadBudget.isExceeded(injected: 49, sessionTokens: 1000) == false)
        #expect(TokenOverheadBudget.isExceeded(injected: 1, sessionTokens: 0) == false)
    }
}
