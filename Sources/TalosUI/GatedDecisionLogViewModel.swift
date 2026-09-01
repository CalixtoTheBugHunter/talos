import Foundation
import Observation
import TalosOrchestration
import TalosProjectLibrary

/// Drives the four states ``GatedDecisionLogView`` renders — Loading, Empty,
/// Ready, Failed — from a ``GatedDecisionLogReader``.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Foundations-States-and-Feedback#the-five-states-every-surface-owes
@Observable
@MainActor
public final class GatedDecisionLogViewModel {
    public enum State: Equatable, Sendable {
        case loading
        case empty
        case ready([StoredGatedDecisionEntry])
        case failed(String)
    }

    /// The state ``GatedDecisionLogView`` renders right now.
    public private(set) var state: State = .loading

    private let reader: any GatedDecisionLogReader
    private let project: ProjectIdentifier
    private let start: Date
    private let end: Date

    /// `start`/`end` bound the range ``load()`` reads; nothing is loaded until
    /// ``load()`` is called.
    public init(reader: any GatedDecisionLogReader, project: ProjectIdentifier, from start: Date, to end: Date) {
        self.reader = reader
        self.project = project
        self.start = start
        self.end = end
    }

    /// Loads the range given at init. Also the control ``GatedDecisionLogView``
    /// offers in its Failed state, so a transient read failure is retryable
    /// rather than terminal.
    public func load() async {
        state = .loading
        do {
            let entries = try await reader.entries(project: project, from: start, to: end)
            state = entries.isEmpty ? .empty : .ready(entries)
        } catch {
            state = .failed("The decision log could not be read: \(error.localizedDescription)")
        }
    }
}
