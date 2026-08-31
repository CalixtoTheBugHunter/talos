import TalosProjectLibrary

/// What a pre-check needs to judge one session before the agent is launched.
///
/// Carries the requesting project and sub-function rather than the
/// orchestration layer's `Intent`: the gate sits *below* the pipeline in the
/// module graph, and per-project allowlisting is what these two fields serve.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Architecture-The-Orchestration-Boundary#the-shared-session-model
public struct SafeguardsPreCheckInput: Equatable, Sendable {
    public let project: ProjectIdentifier
    public let subFunction: SubFunction
    public let intentContent: String
    public let guideline: GuidelineDocument
    public let safeguards: SafeguardsDocument
    public let connectors: ConnectorsManifest

    public init(
        project: ProjectIdentifier,
        subFunction: SubFunction,
        intentContent: String,
        guideline: GuidelineDocument,
        safeguards: SafeguardsDocument,
        connectors: ConnectorsManifest
    ) {
        self.project = project
        self.subFunction = subFunction
        self.intentContent = intentContent
        self.guideline = guideline
        self.safeguards = safeguards
        self.connectors = connectors
    }
}

/// A pre-check's verdict. Two cases only: a session either proceeds to the
/// agent or does not. `.denied` is a recorded outcome, never an error —
/// "Denial is not failure."
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Safeguards-and-Autonomy
public enum SafeguardsPreCheckOutcome: Equatable, Sendable {
    case approved
    case denied(reason: String)
}

/// The pre-check the session pipeline runs at stage 4, before any agent is
/// launched. Only a `.approved` outcome can produce the pipeline's
/// `SafeguardsApproved` stage, so this cannot be skipped on the way to a
/// running agent.
///
/// Declared here with no conformance in this module: the tiered,
/// deny-by-default evaluation is tracked separately, and the pipeline's
/// ordering guarantee does not wait on it.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Architecture-The-Orchestration-Boundary#the-shared-session-model
public protocol SafeguardsPreCheck: Sendable {
    func evaluate(_ input: SafeguardsPreCheckInput) async -> SafeguardsPreCheckOutcome
}
