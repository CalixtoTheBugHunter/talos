import Foundation
import TalosAdapters
import TalosCore
import TalosOrchestration
import TalosProjectLibrary
import TalosSafeguards
import Testing

/// A `.permissionUnavailable` is the fail-closed denial for an action the gate
/// could never be offered — a call the CLI dropped from a parallel batch. It is
/// logged with the same four fields as any decision, actor Talos, counted as a
/// denial, and surfaced through `onDenial`. Nothing is carried back to the
/// adapter, since there is no request the CLI is still holding to resolve.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Safeguards-and-Autonomy#the-gate-fails-closed
@Suite("Unaskable denial")
struct SessionUnaskableDenialTests {
    @Test("An unaskable action is logged once as a Talos denial, counted, and never resolved back")
    func unaskableIsLoggedCountedAndNotResolved() async {
        let request = AgentPermissionRequest(id: "dropped-1", prompt: "Bash — cat one.txt", toolName: "Bash")
        let adapter = ScriptedAgentAdapter(events: [
            .permissionUnavailable(request),
            terminated(.exited(code: 0))
        ])
        let decisionLog = RecordingGatedDecisionLog()
        let pipeline = makeTestPipeline(adapter: adapter, decisionLog: decisionLog)

        let denied = DeniedActionRecorder()
        let record = await runTestSession(pipeline, onDenial: denied.note)

        #expect(record.denialCount == 1, "a blocked call is a denial from the user's side of the gate")
        #expect(record.approvalCount == 0)

        let entries = await decisionLog.entries
        #expect(entries.count == 1, "exactly one row, the same as any gated decision")
        #expect(entries.first?.outcome == .denied)
        #expect(entries.first?.actor == .talos, "the user never decided, so Talos is the actor")
        #expect(entries.first?.requestID == "dropped-1")

        #expect(await denied.notes.count == 1, "the user is told, the same as any other denial")
        #expect(await adapter.carriedDecisions.isEmpty, "nothing is resolved back — the CLI holds no request to answer")
    }
}

/// Captures each `onDenial` call, so "the user is told" is an assertion.
private actor DeniedActionRecorder {
    private(set) var notes: [(action: SafeguardsActionType, prompt: String)] = []

    func note(_ action: SafeguardsActionType, _ prompt: String) async {
        notes.append((action, prompt))
    }
}
