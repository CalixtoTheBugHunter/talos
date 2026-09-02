import Foundation
import Testing

/// Two structural absences, checked the same way `AllowlistStoreWriteReachabilityTests` checks its
/// own: by reading source text rather than by running the code, because both properties are ones no
/// unit test against a running gate can observe — there is nothing to call that would prove a write
/// path or a timer does not exist.
@Suite("Safeguards: structural invariants no runtime test can observe")
struct SafeguardsStructuralInvariantTests {
    private static var repositoryRoot: URL {
        var url = URL(fileURLWithPath: #filePath)
        while url.pathComponents.count > 1 {
            url.deleteLastPathComponent()
            if FileManager.default.fileExists(atPath: url.appendingPathComponent("Package.swift").path) {
                return url
            }
        }
        fatalError("Could not locate the repository root above \(#filePath)")
    }

    // MARK: - Nothing writes .talos/safeguards.md except the one sanctioned, non-overwriting create

    /// `SafeguardsLoader` is deliberately read-only — no type anywhere offers a way to write, edit, or
    /// delete `safeguards.md`. Several files legitimately *mention* the path — a doc comment, the
    /// refused `config.safeguards.write` action type's own description, `ContextAssembler` naming it
    /// for a dropped-context message — so this does not assert that no other file names the string
    /// (`AllowlistStoreWriteReachabilityTests` can grep for two distinctive mutator names because
    /// those exist; there is no mutator name to grep for here because none exists). Instead it checks
    /// the one thing that would actually matter: no file other than `ProjectLibraryScaffolder.swift`
    /// (the documented, one-time, non-overwriting create on project add) combines a mention of
    /// `safeguards.md` with a filesystem-write call. If a third file ever does both, that is the
    /// second, agent-reachable write path the SPEC says must never exist.
    /// https://github.com/CalixtoTheBugHunter/talos/wiki/Safeguards-and-Autonomy#limits-on-ai-self-modification
    @Test("No source file other than ProjectLibraryScaffolder.swift both names safeguards.md and writes a file")
    func onlyTheScaffolderCombinesSafeguardsFileWithAWrite() throws {
        let writeTokens = [".write(to:", "createFile", "SecItemAdd", "SecItemUpdate"]
        let sourcesRoot = Self.repositoryRoot.appendingPathComponent("Sources")
        guard let enumerator = FileManager.default.enumerator(at: sourcesRoot, includingPropertiesForKeys: nil) else {
            Issue.record("Could not enumerate \(sourcesRoot.path)")
            return
        }

        for case let url as URL in enumerator {
            guard url.pathExtension == "swift", url.lastPathComponent != "ProjectLibraryScaffolder.swift" else {
                continue
            }
            let source = try String(contentsOf: url, encoding: .utf8)
            guard source.contains("safeguards.md") else { continue }
            for token in writeTokens {
                let message = "\(url.path) names 'safeguards.md' and references '\(token)' — only " +
                    "ProjectLibraryScaffolder.swift may write that file, and only once, when absent"
                #expect(!source.contains(token), "\(message)")
            }
        }
    }

    // MARK: - Nothing puts a timer on a pending approval

    /// "A pending prompt has no timer" — an approval on a clock is consent nobody gave, and a denial
    /// on a clock is an outcome the user did not choose. There is no protocol member to call to prove
    /// this at runtime — the gate's and the prompt's own signatures are `async` with no deadline
    /// parameter — so this checks the one thing a future change could add without touching either
    /// signature: a timer or a scheduled deadline somewhere in the decision path itself.
    /// https://github.com/CalixtoTheBugHunter/talos/wiki/Safeguards-and-Autonomy#the-gate-fails-closed
    @Test("No file on the approval decision path schedules a timeout")
    func noFileOnTheApprovalPathSchedulesATimeout() throws {
        let forbiddenTokens = ["Timer(", "asyncAfter", "Task.sleep", "DispatchTime", "withTimeout"]
        let candidateFiles = [
            "Sources/TalosSafeguards/SafeguardsGate.swift",
            "Sources/TalosSafeguards/SafeguardsApprovalPrompt.swift",
            "Sources/TalosSafeguards/TieredSafeguardsGate.swift",
            "Sources/TalosUI/ApprovalPromptCenter.swift",
            "Sources/TalosUI/SafeguardsApprovalPromptView.swift",
            "Sources/TalosUI/ApprovalPromptHost.swift"
        ]

        for relativePath in candidateFiles {
            let url = Self.repositoryRoot.appendingPathComponent(relativePath)
            guard FileManager.default.fileExists(atPath: url.path) else {
                Issue.record("Expected \(relativePath) to exist — update this test if it moved or was renamed")
                continue
            }
            let source = try String(contentsOf: url, encoding: .utf8)
            for token in forbiddenTokens {
                #expect(!source.contains(token), "\(relativePath) references '\(token)' on the approval decision path")
            }
        }
    }
}
