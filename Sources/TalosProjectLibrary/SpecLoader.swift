import Foundation

/// Loads `.talos/spec.yaml` and parses it through ``SpecManifestParser`` — the
/// one way any part of Talos resolves where a project's Spec Drive lives, or
/// that it declares none. Nothing here reaches the wiki: fetching its content
/// is the agent's out-of-band work per
/// [decision 83](https://github.com/CalixtoTheBugHunter/talos/wiki/Decision-Log#foundational-decisions).
/// A missing file is a validation error, never read as an absent Spec Drive —
/// "a missing `specDrive` key, or a missing `status`, is a validation error —
/// never read as absence".
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Project-Library#spec-drive
public enum SpecLoader {
    private static let relativePath = ".talos/spec.yaml"

    /// Reads and validates `.talos/spec.yaml` under `projectRoot`. Throws a
    /// ``SpecManifestError`` for a missing or unreadable file and for any
    /// validation failure the parser finds — a Spec Drive's absence is a
    /// declared value inside the file, never inferred from the file not being
    /// there.
    public static func load(
        projectRoot: URL,
        fileManager: FileManager = .default
    ) throws -> SpecManifest {
        let file = projectRoot.appendingPathComponent(relativePath, isDirectory: false)

        guard fileManager.fileExists(atPath: file.path) else {
            throw SpecManifestError(
                file: file.path,
                line: nil,
                fix: "Create '\(relativePath)' declaring 'specDrive.status: absent' or 'present' — " +
                    "a missing file is never read as an absent Spec Drive."
            )
        }

        let rawText: String
        do {
            rawText = try String(contentsOf: file, encoding: .utf8)
        } catch {
            throw SpecManifestError(
                file: file.path,
                line: nil,
                fix: "Fix '\(relativePath)' so it can be read as UTF-8 text: \(error)"
            )
        }
        return try SpecManifestParser.parse(contents: rawText, file: file.path)
    }
}
