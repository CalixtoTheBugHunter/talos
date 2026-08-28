import TalosProjectLibrary

/// Renders a ``ConnectorsManifest`` into the text assembled for the
/// `connectors` context part. Only `name`, `kind`, `target`, and
/// `reachedVia` are ever rendered — `env` is never touched, so a
/// ``SecretReference`` or a literal configuration value can never reach the
/// prompt through this path.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Project-Library#connectors
enum ConnectorsContextRendering {
    static func render(_ manifest: ConnectorsManifest) -> String {
        guard !manifest.connectors.isEmpty else {
            return "No connectors are declared for this project."
        }
        let lines = manifest.connectors.map { connector in
            "\(connector.name) (\(connector.kind.rawValue)) -> \(connector.target) via \(connector.reachedVia.rawValue)"
        }
        return (["Declared connectors:"] + lines).joined(separator: "\n")
    }
}
