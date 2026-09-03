import Foundation
import Observation
import TalosAdapters

/// Accumulates an agent's streamed output into ``SessionConsoleLine``s and
/// tracks whether the transcript should keep following new output.
///
/// Output is split on `"\n"` into an immutable, finalized line per completed
/// line of text and one mutable "open" line — the one still receiving
/// chunks. A finalized line's `id` and payload never change again, so a
/// `List` keyed on that `id` only ever diffs the one row still streaming,
/// never the whole transcript.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Session-Console#what-it-is
///
/// ``state`` carries the five states this surface owes, named exactly as
/// ``GatedDecisionLogViewModel/State`` names them for the same reason.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Foundations-States-and-Feedback
@Observable
@MainActor
public final class SessionConsoleViewModel {
    public enum State: Equatable, Sendable {
        case empty
        case loading
        case ready
        case failed(AgentTermination)
        case denied(AgentTermination)
    }

    /// Resolves each line's ``OutputElement`` to the view that displays it —
    /// the pluggable dispatch this view model never bypasses.
    public let renderers: OutputRendererRegistry
    /// The transcript so far, in arrival order. Every element but the last
    /// is finalized; the last is still open to more text.
    public private(set) var lines: [SessionConsoleLine] = []
    /// Whether the console should keep scrolling to new output. Toggled only
    /// by the view, from a real scroll-phase event — never by a timer.
    /// https://github.com/CalixtoTheBugHunter/talos/wiki/Foundations-States-and-Feedback#nothing-polls
    public private(set) var isFollowingOutput = true

    /// Set once by ``sessionStarted()``, before the first event ever arrives —
    /// what tells ``state`` apart ``State/empty`` (no session at all) from
    /// ``State/loading`` (a session is running; the agent has not answered
    /// yet).
    private var hasStarted = false
    /// How the most recent session ended, or `nil` while it is still running.
    private var termination: AgentTermination?
    private let announcer: any SessionConsoleAnnouncing
    /// The `id` of the last line, while it is still open to more text.
    /// `nil` means every line so far is finalized — true only before the
    /// first chunk ever arrives.
    private var openLineID: Int?
    private var nextID = 0

    /// What ``SessionConsoleView`` renders right now — derived rather than
    /// stored, so it can never drift from ``lines`` and ``termination``.
    /// A termination is checked before an empty transcript, so a session that
    /// failed or was denied before producing any output still reads as
    /// ``State/failed(_:)`` / ``State/denied(_:)`` rather than as stuck in
    /// ``State/loading``.
    public var state: State {
        if let termination {
            switch termination.reason {
            case let .exited(code):
                return code == 0 ? (lines.isEmpty ? .empty : .ready) : .failed(termination)
            case .failedToLaunch:
                return .failed(termination)
            case .denied:
                return .denied(termination)
            case .stopped:
                return lines.isEmpty ? .empty : .ready
            }
        }
        if lines.isEmpty {
            return hasStarted ? .loading : .empty
        }
        return .ready
    }

    /// `renderers` defaults to the registry a console starts from — Markdown
    /// registered as data — and `announcer` defaults to the real VoiceOver
    /// announcer; a test injects a spy for either.
    public init(
        renderers: OutputRendererRegistry = .withDefaults(),
        announcer: any SessionConsoleAnnouncing = SystemVoiceOverAnnouncer()
    ) {
        self.renderers = renderers
        self.announcer = announcer
    }

    /// Called once, before the first ``AgentEvent`` ever arrives, so ``state``
    /// can tell "no session" (``State/empty``) apart from "a session is
    /// running and the agent has not answered yet" (``State/loading``) — the
    /// distinction this exact surface owes.
    /// https://github.com/CalixtoTheBugHunter/talos/wiki/Foundations-States-and-Feedback
    public func sessionStarted() {
        hasStarted = true
        termination = nil
    }

    /// The seam this view model plugs into directly as
    /// `SafeguardsApproved.run`'s `observer:` parameter. `.toolCall` and
    /// `.permissionRequest` belong to a different surface and are ignored
    /// here; `.terminated` is not ignored — it is what moves ``state`` to
    /// ``State/failed(_:)`` or ``State/denied(_:)``, attributed to the agent
    /// rather than paraphrased.
    /// https://github.com/CalixtoTheBugHunter/talos/wiki/Foundations-States-and-Feedback#errors
    public func handle(_ event: AgentEvent) {
        switch event {
        case let .output(chunk):
            appendOutput(chunk)
        case let .terminated(termination):
            self.termination = termination
        case .toolCall, .permissionRequest:
            break
        }
    }

    /// Feeds one incremental chunk of agent output through the same
    /// line-splitting appendOutput ``handle(_:)`` calls this with.
    public func appendOutput(_ chunk: AgentOutputChunk) {
        guard !chunk.text.isEmpty else { return }

        let hasOpenLine = openLineID != nil
        let basePayload = hasOpenLine ? (lines.last?.element.payload ?? "") : ""
        let segments = (basePayload + chunk.text)
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
        let openSegment = segments.last ?? ""
        let finalizedSegments = Array(segments.dropLast())

        guard !finalizedSegments.isEmpty else {
            if hasOpenLine {
                updateOpenLinePayload(openSegment)
            } else {
                openNewLine(payload: openSegment)
            }
            return
        }

        var segmentsToFinalize = finalizedSegments
        if hasOpenLine {
            finalizeOpenLine(payload: segmentsToFinalize.removeFirst())
        }
        for segment in segmentsToFinalize {
            appendFinalizedLine(payload: segment)
        }
        openNewLine(payload: openSegment)
    }

    /// Called by the view when a real scroll event moves the transcript away
    /// from the bottom — never from a timer.
    public func pauseFollowingOutput() {
        isFollowingOutput = false
    }

    /// Called by the view when a real scroll event returns the transcript to
    /// the bottom.
    public func resumeFollowingOutput() {
        isFollowingOutput = true
    }

    private func updateOpenLinePayload(_ payload: String) {
        guard let index = lines.indices.last else { return }
        lines[index].element = OutputElement(kind: .markdown, payload: payload)
    }

    /// Converts the current open line into a finalized one, in place, so its
    /// `id` never changes.
    private func finalizeOpenLine(payload: String) {
        guard let index = lines.indices.last else { return }
        lines[index].element = OutputElement(kind: .markdown, payload: payload)
        announceIfMeaningful(payload)
        openLineID = nil
    }

    private func appendFinalizedLine(payload: String) {
        lines.append(SessionConsoleLine(id: makeNextID(), element: OutputElement(kind: .markdown, payload: payload)))
        announceIfMeaningful(payload)
    }

    private func openNewLine(payload: String) {
        let id = makeNextID()
        lines.append(SessionConsoleLine(id: id, element: OutputElement(kind: .markdown, payload: payload)))
        openLineID = id
    }

    private func makeNextID() -> Int {
        let id = nextID
        nextID += 1
        return id
    }

    /// A blank line finalizing carries nothing to announce — "one
    /// announcement per meaningful unit of output".
    /// https://github.com/CalixtoTheBugHunter/talos/wiki/Foundations-Accessibility#voiceover
    private func announceIfMeaningful(_ payload: String) {
        guard !payload.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        announcer.announce(payload)
    }
}
