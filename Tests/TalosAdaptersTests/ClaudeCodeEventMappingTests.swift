import Foundation
@testable import TalosAdapters
import Testing

/// Loads the real, scrubbed captures under `Fixtures/ClaudeCode/`, copied into
/// the test bundle by `Package.swift`'s `resources:`.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Engineering-Standards#the-suite-installs-nothing
enum ClaudeCodeFixture {
    static func url(_ name: String) -> URL {
        let resolved = Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Fixtures/ClaudeCode")
        guard let resolved else {
            fatalError("Fixture '\(name)' is missing from the test bundle — check Package.swift's resources:.")
        }
        return resolved
    }

    static func path(_ name: String) -> String {
        url(name).path
    }

    static func lines(_ name: String) throws -> [String] {
        let contents = try String(contentsOf: url(name), encoding: .utf8)
        return contents.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
    }
}

/// Asserts the mapping from a decoded stdout line to an ``AgentEvent`` —
/// against fixtures rather than invented JSON, per
/// § The suite installs nothing / fixtures are real captured output.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Engineering-Standards#the-suite-installs-nothing
@Suite("Claude Code event mapping")
struct ClaudeCodeEventMappingTests {
    @Test("A tool call decodes to a typed tool call, naming the tool and its target")
    func toolCallDecodes() throws {
        let lines = try ClaudeCodeFixture.lines("tool-call.jsonl")
        let value = try #require(ClaudeCodeStreamDecoder.decode(lines[1]))
        let event = try #require(ClaudeCodeEventMapper.agentEvent(for: value))

        guard case let .toolCall(call) = event else {
            Issue.record("Expected a tool call, got \(event)")
            return
        }
        #expect(call.name == "Read")
        #expect(call.targets == ["/private/tmp/fixture/README.md"])
    }

    @Test("A deferred result decodes to a permission request, distinct from a tool call")
    func permissionRequestDecodes() throws {
        let lines = try ClaudeCodeFixture.lines("permission-request.jsonl")
        let lastLine = try #require(lines.last)
        let value = try #require(ClaudeCodeStreamDecoder.decode(lastLine))
        let event = try #require(ClaudeCodeEventMapper.agentEvent(for: value))

        guard case let .permissionRequest(request) = event else {
            Issue.record("Expected a permission request, got \(event)")
            return
        }
        #expect(request.id == "toolu_fixture_write_0002")
        #expect(request.toolName == "Write")
    }

    /// § A tool call and a permission request are two events, never as one —
    /// https://github.com/CalixtoTheBugHunter/talos/wiki/Architecture-The-Orchestration-Boundary
    @Test("A run containing both a tool call and its permission request keeps them distinct")
    func bothTogetherDoNotCollapse() throws {
        let lines = try ClaudeCodeFixture.lines("both-together.jsonl")
        let events = lines.compactMap(ClaudeCodeStreamDecoder.decode).compactMap(ClaudeCodeEventMapper.agentEvent)

        #expect(events.count == 2)
        guard case let .toolCall(call) = events[0], case let .permissionRequest(request) = events[1] else {
            Issue.record("Expected [toolCall, permissionRequest], got \(events)")
            return
        }
        #expect(call.id == request.id)
        #expect(call.name == request.toolName)
    }

    @Test("A malformed line is skipped, and the lines around it still decode")
    func malformedLineIsTolerated() throws {
        let lines = try ClaudeCodeFixture.lines("malformed-output.jsonl")
        #expect(lines.count == 3)

        let decoded = lines.map(ClaudeCodeStreamDecoder.decode)
        #expect(decoded[0] != nil, "The init line should decode")
        #expect(decoded[1] == nil, "The truncated line should fail to decode rather than throw")
        #expect(decoded[2] != nil, "A good line after a malformed one should still decode")
    }

    @Test("An unrecognized JSON type is ignored rather than failing the decode")
    func unknownTypeIsIgnored() {
        #expect(ClaudeCodeStreamDecoder.decode(#"{"type":"command_lifecycle"}"#) == .ignored)
    }

    @Test("A line split across two reads is not decodable until the second read completes it")
    func lineSplitAcrossChunksIsBuffered() {
        var decoder = ClaudeCodeStreamDecoder()
        let first = decoder.takeLines(from: #"{"type":"resu"#)
        #expect(first.isEmpty)

        let second = decoder.takeLines(from: #"lt","subtype":"success"}"# + "\n")
        #expect(second == [#"{"type":"result","subtype":"success"}"#])
    }
}
