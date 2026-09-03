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
@Observable
@MainActor
public final class SessionConsoleViewModel {
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

    private let announcer: any SessionConsoleAnnouncing
    /// The `id` of the last line, while it is still open to more text.
    /// `nil` means every line so far is finalized — true only before the
    /// first chunk ever arrives.
    private var openLineID: Int?
    private var nextID = 0

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

    /// The seam this view model plugs into directly as
    /// `SafeguardsApproved.run`'s `observer:` parameter. Every other event
    /// case belongs to a different surface (tool calls, permission requests,
    /// termination) and is ignored here.
    public func handle(_ event: AgentEvent) {
        guard case let .output(chunk) = event else { return }
        appendOutput(chunk)
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
