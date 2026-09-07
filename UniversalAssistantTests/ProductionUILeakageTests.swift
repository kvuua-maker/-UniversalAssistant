import Foundation
import Testing

@Suite("Production UI leakage guard")
struct ProductionUILeakageTests {
    @Test func resultRendererDoesNotUseNarrationOrPlannerIdentifiersAsVisibleText() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: root.appending(path: "UniversalAssistant/App/CompactResultCard.swift"), encoding: .utf8)
        for visibleExpression in [
            "Text(\"request_recognized\"",
            "Text(\"web_search_ready\"",
            "Text(\"system_handoff_ready\"",
            "Text(\"typedCommand\"",
            "Text(\"deterministicCompose\"",
            "Text(\"apple-mapkit\"",
            "Text(\"apple-weatherkit\")",
        ] {
            #expect(!source.contains(visibleExpression))
        }
        #expect(source.contains("!source.hasPrefix(\"apple-\")"))
        #expect(source.contains("[\"typedCommand\", \"deterministicCompose\", \"voice\", \"command\"]"))
    }
}
