import Foundation
import Testing

@Suite("Architecture decision record coverage")
struct ArchitectureDecisionRecordTests {
    @Test func consequentialDecisionsHaveVersionedCompleteRecords() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let directory = root.appendingPathComponent("ADR")
        let files = try FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil
        ).filter { $0.pathExtension == "md" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
        #expect(files.count >= 6)
        let records = try files.map { try String(contentsOf: $0, encoding: .utf8) }
        for record in records {
            for field in ["- Date:", "- Version:", "- Context:", "- Decision:",
                          "- Alternatives considered:", "- Consequences:"] {
                #expect(record.contains(field))
            }
        }
        let combined = records.joined(separator: "\n").lowercased()
        for decision in ["local persistence", "backend", "authentication", "sync",
                         "durable queue", "notifications", "api contracts", "versioning"] {
            #expect(combined.contains(decision))
        }
    }
}
