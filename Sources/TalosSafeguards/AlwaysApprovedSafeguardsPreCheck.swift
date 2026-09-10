/// A ``SafeguardsPreCheck`` that always approves. Stage 4 of the shared
/// session pipeline names "Safeguards pre-check" but the SPEC does not yet
/// specify what it evaluates beyond that — ``SafeguardsPreCheck``'s own doc
/// comment already tracks "the tiered, deny-by-default evaluation" as
/// separate work. Every mutating action a session attempts is still gated by
/// ``SafeguardsGate`` at the point it is attempted, which is real and
/// tiered; this type only discharges the pipeline's stage-4 seam so a
/// session can be composed today.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Architecture-The-Orchestration-Boundary#the-shared-session-model
public struct AlwaysApprovedSafeguardsPreCheck: SafeguardsPreCheck {
    public init() {
        // Nothing to set up — this conformance holds no state.
    }

    public func evaluate(_: SafeguardsPreCheckInput) async -> SafeguardsPreCheckOutcome {
        .approved
    }
}
