import TalosAdapters

/// The < 5% Talos-added token overhead budget, as arithmetic.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Vision-and-Principles#budgets-that-make-the-above-testable
public enum TokenOverheadBudget {
    /// The budget is "< 5% of session tokens", so a figure at 5% already fails
    /// it. Compared as `injected × 20 >= session` rather than on a `Double`,
    /// so a session at exactly 5% is never misjudged by rounding.
    public static func isExceeded(injected: Int, sessionTokens: Int) -> Bool {
        sessionTokens > 0 && injected * percentDivisor >= sessionTokens
    }

    /// `100 / 5` — the reciprocal of the budget fraction.
    private static let percentDivisor = 20
}

/// One session's overhead: what Talos injected against the total tokens the
/// agent reported. Absent (`nil` from the initializer) when the agent reported
/// no count, because that supplies no denominator.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Essential-Tools#how-token-overhead-is-computed
public struct SessionOverhead: Equatable, Sendable {
    public let injected: InjectedTokens
    /// Input, output, cache creation, and cache read — everything the agent
    /// reported for the session.
    public let sessionTokens: Int

    public init?(injected: InjectedTokens, report: TokenReport?) {
        guard case let .measured(counts, _)? = report else { return nil }
        let total = counts.input + counts.output + (counts.cacheCreation ?? 0) + (counts.cacheRead ?? 0)
        guard total > 0 else { return nil }
        self.injected = injected
        sessionTokens = total
    }

    public var ratio: Double {
        Double(injected.total) / Double(sessionTokens)
    }

    public var exceedsBudget: Bool {
        TokenOverheadBudget.isExceeded(injected: injected.total, sessionTokens: sessionTokens)
    }
}

/// The overhead across a set of sessions, pooled: `Σ injected ÷ Σ session
/// tokens` over the sessions that could be measured. Never a mean of ratios,
/// so a tiny session cannot move the gate as far as a large one.
///
/// The coverage travels with the figure: a session with no agent token count,
/// or none recorded for what Talos injected, is excluded and counted in
/// `excludedCount`, so the figure never reads as measured over more than it was.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Essential-Tools#how-token-overhead-is-computed
public struct OverheadAggregate: Equatable, Sendable {
    public let measuredCount: Int
    public let excludedCount: Int
    public let injectedTotal: Int
    public let sessionTokenTotal: Int

    public init(records: some Sequence<StoredSessionRecord>) {
        var measured = 0, excluded = 0, injected = 0, session = 0
        for record in records {
            guard let injectedTokens = record.injectedTokens,
                  let overhead = SessionOverhead(injected: injectedTokens, report: record.tokenReport)
            else {
                excluded += 1
                continue
            }
            measured += 1
            injected += overhead.injected.total
            session += overhead.sessionTokens
        }
        measuredCount = measured
        excludedCount = excluded
        injectedTotal = injected
        sessionTokenTotal = session
    }

    /// The pooled fraction, or `nil` when no session was measurable — an
    /// empty or all-excluded set has no overhead to state, and a `0` would read
    /// as a measurement nobody made.
    public var ratio: Double? {
        sessionTokenTotal == 0 ? nil : Double(injectedTotal) / Double(sessionTokenTotal)
    }

    public var exceedsBudget: Bool {
        TokenOverheadBudget.isExceeded(injected: injectedTotal, sessionTokens: sessionTokenTotal)
    }
}

public extension SessionOverhead {
    /// This stored session's overhead, or `nil` when it cannot be measured.
    init?(record: StoredSessionRecord) {
        guard let injected = record.injectedTokens else { return nil }
        self.init(injected: injected, report: record.tokenReport)
    }
}
