import TalosAdapters
import TalosSafeguards

extension SafeguardsApproved {
    /// Runs the board conflict check on an allowed decision and, when the write
    /// is abandoned, returns a denied decision carrying the abandoning actor —
    /// the user for a chosen keep/open, Talos for a prompt that could not be
    /// presented. Any other decision passes through untouched, and the `Bool`
    /// tells ``carry(_:collaborators:metrics:retries:transcript:)`` a conflict
    /// abandon apart from a gate denial so it stays out of the retry tracker.
    func resolveBoardConflict(
        _ decision: SafeguardsDecision,
        request: AgentPermissionRequest,
        collaborators: SessionRunCollaborators<some AgentAdapter, some SafeguardsGate>
    ) async -> (decision: SafeguardsDecision, abandoned: Bool) {
        guard decision.outcome == .allowed,
              let resolver = collaborators.boardConflict,
              case let .abandon(actor) = await resolver.resolve(request)
        else {
            return (decision, false)
        }
        return (
            SafeguardsDecision(
                outcome: .denied,
                action: decision.action,
                classification: decision.classification,
                actor: actor
            ),
            true
        )
    }
}
