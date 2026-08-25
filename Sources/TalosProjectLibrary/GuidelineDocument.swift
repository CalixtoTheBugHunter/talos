import Foundation

// The typed model for one `.talos/guidelines/*.md` file — an Editable Talos
// Guideline. Each declares its purpose, the context it wants assembled, its
// token ceiling, and its output expectations for one sub-function.
// https://github.com/CalixtoTheBugHunter/talos/wiki/Talos-Guidelines#editable-talos-guidelines

public extension SubFunction {
    /// "Active at MVP" vs "Present but inert", per Talos Guidelines §
    /// Editable Talos Guidelines. `.advisor` and `.selfImprover` are
    /// generated and parse like any other guideline, but this is the fact a
    /// context assembler checks to never assemble either one into a prompt
    /// at MVP.
    /// https://github.com/CalixtoTheBugHunter/talos/wiki/Talos-Guidelines#editable-talos-guidelines
    /// https://github.com/CalixtoTheBugHunter/talos/wiki/MVP-Definition-of-Done#checklist
    var isActiveAtMVP: Bool {
        switch self {
        case .assistant, .automator: true
        case .advisor, .selfImprover: false
        }
    }

    /// The exact filename `ProjectLibraryScaffolder` generates under
    /// `.talos/guidelines/` for this sub-function.
    var guidelineFileName: String {
        "\(rawValue).md"
    }
}

/// The parsed contents of one Editable Talos Guideline file. `rawText` is
/// the file's exact, unmodified text, kept alongside the four typed fields
/// so a hand edit round-trips without loss even though nothing in this
/// module writes the file back.
public struct GuidelineDocument: Equatable, Sendable {
    public let subFunction: SubFunction
    public let purpose: String
    public let context: [String]
    public let tokenCeiling: Int
    public let outputExpectations: String
    public let rawText: String

    public init(
        subFunction: SubFunction,
        purpose: String,
        context: [String],
        tokenCeiling: Int,
        outputExpectations: String,
        rawText: String
    ) {
        self.subFunction = subFunction
        self.purpose = purpose
        self.context = context
        self.tokenCeiling = tokenCeiling
        self.outputExpectations = outputExpectations
        self.rawText = rawText
    }
}

/// A validation failure that names the file, the line, and the fix — the
/// same shape every other manifest error in this module uses.
public struct GuidelineDocumentError: Error, Equatable, Sendable {
    /// The path of the file that failed to parse or validate.
    public let file: String
    /// The 1-indexed source line the failure was found at, when the parser
    /// could locate one.
    public let line: Int?
    /// What to change to fix it, stated as an instruction.
    public let fix: String

    public init(file: String, line: Int?, fix: String) {
        self.file = file
        self.line = line
        self.fix = fix
    }
}
