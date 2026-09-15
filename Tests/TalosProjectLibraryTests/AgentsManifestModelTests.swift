@testable import TalosProjectLibrary
import Testing

/// Verifies the optional `model:` selection on an `agents.yaml` agent —
/// adopted by [decision 90](https://github.com/CalixtoTheBugHunter/talos/wiki/Decision-Log#engineering-decisions)
/// and applied via the CLI's `--model` flag per
/// [decision 91](https://github.com/CalixtoTheBugHunter/talos/wiki/Decision-Log#engineering-decisions).
/// Parsing and validation are the same either way; how it reaches the CLI is
/// asserted in the adapter's own tests.
@Suite("Agents manifest model selection")
struct AgentsManifestModelTests {
    /// The declared model is a selection carried through verbatim.
    @Test("A pinned model is carried through verbatim")
    func aPinnedModelIsCarriedThroughVerbatim() throws {
        let yaml = """
        agents:
          claude-code:
            adapter: claude-code
            model: claude-opus-4-8
        """

        let manifest = try AgentsManifestParser.parse(contents: yaml, file: "agents.yaml")
        #expect(manifest.agents.first?.model == "claude-opus-4-8")
    }

    /// No `model:` leaves the choice to the CLI's own configuration — the
    /// launch decision 89 restored — so the parsed value is `nil`, not empty.
    @Test("An absent model parses as nil, leaving the choice to the CLI")
    func anAbsentModelParsesAsNil() throws {
        let yaml = """
        agents:
          claude-code:
            adapter: claude-code
        """

        let manifest = try AgentsManifestParser.parse(contents: yaml, file: "agents.yaml")
        #expect(manifest.agents.first?.model == nil)
    }

    /// Decision 90: the block "holds selection, never a credential". A
    /// `keychain:` reference is a secret reference, so it is rejected — a
    /// model is named directly.
    @Test("A keychain: reference as the model fails validation")
    func aKeychainReferenceAsModelFailsValidation() {
        let yaml = """
        agents:
          claude-code:
            adapter: claude-code
            model: keychain:some-model
        """

        #expect {
            try AgentsManifestParser.parse(contents: yaml, file: "agents.yaml")
        } throws: { error in
            guard let error = error as? AgentsManifestError else { return false }
            return error.file == "agents.yaml" && error.line != nil && error.fix.contains("model")
        }
    }

    /// Decision 90: "a key placed in it is the same validation error a
    /// secret-shaped `env` literal already is", and — like that error — it
    /// names the key, never the value. Assembled from non-contiguous parts so
    /// no secret-shaped literal is committed whole.
    @Test("A secret-shaped model value fails validation, naming the field and not the value")
    func aSecretShapedModelValueFailsValidation() {
        let secretShaped = "sk-" + String(repeating: "A", count: 40)
        let yaml = """
        agents:
          claude-code:
            adapter: claude-code
            model: \(secretShaped)
        """

        #expect {
            try AgentsManifestParser.parse(contents: yaml, file: "agents.yaml")
        } throws: { error in
            guard let error = error as? AgentsManifestError else { return false }
            return error.file == "agents.yaml" && error.line != nil &&
                error.fix.contains("model") && !error.fix.contains(secretShaped)
        }
    }

    /// An empty value is not a model selection.
    @Test("An empty model string fails validation")
    func anEmptyModelStringFailsValidation() {
        let yaml = """
        agents:
          claude-code:
            adapter: claude-code
            model: ""
        """

        #expect {
            try AgentsManifestParser.parse(contents: yaml, file: "agents.yaml")
        } throws: { error in
            guard let error = error as? AgentsManifestError else { return false }
            return error.file == "agents.yaml" && error.fix.contains("model")
        }
    }
}
