import TalosOrchestration

/// Context-reporting helpers — split out of `SessionConsoleViewModel.swift`
/// to keep that file within this module's file-length limit, the same reason
/// `+Lifecycle` and `+Resume` are split.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Session-Console#what-it-is
extension SessionConsoleViewModel {
    /// The user-facing name of a context part. `Text(verbatim:)` at the call
    /// site, so this is display copy rather than the `spec-drive` raw value the
    /// guideline's `context:` list uses.
    static func contextPartLabel(_ kind: ContextPartKind) -> String {
        switch kind {
        case .guideline: "Guideline"
        case .safeguards: "Safeguards"
        case .specDrive: "Spec Drive"
        case .connectors: "Connectors"
        case .board: "Board"
        case .memories: "Memories"
        }
    }
}
