import Foundation
import Observation
import TalosAdapters
import TalosCore
import TalosOrchestration
import TalosSafeguards

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
///
/// Conforms to ``SafeguardsApprovalPrompt`` so a pending approval renders
/// "inline, where the work is happening" rather than as a detached modal —
/// the console is given the gate's own `action`/`tier` directly through
/// `present(_:action:tier:)`, which is the only place that data exists; core
/// never derives a tier by reading ``AgentToolCall/name``.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Session-Console#what-it-is
@Observable
@MainActor
public final class SessionConsoleViewModel: SafeguardsApprovalPrompt {
    public enum State: Equatable, Sendable {
        case empty
        case loading
        case ready
        case failed(AgentTermination)
        case denied(AgentTermination)
    }

    /// Resolves an output line's ``OutputElement`` to the view that displays
    /// it — the pluggable dispatch this view model never bypasses. A
    /// ``SessionConsoleToolCall`` line is not an ``OutputElement`` and never
    /// goes through this registry; it renders through its own row.
    public let renderers: OutputRendererRegistry
    /// The transcript so far, in arrival order. Every element but the last
    /// is finalized; the last is still open to more text.
    public private(set) var lines: [SessionConsoleLine] = []
    /// Whether the console should keep scrolling to new output. Toggled only
    /// by the view, from a real scroll-phase event — never by a timer.
    /// https://github.com/CalixtoTheBugHunter/talos/wiki/Foundations-States-and-Feedback#nothing-polls
    public private(set) var isFollowingOutput = true

    /// The agent's live token report, or `nil` before the first
    /// ``updateTokenUsage(_:)`` — never rendered as a zero.
    /// https://github.com/CalixtoTheBugHunter/talos/wiki/Essential-Tools#when-the-log-format-changes
    public private(set) var tokenUsage: TokenReport?
    /// Talos-added token overhead for this run, shown alongside ``tokenUsage``
    /// as a distinct figure.
    /// https://github.com/CalixtoTheBugHunter/talos/wiki/Vision-and-Principles#budgets-that-make-the-above-testable
    public private(set) var contextOverheadRatio: Double?

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
    /// The continuation a pending ``present(_:action:tier:)`` call is
    /// suspended on. One slot, not a queue: the stream that raises a
    /// `.permissionRequest` here is fully serialized by
    /// `SafeguardsApproved.run` — it awaits this call before consuming the
    /// next event — so at most one approval is ever pending for this console
    /// at a time.
    private var pendingApprovalContinuation: CheckedContinuation<AgentPermissionDecision?, Never>?

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
        tokenUsage = nil
        contextOverheadRatio = nil
    }

    /// The seam this plugs into as `SafeguardsApproved.run`'s `tokenObserver:`
    /// — event-driven, never a timer.
    /// https://github.com/CalixtoTheBugHunter/talos/wiki/Foundations-States-and-Feedback#nothing-polls
    public func updateTokenUsage(_ update: SessionTokenUpdate) {
        tokenUsage = update.report
        contextOverheadRatio = update.contextOverheadRatio
    }

    /// The seam this view model plugs into directly as
    /// `SafeguardsApproved.run`'s `observer:` parameter, and separately as
    /// the `approvalPrompt` a ``SafeguardsGate`` presents through.
    ///
    /// A `.toolCall` renders inline as it arrives — "tool calls as the agent
    /// makes them". `.permissionRequest` is ignored here: the gate calls
    /// ``present(_:action:tier:)`` directly for the same event, carrying the
    /// `action`/`tier` this method is never given, so that is the one real
    /// channel a pending approval renders through, never duplicated here.
    /// `.terminated` is not ignored — it is what moves ``state`` to
    /// ``State/failed(_:)`` or ``State/denied(_:)``, attributed to the agent
    /// rather than paraphrased.
    /// https://github.com/CalixtoTheBugHunter/talos/wiki/Foundations-States-and-Feedback#errors
    public func handle(_ event: AgentEvent) {
        switch event {
        case let .output(chunk):
            appendOutput(chunk)
        case let .toolCall(call):
            appendToolCall(call)
        case let .terminated(termination):
            self.termination = termination
        case .permissionRequest:
            break
        }
    }

    /// Renders a tool call inline the moment it arrives, structurally at
    /// ``SessionConsoleToolCallApproval/none`` — never by classifying
    /// ``AgentToolCall/name``, which core does not switch on. A call that
    /// later turns out to need approval is upgraded in place by
    /// ``present(_:action:tier:)``; one that never does is read tier, shown
    /// de-emphasized because it never prompted.
    /// https://github.com/CalixtoTheBugHunter/talos/wiki/Safeguards-and-Autonomy#tiers
    private func appendToolCall(_ call: AgentToolCall) {
        closeOpenLineIfNeeded()
        lines.append(SessionConsoleLine(
            id: makeNextID(),
            content: .toolCall(SessionConsoleToolCall(callID: call.id, name: call.name, targets: call.targets))
        ))
    }

    /// Presents a pending approval inline in the transcript rather than as a
    /// detached modal — the row a ``SessionConsoleToolCall`` with the same
    /// `callID` upgrades to ``SessionConsoleToolCallApproval/pending(request:action:tier:)``,
    /// or a synthesized row when no correlated `.toolCall` ever arrived.
    /// Suspends until the view calls ``resolvePendingApproval(with:)``, or
    /// resolves `nil` on cancellation — the fail-closed case the gate
    /// attributes to Talos rather than to a decision the user never made.
    ///
    /// ``beginPendingApproval(request:action:tier:)`` runs only once the task
    /// is confirmed not already cancelled, mirroring ``ApprovalPromptCenter/present(_:action:tier:)``'s
    /// own ordering — never before, so a task already cancelled at entry
    /// never shows a row it cannot resolve: `cancelPendingApproval` only acts
    /// on a `pendingApprovalContinuation` this method has stored.
    /// https://github.com/CalixtoTheBugHunter/talos/wiki/Safeguards-and-Autonomy#the-gate-fails-closed
    public func present(
        _ request: AgentPermissionRequest,
        action: SafeguardsActionType,
        tier: SafeguardsTier
    ) async -> AgentPermissionDecision? {
        await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<AgentPermissionDecision?, Never>) in
                guard !Task.isCancelled else {
                    continuation.resume(returning: nil)
                    return
                }
                beginPendingApproval(request: request, action: action, tier: tier)
                pendingApprovalContinuation = continuation
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.cancelPendingApproval(requestID: request.id) }
        }
    }

    /// Called by the view once the user decides on the row currently
    /// pending — there is only ever one, per ``present(_:action:tier:)``'s
    /// own guarantee.
    public func resolvePendingApproval(with decision: AgentPermissionDecision) {
        guard let pending = currentPendingApproval, let continuation = pendingApprovalContinuation else { return }
        pendingApprovalContinuation = nil
        updateToolCall(
            callID: pending.callID,
            approval: .resolved(action: pending.action, tier: pending.tier, outcome: decision)
        )
        continuation.resume(returning: decision)
    }

    /// Feeds one incremental chunk of agent output through the same
    /// line-splitting appendOutput ``handle(_:)`` calls this with.
    public func appendOutput(_ chunk: AgentOutputChunk) {
        guard !chunk.text.isEmpty else { return }

        let hasOpenLine = openLineID != nil
        let basePayload = hasOpenLine ? openLinePayload : ""
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
        lines[index].content = .output(OutputElement(kind: .markdown, payload: payload))
    }

    /// Converts the current open line into a finalized one, in place, so its
    /// `id` never changes.
    private func finalizeOpenLine(payload: String) {
        guard let index = lines.indices.last else { return }
        lines[index].content = .output(OutputElement(kind: .markdown, payload: payload))
        announceIfMeaningful(payload)
        openLineID = nil
    }

    private func appendFinalizedLine(payload: String) {
        lines.append(SessionConsoleLine(
            id: makeNextID(),
            content: .output(OutputElement(kind: .markdown, payload: payload))
        ))
        announceIfMeaningful(payload)
    }

    private func openNewLine(payload: String) {
        let id = makeNextID()
        lines.append(SessionConsoleLine(id: id, content: .output(OutputElement(kind: .markdown, payload: payload))))
        openLineID = id
    }

    /// The open output line's own payload so far, or empty when the last
    /// line is not an open output line at all — which is also true the
    /// moment a ``SessionConsoleToolCall`` row becomes the last line, since
    /// ``closeOpenLineIfNeeded()`` clears ``openLineID`` before that happens.
    private var openLinePayload: String {
        guard let last = lines.last, case let .output(element) = last.content else { return "" }
        return element.payload
    }

    /// A tool call interrupts whatever text line was still open — the text
    /// so far is a complete unit as far as the reader is concerned, so it is
    /// announced and closed rather than left dangling under a row that is no
    /// longer last.
    private func closeOpenLineIfNeeded() {
        defer { openLineID = nil }
        guard openLineID != nil, let last = lines.last, case let .output(element) = last.content else { return }
        announceIfMeaningful(element.payload)
    }

    /// Finds the line whose ``SessionConsoleToolCall/callID`` matches and
    /// updates its `approval` in place. The row's own `id` never changes —
    /// this is the single-row diff the file's own perf note keeps to.
    @discardableResult
    private func updateToolCall(callID: String, approval: SessionConsoleToolCallApproval) -> Bool {
        guard let index = lines.firstIndex(where: { line in
            if case let .toolCall(call) = line.content {
                return call.callID == callID
            }
            return false
        }) else { return false }
        guard case var .toolCall(call) = lines[index].content else { return false }
        call.approval = approval
        lines[index].content = .toolCall(call)
        return true
    }

    /// The row currently at ``SessionConsoleToolCallApproval/pending(request:action:tier:)``,
    /// if any — at most one, per ``present(_:action:tier:)``'s own guarantee.
    private var currentPendingApproval: PendingApprovalInfo? {
        for line in lines {
            guard case let .toolCall(call) = line.content,
                  case let .pending(_, action, tier) = call.approval
            else { continue }
            return PendingApprovalInfo(callID: call.callID, action: action, tier: tier)
        }
        return nil
    }

    /// Upgrades the correlated ``SessionConsoleToolCall`` row to pending, or
    /// synthesizes one when no `.toolCall` ever preceded this request — a
    /// defensive fallback rather than a crash, carrying every field the
    /// prompt itself has. Announces the pending approval once either way —
    /// "VoiceOver announces a pending approval".
    /// https://github.com/CalixtoTheBugHunter/talos/wiki/Session-Console#what-it-is
    private func beginPendingApproval(
        request: AgentPermissionRequest,
        action: SafeguardsActionType,
        tier: SafeguardsTier
    ) {
        let approval = SessionConsoleToolCallApproval.pending(request: request, action: action, tier: tier)
        if !updateToolCall(callID: request.id, approval: approval) {
            lines.append(SessionConsoleLine(
                id: makeNextID(),
                content: .toolCall(SessionConsoleToolCall(
                    callID: request.id,
                    name: request.toolName ?? "",
                    targets: [],
                    approval: approval
                ))
            ))
        }
        announcer.announce(request.prompt.isEmpty ? "Approval needed." : "Approval needed. \(request.prompt)")
    }

    /// The gate can no longer obtain a decision — the session is being torn
    /// down. Resolved as denied, attributed to Talos rather than the user,
    /// same as ``ApprovalPromptCenter``'s own cancellation path.
    /// https://github.com/CalixtoTheBugHunter/talos/wiki/Safeguards-and-Autonomy#the-gate-fails-closed
    private func cancelPendingApproval(requestID: String) {
        guard let continuation = pendingApprovalContinuation else { return }
        pendingApprovalContinuation = nil
        if let pending = currentPendingApproval, pending.callID == requestID {
            updateToolCall(
                callID: requestID,
                approval: .resolved(action: pending.action, tier: pending.tier, outcome: .denied)
            )
        }
        continuation.resume(returning: nil)
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
