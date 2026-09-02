import Foundation
import TalosCore
import TalosProjectLibrary
@testable import TalosSafeguards
import Testing

/// "No parsed third-party content can grant an allowlist entry" — checked
/// against the real ``AllowlistStore`` with hostile fixtures standing in for
/// an `actor` string built from third-party content (for example, a session
/// summary quoting a PR comment). `AllowlistStoreWriteReachabilityTests`
/// already proves no agent-facing code path can even reach these mutators;
/// this suite proves that reaching them with hostile content changes
/// nothing about what gets validated.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Safeguards-and-Autonomy#prompt-injection-posture
@Suite("Prompt-injection posture: the allowlist store ignores hostile content")
struct PromptInjectionAllowlistTests {
    private actor RecordingChangeLog: AllowlistChangeLog {
        private(set) var entries: [AllowlistChangeEntry] = []
        func record(_ entry: AllowlistChangeEntry) async {
            entries.append(entry)
        }
    }

    private static func makeTemporaryProjectRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("PromptInjectionAllowlistTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    /// A hostile `actor` string does not change whether an irreversible or
    /// refused action type is rejected — the check is on the action, and the
    /// actor is recorded, never parsed for a second directive.
    @Test("A hostile actor string does not open a path to allowlist an irreversible action")
    func hostileActorDoesNotOpenAnIrreversibleAction() async throws {
        let root = try Self.makeTemporaryProjectRoot()
        let store = try AllowlistStore(
            projectRoot: root, project: ProjectIdentifier(rawValue: "p"), changeLog: RecordingChangeLog()
        )

        for fixture in PromptInjectionFixtures.all {
            await #expect {
                try await store.allowlistAction(.deployProduction, actor: fixture)
            } throws: { error in
                guard case let .invalidEntry(rejected, _) = error as? AllowlistStoreError else { return false }
                return rejected == .deployProduction
            }
        }
    }

    /// The refused types — the ones a user most needs to see an agent
    /// attempt — stay refused even when the fixture that produced the write
    /// attempt is itself an instruction to allowlist that exact type.
    @Test("A hostile actor string does not open a path to allowlist a refused type")
    func hostileActorDoesNotOpenARefusedType() async throws {
        let root = try Self.makeTemporaryProjectRoot()
        let store = try AllowlistStore(
            projectRoot: root, project: ProjectIdentifier(rawValue: "p"), changeLog: RecordingChangeLog()
        )

        for fixture in PromptInjectionFixtures.all {
            await #expect {
                try await store.allowlistAction(.configAllowlistWrite, actor: fixture)
            } throws: { error in
                guard case let .invalidEntry(rejected, _) = error as? AllowlistStoreError else { return false }
                return rejected == .configAllowlistWrite
            }
        }
    }

    /// A legitimate write-tier grant still succeeds with a hostile actor
    /// string, and the string is recorded verbatim rather than being read as
    /// a second action — proving the log tells the truth about who typed
    /// what, even when what they typed was adversarial.
    @Test("A hostile actor string is recorded verbatim on a legitimate grant, never acted on twice")
    func hostileActorIsRecordedVerbatimOnALegitimateGrant() async throws {
        let root = try Self.makeTemporaryProjectRoot()
        let changeLog = RecordingChangeLog()
        let store = try AllowlistStore(
            projectRoot: root, project: ProjectIdentifier(rawValue: "p"), changeLog: changeLog
        )
        let fixture = PromptInjectionFixtures.issueBody

        try await store.allowlistAction(.fileWrite, actor: fixture)

        #expect(await store.isAllowlisted(.fileWrite, project: ProjectIdentifier(rawValue: "p")))
        let entries = await changeLog.entries
        #expect(entries.map(\.action) == [.fileWrite])
        #expect(entries.map(\.actor) == [fixture])
    }
}
