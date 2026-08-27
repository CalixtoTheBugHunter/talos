import TalosProjectLibrary

/// Where an ``Intent`` entered the pipeline from. `Assistant` and `Automator`
/// construct one from a user action; `Advisor` and `Self-improver` will
/// construct one from the scheduler. A closed enum on purpose: adding a case
/// is a compile error at every existing switch until that switch accounts
/// for it, which is the property this module wants as new entry points
/// arrive.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Roadmap-Post-MVP#why-these-constraints-matter
public enum IntentSource: Equatable, Hashable, Sendable {
    case userText
    case scheduler
}

/// The transport-agnostic entry point to the shared session pipeline —
/// carries what a sub-function was asked to do, independent of how it
/// arrived, so voice, schedule, and text all enter the same pipeline stage.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Architecture-The-Orchestration-Boundary#the-shared-session-model
public struct Intent: Equatable, Sendable {
    public let content: String
    public let source: IntentSource
    public let project: ProjectIdentifier
    public let requestingSubFunction: SubFunction

    public init(
        content: String,
        source: IntentSource,
        project: ProjectIdentifier,
        requestingSubFunction: SubFunction
    ) {
        self.content = content
        self.source = source
        self.project = project
        self.requestingSubFunction = requestingSubFunction
    }
}
