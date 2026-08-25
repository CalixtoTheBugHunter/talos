import Foundation

// The typed model for `.talos/board.yaml` — maps a board provider's real
// columns onto Talos's six canonical internal states so no provider-specific
// assumption leaks into Talos core.
// https://github.com/CalixtoTheBugHunter/talos/wiki/Project-Library#board
// https://github.com/CalixtoTheBugHunter/talos/wiki/Project-Library#the-canonical-internal-states

/// The registered board providers Project Library § Board names by example:
/// "Jira, GitHub Projects."
public enum BoardProviderKind: String, CaseIterable, Equatable, Hashable, Sendable {
    case jira
    case githubProjects = "github-projects"
}

/// The six canonical internal board states, and the whole set — per
/// [decision 58](https://github.com/CalixtoTheBugHunter/talos/wiki/Decision-Log#foundational-decisions),
/// the same machine as
/// [the dev cycle](https://github.com/CalixtoTheBugHunter/talos/wiki/Engineering-Standards#the-dev-cycle).
/// An unrecognized value in `board.yaml` is a configuration error, never a
/// new state.
public enum BoardState: String, CaseIterable, Equatable, Hashable, Sendable {
    case backlog
    case ready
    case inProgress = "in-progress"
    case inReview = "in-review"
    case done
    case blocked
}

/// One provider column mapped to exactly one internal state. Several
/// `BoardColumnMapping`s may share the same `state` — the many-to-one
/// direction Project Library § Board allows.
public struct BoardColumnMapping: Equatable, Sendable {
    public let column: String
    public let state: BoardState

    public init(column: String, state: BoardState) {
        self.column = column
        self.state = state
    }
}

/// What looking up a provider column resolves to. `.unmapped` is a declared
/// answer, not the absence of one — a column with no counterpart is never
/// read as `.mapped(.backlog)` or any other default.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Project-Library#board
public enum BoardColumnResolution: Equatable, Sendable {
    case mapped(BoardState)
    case unmapped
}

/// The parsed, validated contents of `.talos/board.yaml`.
public struct BoardManifest: Equatable, Sendable {
    public let provider: BoardProviderKind
    public let columns: [BoardColumnMapping]

    public init(provider: BoardProviderKind, columns: [BoardColumnMapping] = []) {
        self.provider = provider
        self.columns = columns
    }

    /// Answers "what internal state does `column` map to?" — a pure lookup
    /// against what was parsed. A column with no matching entry resolves
    /// `.unmapped`, never inferred and never defaulted.
    /// https://github.com/CalixtoTheBugHunter/talos/wiki/Project-Library#board
    public func state(forColumn column: String) -> BoardColumnResolution {
        guard let mapping = columns.first(where: { $0.column == column }) else {
            return .unmapped
        }
        return .mapped(mapping.state)
    }
}

/// A validation failure that names the file, the line, and the fix — the
/// same shape ``ConnectorsManifestError`` and ``SpecManifestError`` use.
public struct BoardManifestError: Error, Equatable, Sendable {
    /// The path of the file that failed to parse or validate.
    public let file: String
    /// The 1-indexed source line the failure was found at, when the YAML
    /// parser could locate one.
    public let line: Int?
    /// What to change to fix it, stated as an instruction.
    public let fix: String
}
