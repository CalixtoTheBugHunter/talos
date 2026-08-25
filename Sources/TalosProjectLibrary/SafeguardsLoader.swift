import Foundation

/// Loads `.talos/safeguards.md`. This is the only way any part of Talos may
/// access the file's contents, and it is deliberately read-only: no type
/// here offers a way to write, edit, or delete `safeguards.md` —
/// `config.safeguards.write` is refused outright rather than gated, per
/// Safeguards & Autonomy § Refused — not a tier, so there is no write path
/// here to gate in the first place. `ProjectLibraryScaffolder` still creates
/// this file once, only when absent, as part of generating `.talos/` on
/// project add — that single, idempotent, non-overwriting entry is the one
/// sanctioned exception to "read-only" here, and it is covered separately.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Safeguards-and-Autonomy#refused--not-a-tier
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Project-Library#safeguards
public enum SafeguardsLoader {
    private static let relativePath = ".talos/safeguards.md"

    /// Reads `.talos/safeguards.md` under `projectRoot` and returns its
    /// literal text as a ``SafeguardsDocument``. A missing file throws
    /// ``SafeguardsLoadError`` rather than returning an empty or default
    /// document — Safeguards, the highest-authority project document, has
    /// no silent default-open.
    /// https://github.com/CalixtoTheBugHunter/talos/wiki/Project-Library#safeguards
    public static func load(
        projectRoot: URL,
        fileManager: FileManager = .default
    ) throws -> SafeguardsDocument {
        let file = projectRoot.appendingPathComponent(relativePath, isDirectory: false)

        guard fileManager.fileExists(atPath: file.path) else {
            throw SafeguardsLoadError(
                file: file.path,
                fix: "Create '\(relativePath)' — a missing Safeguards document blocks the session " +
                    "rather than running with none."
            )
        }

        do {
            let rawText = try String(contentsOf: file, encoding: .utf8)
            return SafeguardsDocument(rawText: rawText)
        } catch {
            throw SafeguardsLoadError(
                file: file.path,
                fix: "Fix '\(relativePath)' so it can be read as UTF-8 text: \(error)"
            )
        }
    }
}
