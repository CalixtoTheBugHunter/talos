import Foundation

/// One session's `PreToolUse` gate: writes the `--settings` file and gate
/// script into a directory this adapter owns — never `~/.claude/` or the
/// project's own `.claude/` — and answers a tool call with the decision
/// recorded for its id, deferring when none has been recorded yet.
///
/// Deferring rather than denying by default is what lets a request wait with
/// "no timeout or retry limit" while ``AgentAdapter/resolve(_:with:)`` is still
/// unresolved.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Architecture-The-Orchestration-Boundary
struct ClaudeCodeHookConfiguration: Equatable, Hashable, Sendable {
    /// Passed to `--settings` on every `claude` invocation this session runs.
    let settingsPath: String
    private let directory: URL
    private let decisionsDirectory: URL

    init(rootDirectory: URL = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)) throws {
        directory = rootDirectory.appendingPathComponent("talos-claude-code-\(UUID().uuidString)", isDirectory: true)
        decisionsDirectory = directory.appendingPathComponent("decisions", isDirectory: true)
        let deferPath = directory.appendingPathComponent("defer.json")
        let gateScriptPath = directory.appendingPathComponent("gate.sh")
        let settingsURL = directory.appendingPathComponent("settings.json")
        settingsPath = settingsURL.path

        try FileManager.default.createDirectory(at: decisionsDirectory, withIntermediateDirectories: true)
        try Self.deferJSON.write(to: deferPath, atomically: true, encoding: .utf8)
        try Self.gateScript(deferPath: deferPath.path, decisionsDirectory: decisionsDirectory.path)
            .write(to: gateScriptPath, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: gateScriptPath.path)
        let settingsJSON = Self.settingsJSON(gateScriptPath: gateScriptPath.path)
        try settingsJSON.write(to: settingsURL, atomically: true, encoding: .utf8)
    }

    /// Records the gate's `decision` for `toolUseID`, so the next resume's
    /// hook answers it instead of deferring again.
    func recordDecision(_ decision: AgentPermissionDecision, reason: String, for toolUseID: String) throws {
        let value = decision == .allowed ? "allow" : "deny"
        let json = """
        {"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"\(value)",\
        "permissionDecisionReason":"\(Self.jsonEscaped(reason))"}}
        """
        let path = decisionsDirectory.appendingPathComponent("\(toolUseID).json")
        try json.write(to: path, atomically: true, encoding: .utf8)
    }

    /// Removes everything this session wrote, once the run has ended.
    func cleanUp() {
        try? FileManager.default.removeItem(at: directory)
    }

    private static let deferJSON =
        #"{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"defer"}}"#

    /// Reads `tool_use_id` by pattern rather than a JSON parser, so the gate
    /// depends on nothing but `/bin/sh`, `cat`, `tr`, and `sed`.
    private static func gateScript(deferPath: String, decisionsDirectory: String) -> String {
        """
        #!/bin/sh
        input=$(/bin/cat)
        identifier=$(printf '%s' "$input" | /usr/bin/tr -d '\\n' | \\
            /usr/bin/sed -n 's/.*"tool_use_id"[[:space:]]*:[[:space:]]*"\\([^"]*\\)".*/\\1/p')
        decision="\(decisionsDirectory)/$identifier.json"
        if [ -n "$identifier" ] && [ -f "$decision" ]; then
          /bin/cat "$decision"
        else
          /bin/cat "\(deferPath)"
        fi
        """
    }

    private static func settingsJSON(gateScriptPath: String) -> String {
        let command = jsonEscaped("/bin/sh '\(gateScriptPath)'")
        return """
        {"hooks":{"PreToolUse":[{"matcher":"*","hooks":[{"type":"command","command":"\(command)"}]}]}}
        """
    }

    private static func jsonEscaped(_ string: String) -> String {
        var result = ""
        for scalar in string.unicodeScalars {
            switch scalar {
            case "\"": result += "\\\""
            case "\\": result += "\\\\"
            case "\n": result += "\\n"
            default: result.unicodeScalars.append(scalar)
            }
        }
        return result
    }
}
