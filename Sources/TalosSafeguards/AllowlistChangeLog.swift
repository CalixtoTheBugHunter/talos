import Foundation
import TalosCore
import TalosProjectLibrary

/// Which direction one allowlist mutation went.
public enum AllowlistChangeKind: String, Equatable, Hashable, Sendable {
    case added
    case removed
}

/// One row of the allowlist change log: "Allowlist changes are logged with
/// actor and timestamp."
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Safeguards-and-Autonomy#rules
///
/// A distinct type from ``GatedDecisionEntry`` rather than a reuse of it: a
/// gated decision is the gate answering an in-flight `AgentPermissionRequest`
/// from an agent, while an allowlist change is a persistent configuration
/// edit with no request behind it at all — the two never share a shape.
public struct AllowlistChangeEntry: Equatable, Sendable {
    public let project: ProjectIdentifier
    public let action: SafeguardsActionType
    public let change: AllowlistChangeKind
    public let actor: String
    public let timestamp: Date

    public init(
        project: ProjectIdentifier,
        action: SafeguardsActionType,
        change: AllowlistChangeKind,
        actor: String,
        timestamp: Date
    ) {
        self.project = project
        self.action = action
        self.change = change
        self.actor = actor
        self.timestamp = timestamp
    }
}

/// Where every allowlist change is written, one entry per add or revoke.
///
/// Declared here with no conformance in this module, the same pattern
/// ``GatedDecisionLog`` uses: durable storage of the log is tracked
/// separately from the store that produces its entries.
public protocol AllowlistChangeLog: Sendable {
    func record(_ entry: AllowlistChangeEntry) async
}
