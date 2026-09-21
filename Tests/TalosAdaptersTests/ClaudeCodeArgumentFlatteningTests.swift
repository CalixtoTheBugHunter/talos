@testable import TalosAdapters
import Testing

/// The pure transform that surfaces a held call's arguments by field name.
/// Unit-tested with plain dictionaries rather than a captured stream: the
/// flattening is a property of Talos's own code, not a claim about any agent's
/// output format — which is what keeps this clear of the real-fixture rule that
/// governs the decode-to-event mapping.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Architecture-The-Orchestration-Boundary
@Suite("Claude Code argument flattening")
struct ClaudeCodeArgumentFlatteningTests {
    @Test("A flat input keeps its string values unchanged")
    func flatInputIsUnchanged() {
        let arguments = ClaudeCodeStreamDecoder.keyedArguments(from: [
            "file_path": "/tmp/note.txt",
            "content": "hello\n"
        ])
        #expect(arguments == ["file_path": "/tmp/note.txt", "content": "hello\n"])
    }

    @Test("A nested object flattens to dotted paths, and a number stringifies")
    func nestedObjectFlattensToDottedPaths() {
        let arguments = ClaudeCodeStreamDecoder.keyedArguments(from: [
            "method": "update_project_item",
            "project_number": 7,
            "item_id": "PVTI_1",
            "updated_field": ["name": "Status", "value": "Done"]
        ])
        #expect(arguments == [
            "method": "update_project_item",
            "project_number": "7",
            "item_id": "PVTI_1",
            "updated_field.name": "Status",
            "updated_field.value": "Done"
        ])
    }

    @Test("An array carries no single field value to name, so it is skipped")
    func arraysAreSkipped() {
        let arguments = ClaudeCodeStreamDecoder.keyedArguments(from: [
            "items": ["PVTI_1", "PVTI_2"],
            "item_id": "PVTI_3"
        ])
        #expect(arguments == ["item_id": "PVTI_3"])
    }
}
