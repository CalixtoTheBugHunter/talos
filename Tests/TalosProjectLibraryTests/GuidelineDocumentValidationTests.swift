@testable import TalosProjectLibrary
import Testing

/// Verifies every `.talos/guidelines/*.md` validation failure against
/// ``GuidelineDocumentParser`` — the missing-token-ceiling error AC6 requires,
/// every other declared element being required too, and the front matter
/// block's own shape. Split from ``GuidelineDocumentTests`` to keep each
/// suite under the type-body-length limit.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Talos-Guidelines#editable-talos-guidelines
@Suite("Guideline document validation")
struct GuidelineDocumentValidationTests {
    // MARK: - Token ceiling: the machine-readable number the assembler enforces

    @Test("A missing token ceiling fails validation, naming the file and a fix")
    func missingTokenCeilingFailsValidation() {
        let contents = """
        ---
        purpose: >-
          Purpose text.
        context: []
        outputExpectations: >-
          Output text.
        ---
        """

        #expect {
            try GuidelineDocumentParser.parse(contents: contents, subFunction: .assistant, file: "assistant.md")
        } throws: { error in
            guard let error = error as? GuidelineDocumentError else { return false }
            return error.file == "assistant.md" && error.fix.contains("tokenCeiling")
        }
    }

    @Test("A zero token ceiling fails validation")
    func zeroTokenCeilingFailsValidation() {
        let contents = """
        ---
        purpose: >-
          Purpose text.
        context: []
        tokenCeiling: 0
        outputExpectations: >-
          Output text.
        ---
        """

        #expect {
            try GuidelineDocumentParser.parse(contents: contents, subFunction: .assistant, file: "assistant.md")
        } throws: { error in
            guard let error = error as? GuidelineDocumentError else { return false }
            return error.fix.contains("tokenCeiling")
        }
    }

    @Test("A non-integer token ceiling fails validation")
    func nonIntegerTokenCeilingFailsValidation() {
        let contents = """
        ---
        purpose: >-
          Purpose text.
        context: []
        tokenCeiling: not-a-number
        outputExpectations: >-
          Output text.
        ---
        """

        #expect {
            try GuidelineDocumentParser.parse(contents: contents, subFunction: .assistant, file: "assistant.md")
        } throws: { error in
            guard let error = error as? GuidelineDocumentError else { return false }
            return error.fix.contains("tokenCeiling")
        }
    }

    // MARK: - Every other declared element is required too

    @Test("A missing purpose fails validation")
    func missingPurposeFailsValidation() {
        let contents = """
        ---
        context: []
        tokenCeiling: 1000
        outputExpectations: >-
          Output text.
        ---
        """

        #expect {
            try GuidelineDocumentParser.parse(contents: contents, subFunction: .assistant, file: "assistant.md")
        } throws: { error in
            guard let error = error as? GuidelineDocumentError else { return false }
            return error.fix.contains("purpose")
        }
    }

    @Test("A non-sequence context fails validation")
    func nonSequenceContextFailsValidation() {
        let contents = """
        ---
        purpose: >-
          Purpose text.
        context: not-a-sequence
        tokenCeiling: 1000
        outputExpectations: >-
          Output text.
        ---
        """

        #expect {
            try GuidelineDocumentParser.parse(contents: contents, subFunction: .assistant, file: "assistant.md")
        } throws: { error in
            guard let error = error as? GuidelineDocumentError else { return false }
            return error.fix.contains("context")
        }
    }

    @Test("A missing outputExpectations fails validation")
    func missingOutputExpectationsFailsValidation() {
        let contents = """
        ---
        purpose: >-
          Purpose text.
        context: []
        tokenCeiling: 1000
        ---
        """

        #expect {
            try GuidelineDocumentParser.parse(contents: contents, subFunction: .assistant, file: "assistant.md")
        } throws: { error in
            guard let error = error as? GuidelineDocumentError else { return false }
            return error.fix.contains("outputExpectations")
        }
    }

    // MARK: - The front matter block itself

    @Test("A file with no opening --- fails validation")
    func missingOpeningDelimiterFailsValidation() {
        let contents = "purpose: >-\n  Purpose text.\n"

        #expect {
            try GuidelineDocumentParser.parse(contents: contents, subFunction: .assistant, file: "assistant.md")
        } throws: { error in
            guard let error = error as? GuidelineDocumentError else { return false }
            return error.file == "assistant.md" && !error.fix.isEmpty
        }
    }

    @Test("A front matter block that never closes fails validation")
    func unclosedFrontMatterFailsValidation() {
        let contents = """
        ---
        purpose: >-
          Purpose text.
        """

        #expect {
            try GuidelineDocumentParser.parse(contents: contents, subFunction: .assistant, file: "assistant.md")
        } throws: { error in
            guard let error = error as? GuidelineDocumentError else { return false }
            return error.fix.contains("never closes")
        }
    }

    @Test("Malformed YAML syntax inside the front matter names the file and a fix")
    func malformedYAMLNamesFileAndFix() {
        let contents = """
        ---
        purpose: [unterminated
        ---
        """

        #expect {
            try GuidelineDocumentParser.parse(contents: contents, subFunction: .assistant, file: "assistant.md")
        } throws: { error in
            guard let error = error as? GuidelineDocumentError else { return false }
            return error.file == "assistant.md" && !error.fix.isEmpty
        }
    }
}
