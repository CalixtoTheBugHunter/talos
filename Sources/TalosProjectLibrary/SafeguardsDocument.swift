import Foundation

/// The loaded contents of `.talos/safeguards.md`, the highest-authority
/// project-level document, never editable by AI. `rawText` is the file's
/// literal text, never parsed into a structure that could let something
/// written inside it be read as an instruction rather than data — the same
/// posture the SPEC states for third-party content, applied to this file's
/// own text.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Safeguards-and-Autonomy#prompt-injection-posture
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Talos-Guidelines#authority-order
///
/// One value, one property: the copy assembled into a prompt (advisory) and
/// the copy the gate reads (enforcement) are the same `rawText`, never two
/// representations that could drift apart — see Architecture: The
/// Orchestration Boundary § What is persistent context, and what is not.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Architecture-The-Orchestration-Boundary
public struct SafeguardsDocument: Equatable, Sendable {
    public let rawText: String

    public init(rawText: String) {
        self.rawText = rawText
    }
}

/// A failure to load `.talos/safeguards.md` — loud and blocking, never a
/// silent default-open.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Project-Library#safeguards
public struct SafeguardsLoadError: Error, Equatable, Sendable {
    /// The path of the file that could not be loaded.
    public let file: String
    /// What to change to fix it, stated as an instruction.
    public let fix: String

    public init(file: String, fix: String) {
        self.file = file
        self.fix = fix
    }
}
