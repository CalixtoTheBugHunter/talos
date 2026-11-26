import Foundation
import TalosAdapters
import TalosOrchestration
import TalosProjectLibrary
import TalosUI

/// The Monitor cost seed, split from `TalosAppUITestSeeding` for the same
/// reason the file itself was split from `TalosApp`: to keep each type's body
/// under the line-count limits, not because the helper differs from the others.
extension TalosAppUITestSeeding {
    /// Exists only so `TalosUITests` can drive the real, mounted Monitor
    /// without a real project or database — the same reason the seeds beside
    /// it exist. The seeded records go through the same loader and filter as
    /// live ones. Seeds every cost line (a priced run, an unknown model, an
    /// unparsable token report) and every outcome. Forces the Monitor surface
    /// and a project, since the persisted sidebar selection survives across
    /// launches and would otherwise leave the seeded list off screen.
    /// https://github.com/CalixtoTheBugHunter/talos/wiki/Essential-Tools#monitor-screen
    static func seedMonitorCost(navigation: ShellNavigationModel) {
        guard isSeedingMonitorCost else { return }
        navigation.selectedProjectRoot = URL(fileURLWithPath: "/ui-test-project", isDirectory: true)
        navigation.selectedSurface = .monitor
    }

    /// The seeded records loader, or `nil` outside the Monitor UI test.
    static var monitorCostSeedLoader: (@Sendable (URL, DateInterval) async throws -> [StoredSessionRecord])? {
        guard isSeedingMonitorCost else { return nil }
        let records = seededMonitorCostRecords(endingAt: .now)
        return { _, interval in records.filter { interval.contains($0.startedAt) } }
    }

    private static var isSeedingMonitorCost: Bool {
        ProcessInfo.processInfo.environment["TALOS_UI_TEST_MONITOR_COST"] != nil
    }

    /// One seeded Monitor session: what ran, how it ended, and the token
    /// report the cost estimate is mapped from.
    private struct SeededCostSession {
        let subFunction: SubFunction
        let outcome: SessionOutcomeClassification
        let duration: TimeInterval
        let report: TokenReport?
        let injected: InjectedTokens?
    }

    private static let seededMonitorCostSessions: [SeededCostSession] = [
        SeededCostSession(subFunction: .automator, outcome: .succeeded, duration: seededLongDuration, report: .measured(
            TokenCounts(
                input: seededPricedInput,
                output: seededPricedOutput,
                cacheCreation: seededPricedCacheWrite,
                cacheRead: seededPricedCacheRead
            ),
            model: "global.anthropic.claude-opus-5"
        ), injected: InjectedTokens(bySource: [.guideline: seededOverBudgetInjected], framing: 0)),
        SeededCostSession(
            subFunction: .assistant, outcome: .succeeded, duration: seededShortDuration, report: .measured(
                TokenCounts(input: seededUnknownInput, output: seededUnknownOutput),
                model: "experimental-model-x"
            ), injected: InjectedTokens(bySource: [.guideline: seededUnderBudgetInjected], framing: 0)
        ),
        SeededCostSession(
            subFunction: .advisor, outcome: .succeeded, duration: seededShortDuration, report: .unavailable(
                TokenUsageUnavailable(reason: .unrecognizedFormat, agentVersion: "2.1.246")
            ), injected: InjectedTokens(bySource: [.guideline: seededUnderBudgetInjected], framing: 0)
        ),
        // No token record: excluded from overhead, not plotted, never a zero.
        SeededCostSession(
            subFunction: .assistant, outcome: .failed, duration: seededShortDuration, report: nil, injected: nil
        ),
        SeededCostSession(
            subFunction: .automator, outcome: .denied, duration: seededShortDuration, report: nil, injected: nil
        ),
        SeededCostSession(
            subFunction: .assistant, outcome: .stopped, duration: seededShortDuration, report: nil, injected: nil
        )
    ]

    /// Oldest first, all inside the last hour, so the default "Last 7 days"
    /// shows every one.
    private static func seededMonitorCostRecords(endingAt now: Date) -> [StoredSessionRecord] {
        let count = Double(seededMonitorCostSessions.count)
        let base = now.addingTimeInterval(-count * seededMonitorCostSpacing)
        return seededMonitorCostSessions.enumerated().map { index, session in
            StoredSessionRecord(
                id: UUID(),
                project: ProjectIdentifier(rawValue: "ui-test-project"),
                subFunction: session.subFunction,
                agentName: "claude-code",
                outcome: session.outcome,
                startedAt: base.addingTimeInterval(Double(index) * seededMonitorCostSpacing),
                duration: session.duration,
                toolCallCount: 0,
                approvalCount: 0,
                denialCount: 0,
                retryCount: 0,
                tokenOverheadRatio: seededMonitorCostOverheadRatio,
                tokenReport: session.report,
                injectedTokens: session.injected
            )
        }
    }

    private static let seededPricedInput = 2
    private static let seededPricedOutput = 4
    private static let seededPricedCacheWrite = 2637
    private static let seededPricedCacheRead = 16509
    /// Over 5% of the priced session's 19,152 tokens; under 5% of the unknown
    /// model's 1,540. The unparsable session has no agent count, so it is
    /// excluded from the overhead figure whatever its injected share.
    private static let seededOverBudgetInjected = 1500
    private static let seededUnderBudgetInjected = 20
    private static let seededUnknownInput = 1200
    private static let seededUnknownOutput = 340
    private static let seededMonitorCostSpacing: TimeInterval = 120
    private static let seededShortDuration: TimeInterval = 12
    private static let seededLongDuration: TimeInterval = 125
    private static let seededMonitorCostOverheadRatio = 0.03
}
