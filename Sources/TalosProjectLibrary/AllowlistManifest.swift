import Foundation

/// The parsed, un-validated contents of `.talos/allowlist.yaml` — one file
/// per project, so the file itself is the per-project scope: there is no
/// field here for a second project, and no shape for "every project" or
/// "every action type".
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Safeguards-and-Autonomy#rules
///
/// `entries` holds the action-type names exactly as written, with no
/// awareness of the taxonomy — this module has no dependency on
/// `TalosSafeguards`, where the taxonomy and its classifier live. Whether a
/// name is recognized, and whether its tier may be allowlisted at all, is
/// validated by the store that loads this manifest, not by this parse.
public struct AllowlistManifest: Equatable, Sendable {
    public let entries: [String]

    public init(entries: [String] = []) {
        self.entries = entries
    }
}

/// A validation failure that names the file, the line, and the fix — the
/// same shape ``ConnectorsManifestError`` uses.
public struct AllowlistManifestError: Error, Equatable, Sendable {
    /// The path of the file that failed to parse.
    public let file: String
    /// The 1-indexed source line the failure was found at, when the YAML
    /// parser could locate one.
    public let line: Int?
    /// What to change to fix it, stated as an instruction.
    public let fix: String
}
