import Foundation
import OSLog
@testable import TalosCore
@testable import TalosProjectLibrary
import Testing

/// What `KeychainSecretAccessorTests.DenyingAuthorizer` throws.
private struct DenyingAuthorizerError: Error {}

/// Verifies ``KeychainSecretAccessor`` against
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Technology-and-Distribution#decisions,
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Safeguards-and-Autonomy#irreversible--outward-facing,
/// and https://github.com/CalixtoTheBugHunter/talos/wiki/Decision-Log#engineering-decisions
/// (decision 71).
@Suite("Keychain secret accessor")
struct KeychainSecretAccessorTests {
    /// Always authorizes — used by tests that are not exercising Rule 5's
    /// denial path.
    private struct AllowingAuthorizer: SecretAccessAuthorizing {
        func authorize(_: SecretAccessAction) throws {
            // Always authorizes.
        }
    }

    /// Always denies, and records the last action it was asked to
    /// authorize, so a test can assert the accessor called it with the
    /// exact action before touching the Keychain.
    private final class DenyingAuthorizer: SecretAccessAuthorizing, @unchecked Sendable {
        private(set) var lastAction: SecretAccessAction?

        func authorize(_ action: SecretAccessAction) throws {
            lastAction = action
            throw DenyingAuthorizerError()
        }
    }

    /// A fresh keychain name per test, so parallel tests never collide on
    /// the same Keychain item.
    private static func freshReference() -> SecretReference {
        SecretReference(keychainName: "test-\(UUID().uuidString)")
    }

    private static func freshProject() -> ProjectIdentifier {
        .generate()
    }

    /// Deletes whatever `reference` under `project` resolved to, ignoring
    /// whether anything was actually there — every test that writes cleans
    /// up after itself regardless of pass or fail.
    private static func cleanUp(_ reference: SecretReference, project: ProjectIdentifier) {
        try? KeychainSecretAccessor(authorizer: AllowingAuthorizer()).delete(reference, project: project)
    }

    // MARK: - Round trip and namespacing (AC1, AC2)

    @Test("A written secret reads back the same value")
    func writtenSecretReadsBackTheSameValue() throws {
        let accessor = KeychainSecretAccessor(authorizer: AllowingAuthorizer())
        let reference = Self.freshReference()
        let project = Self.freshProject()
        defer { Self.cleanUp(reference, project: project) }

        try accessor.write(reference, project: project, value: "correct-horse-battery-staple")
        #expect(try accessor.read(reference, project: project) == "correct-horse-battery-staple")
    }

    @Test("Two projects using the same reference name never read each other's secret")
    func twoProjectsWithTheSameNameDoNotCollide() throws {
        let accessor = KeychainSecretAccessor(authorizer: AllowingAuthorizer())
        let reference = Self.freshReference()
        let projectA = Self.freshProject()
        let projectB = Self.freshProject()
        defer {
            Self.cleanUp(reference, project: projectA)
            Self.cleanUp(reference, project: projectB)
        }

        try accessor.write(reference, project: projectA, value: "project-a-secret")
        try accessor.write(reference, project: projectB, value: "project-b-secret")

        #expect(try accessor.read(reference, project: projectA) == "project-a-secret")
        #expect(try accessor.read(reference, project: projectB) == "project-b-secret")
    }

    @Test("Writing again for the same project and name updates rather than duplicating")
    func writingAgainUpdatesRatherThanDuplicating() throws {
        let accessor = KeychainSecretAccessor(authorizer: AllowingAuthorizer())
        let reference = Self.freshReference()
        let project = Self.freshProject()
        defer { Self.cleanUp(reference, project: project) }

        try accessor.write(reference, project: project, value: "first-value")
        try accessor.write(reference, project: project, value: "second-value")

        #expect(try accessor.read(reference, project: project) == "second-value")
    }

    // MARK: - A missing secret is an actionable error, never an empty string (AC6)

    @Test("Reading a name nothing was ever written for throws an actionable error")
    func readingAnUnwrittenNameThrowsAnActionableError() {
        let accessor = KeychainSecretAccessor(authorizer: AllowingAuthorizer())
        let reference = Self.freshReference()
        let project = Self.freshProject()

        #expect {
            _ = try accessor.read(reference, project: project)
        } throws: { error in
            guard let error = error as? MissingSecretError else { return false }
            return error.keychainName == reference.keychainName && error.project == project &&
                !error.fix.isEmpty
        }
    }

    // MARK: - Reading is a gated action (AC5)

    @Test("A denied authorization prevents the read and names the exact action")
    func deniedAuthorizationPreventsTheRead() throws {
        let allowing = KeychainSecretAccessor(authorizer: AllowingAuthorizer())
        let denying = DenyingAuthorizer()
        let reference = Self.freshReference()
        let project = Self.freshProject()
        defer { Self.cleanUp(reference, project: project) }

        try allowing.write(reference, project: project, value: "should-not-be-readable")

        #expect(throws: SecretAccessDenied.self) {
            _ = try KeychainSecretAccessor(authorizer: denying).read(reference, project: project)
        }
        #expect(denying.lastAction == SecretAccessAction(
            kind: .read, project: project, keychainName: reference.keychainName
        ))

        // The secret is untouched by the denial: an allowed accessor still reads the original value.
        #expect(try allowing.read(reference, project: project) == "should-not-be-readable")
    }

    @Test("A denied authorization prevents the write from ever reaching the Keychain")
    func deniedAuthorizationPreventsTheWrite() throws {
        let denying = DenyingAuthorizer()
        let allowing = KeychainSecretAccessor(authorizer: AllowingAuthorizer())
        let reference = Self.freshReference()
        let project = Self.freshProject()
        defer { Self.cleanUp(reference, project: project) }

        #expect(throws: SecretAccessDenied.self) {
            try KeychainSecretAccessor(authorizer: denying).write(reference, project: project, value: "denied-value")
        }
        #expect(denying.lastAction == SecretAccessAction(
            kind: .write, project: project, keychainName: reference.keychainName
        ))

        #expect {
            _ = try allowing.read(reference, project: project)
        } throws: { $0 is MissingSecretError }
    }

    @Test("A denied authorization prevents the delete from ever reaching the Keychain")
    func deniedAuthorizationPreventsTheDelete() throws {
        let denying = DenyingAuthorizer()
        let allowing = KeychainSecretAccessor(authorizer: AllowingAuthorizer())
        let reference = Self.freshReference()
        let project = Self.freshProject()
        defer { Self.cleanUp(reference, project: project) }

        try allowing.write(reference, project: project, value: "should-survive-the-denied-delete")

        #expect(throws: SecretAccessDenied.self) {
            try KeychainSecretAccessor(authorizer: denying).delete(reference, project: project)
        }
        #expect(denying.lastAction == SecretAccessAction(
            kind: .write, project: project, keychainName: reference.keychainName
        ))

        #expect(try allowing.read(reference, project: project) == "should-survive-the-denied-delete")
    }

    // MARK: - No thrown error ever carries the secret value

    @Test("A denial error's description never contains the secret value")
    func denialErrorNeverContainsTheSecretValue() {
        let denying = DenyingAuthorizer()
        let reference = Self.freshReference()
        let project = Self.freshProject()

        do {
            try KeychainSecretAccessor(authorizer: denying).write(
                reference, project: project, value: "must-never-appear-in-any-error"
            )
            Issue.record("Expected the write to be denied")
        } catch {
            #expect(!"\(error)".contains("must-never-appear-in-any-error"))
        }
    }

    // MARK: - Access is logged without the value (AC4)

    @Test("A successful read logs an access event naming the key but never the value")
    func successfulReadLogsAnAccessEventWithoutTheValue() throws {
        let accessor = KeychainSecretAccessor(authorizer: AllowingAuthorizer())
        let reference = Self.freshReference()
        let project = Self.freshProject()
        defer { Self.cleanUp(reference, project: project) }

        try accessor.write(reference, project: project, value: "logged-access-should-not-leak-this")
        _ = try accessor.read(reference, project: project)

        let store = try OSLogStore(scope: .currentProcessIdentifier)
        let entries = try store.getEntries(at: store.position(date: .distantPast))
            .compactMap { $0 as? OSLogEntryLog }
            .filter { $0.subsystem == Log.Category.projectLibrary.subsystem }

        let readEvents = entries.filter { $0.composedMessage.contains(SecretAccessKind.read.rawValue) }
        #expect(readEvents.contains { $0.composedMessage.contains(reference.keychainName) })
        #expect(entries.allSatisfy { !$0.composedMessage.contains("logged-access-should-not-leak-this") })
    }
}
