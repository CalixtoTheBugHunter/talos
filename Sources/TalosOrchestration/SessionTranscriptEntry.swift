import Foundation

/// One unit of a session's transcript, in arrival order — the storage- and
/// export-independent shape both ``SQLiteSessionRecordStore`` persists and
/// ``SessionTranscriptReconstruction`` reads back. Mirrors the two
/// ``AgentEvent`` cases a transcript ever shows: agent output, and a tool
/// call the agent announced. A `.permissionRequest` never appears here — it
/// is mid-flight state that never survives to a terminal session record, and
/// its resolution is read from the ``GatedDecisionLog`` instead of being
/// duplicated into this store.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Session-Console#what-it-is
public enum SessionTranscriptEntry: Equatable, Sendable {
    case output(String)
    case toolCall(id: String, name: String, targets: [String])
}
