@testable import TalosOrchestration
import TalosProjectLibrary
import Testing

/// Verifies rendering `connectors.yaml` into prompt text never touches
/// `env` — the acceptance criterion that assembled context never includes a
/// secret. https://github.com/CalixtoTheBugHunter/talos/wiki/Project-Library#connectors
@Suite("Connectors context rendering")
struct ConnectorsContextRenderingTests {
    @Test("An empty manifest renders as declared, not as blank")
    func emptyManifestRendersADeclaredMessage() {
        let text = ConnectorsContextRendering.render(ConnectorsManifest())
        #expect(text == "No connectors are declared for this project.")
    }

    @Test("Rendering names kind, target, and access method, but never any env value or key")
    func rendersOnlyPublicFieldsNeverEnv() {
        let manifest = ConnectorsManifest(connectors: [
            ConnectorDeclaration(
                name: "github-repo",
                kind: .repo,
                target: "https://github.com/org/repo",
                reachedVia: .mcp,
                env: [
                    "GITHUB_TOKEN": .secret(SecretReference(keychainName: "github-pat")),
                    "NODE_ENV": .literal("production")
                ]
            )
        ])

        let text = ConnectorsContextRendering.render(manifest)

        #expect(text.contains("github-repo"))
        #expect(text.contains("repo"))
        #expect(text.contains("https://github.com/org/repo"))
        #expect(text.contains("mcp"))
        #expect(!text.contains("GITHUB_TOKEN"))
        #expect(!text.contains("github-pat"))
        #expect(!text.contains("NODE_ENV"))
        #expect(!text.contains("production"))
    }
}
