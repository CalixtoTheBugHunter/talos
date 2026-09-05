import Foundation
import TalosProjectLibrary

/// Reads back what ``GatedDecisionLog`` recorded, so a view can show the
/// user what was logged rather than leave it visible only in a file.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Safeguards-and-Autonomy#rules
public protocol GatedDecisionLogReader: Sendable {
    func entries(project: ProjectIdentifier, from start: Date, to end: Date) async throws -> [StoredGatedDecisionEntry]
    func entries(project: ProjectIdentifier, sessionID: UUID) async throws -> [StoredGatedDecisionEntry]
}

extension SQLiteGatedDecisionLog: GatedDecisionLogReader {}
