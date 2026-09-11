import Foundation
@testable import TalosProjectLibrary
import Testing

/// Verifies `.talos/spec.yaml` loading against
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Project-Library#spec-drive
/// — a declared-absent Spec Drive is a value the loader returns, a present one
/// resolves its locations through the provider interface, and a missing file is
/// a validation error rather than read as absence.
@Suite("Spec loader")
struct SpecLoaderTests {
    private static func temporaryProjectRoot() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    }

    /// Writes `contents` to `.talos/spec.yaml` under a fresh temporary root and
    /// returns that root.
    private static func projectRoot(withSpecYAML contents: String) throws -> URL {
        let root = temporaryProjectRoot()
        let talos = root.appendingPathComponent(".talos", isDirectory: true)
        try FileManager.default.createDirectory(at: talos, withIntermediateDirectories: true)
        try contents.write(
            to: talos.appendingPathComponent("spec.yaml", isDirectory: false),
            atomically: true,
            encoding: .utf8
        )
        return root
    }

    @Test("A declared-absent Spec Drive loads as .absent")
    func declaredAbsentLoadsAsAbsent() throws {
        let root = try Self.projectRoot(withSpecYAML: """
        specDrive:
          status: absent
        """)

        let manifest = try SpecLoader.load(projectRoot: root)

        #expect(manifest.specDrive == .absent)
    }

    @Test("A present Spec Drive resolves its GitHub Wiki location through the provider interface")
    func presentLoadsLocations() throws {
        let root = try Self.projectRoot(withSpecYAML: """
        specDrive:
          status: present
          locations:
            - provider: github-wiki
              url: https://github.com/org/repo/wiki
              syncRule: read-only
        """)

        let manifest = try SpecLoader.load(projectRoot: root)

        #expect(manifest.specDrive == .locations([
            SpecDriveLocation(
                provider: .githubWiki,
                url: "https://github.com/org/repo/wiki",
                syncRule: .readOnly
            )
        ]))
    }

    @Test("A missing spec.yaml is a validation error naming the file, never read as absence")
    func missingFileIsAnError() throws {
        let root = Self.temporaryProjectRoot()
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent(".talos", isDirectory: true),
            withIntermediateDirectories: true
        )

        #expect(throws: SpecManifestError.self) {
            try SpecLoader.load(projectRoot: root)
        }
    }

    @Test("A malformed spec.yaml surfaces the parser's validation error")
    func malformedFileThrows() throws {
        let root = try Self.projectRoot(withSpecYAML: """
        specDrive:
          status: present
        """)

        #expect(throws: SpecManifestError.self) {
            try SpecLoader.load(projectRoot: root)
        }
    }
}
