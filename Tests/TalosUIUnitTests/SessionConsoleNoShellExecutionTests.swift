import Foundation
import Testing

/// Asserts the console module has no free-form command execution path.
///
/// > It is deliberately not a PTY. There is no embedded shell tab... Every
/// > command therefore flows through the Safeguards gate and is auditable. A
/// > real shell tab would let commands bypass it.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Session-Console#what-it-is-not
///
/// Scoped to `Sources/TalosUI` — the console — rather than the repository:
/// `Sources/TalosAdapters` is the one layer permitted to spawn a subprocess
/// at all, per § Only the adapter layer spawns a process, so a spawn
/// primitive there is not this suite's concern. This suite's claim is
/// narrower and specific to the console: nothing in the surface a user types
/// into ever reaches a shell or a process directly, the same style
/// `NoPollingTimerTests` and `NoMCPConnectionTests` already use for a
/// module-scoped source read.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Architecture-The-Orchestration-Boundary
@Suite("The session console has no free-form command execution path")
struct SessionConsoleNoShellExecutionTests {
    /// Subprocess-spawn and shell-execution primitives — a console file
    /// naming any of these would be a path from console input to a process
    /// that never passed through the adapter, and never through the gate.
    ///
    /// The six that `spec-guard.sh`'s own subprocess/shell-path regexes
    /// would otherwise match verbatim are joined from two halves that
    /// individually match neither, so this file's own literals do not trip
    /// that CI check — the same non-contiguous-parts technique § A
    /// scanner's self-test never commits its fixture whole uses for the
    /// same shape of problem. `execv`, `execl`, and `system(` need no split:
    /// none of `spec-guard.sh`'s patterns match them as written.
    /// https://github.com/CalixtoTheBugHunter/talos/wiki/Engineering-Standards
    static let forbiddenFragments = [
        "NS" + "Task", "Process" + "(", "posix_" + "spawn", "execv", "execl",
        "popen" + "(", "system(", "/bin/" + "sh", "/bin/" + "bash"
    ]

    static var repositoryRoot: URL {
        var url = URL(fileURLWithPath: #filePath)
        while url.pathComponents.count > 1 {
            url.deleteLastPathComponent()
            if FileManager.default.fileExists(atPath: url.appendingPathComponent("Package.swift").path) {
                return url
            }
        }
        fatalError("Could not locate repository root above \(#filePath)")
    }

    static var consoleModuleFiles: [URL] {
        get throws {
            try FileManager.default
                .contentsOfDirectory(
                    at: repositoryRoot.appendingPathComponent("Sources/TalosUI"),
                    includingPropertiesForKeys: nil
                )
                .filter { $0.pathExtension == "swift" }
        }
    }

    /// Catches the regression a shell tab would look like: a "run this in a
    /// terminal" convenience added to the console that starts a process
    /// directly instead of handing the string to the agent adapter.
    @Test("No file in the console module names a subprocess-spawn or shell primitive")
    func noConsoleFileNamesAShellPrimitive() throws {
        let files = try Self.consoleModuleFiles
        // A discovery that found nothing would make the assertion below vacuous.
        #expect(!files.isEmpty)

        for file in files {
            let source = try String(contentsOf: file, encoding: .utf8)
            for fragment in Self.forbiddenFragments {
                #expect(!source.contains(fragment), "\(file.lastPathComponent) references '\(fragment)'")
            }
        }
    }
}
