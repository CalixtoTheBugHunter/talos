import TalosAdapters
import TalosSafeguards

/// What ``SafeguardsApproved/run``'s `tokenObserver` receives: the adapter's
/// live report, paired with this run's fixed overhead ratio.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Session-Console#what-it-is
public struct SessionTokenUpdate: Equatable, Sendable {
    public let report: TokenReport
    public let contextOverheadRatio: Double

    public init(report: TokenReport, contextOverheadRatio: Double) {
        self.report = report
        self.contextOverheadRatio = contextOverheadRatio
    }
}

extension SafeguardsApproved {
    /// Reports the adapter's live usage plus this run's fixed overhead ratio,
    /// once before the first event and once per event after — event-driven,
    /// never a timer.
    /// https://github.com/CalixtoTheBugHunter/talos/wiki/Foundations-States-and-Feedback#nothing-polls
    func reportTokenUsage(
        collaborators: SessionRunCollaborators<some AgentAdapter, some SafeguardsGate>,
        tokenObserver: (@Sendable (SessionTokenUpdate) async -> Void)?
    ) async {
        guard let tokenObserver else { return }
        let update = await SessionTokenUpdate(
            report: collaborators.adapter.tokenUsage(),
            contextOverheadRatio: context.overheadRatio
        )
        await tokenObserver(update)
    }
}
