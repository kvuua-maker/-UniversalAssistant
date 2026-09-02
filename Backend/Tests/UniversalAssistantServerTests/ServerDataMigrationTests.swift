import Foundation
import Testing
@testable import UniversalAssistantServer

@Suite("Staging server data migration")
struct ServerDataMigrationTests {
    @Test func sequentialMigrationPersistsAndSurvivesRestart() async throws {
        let url = stateURL()
        let store = FileBackedServerSchemaStore(stateURL: url)
        try await store.seed(.init(version: 1, records: ["partner": ["name": "A"]]))
        let runner = StagingServerMigrationRunner(environment: .staging, store: store)
        let result = try await runner.migrate(to: 2, using: [
            .init(fromVersion: 1, toVersion: 2, transform: { state in
                var value = state
                value.records["partner"]?["status"] = "ACTIVE"
                return value
            }, validate: { $0.records["partner"]?["status"] == "ACTIVE" })
        ])
        #expect(result.version == 2)
        #expect(try await FileBackedServerSchemaStore(stateURL: url).load() == result)
    }

    @Test func failedValidationRestoresExactPreMigrationState() async throws {
        let url = stateURL()
        let original = ServerSchemaState(version: 1, records: ["ledger": ["currency": "EUR"]])
        let store = FileBackedServerSchemaStore(stateURL: url)
        try await store.seed(original)
        let runner = StagingServerMigrationRunner(environment: .staging, store: store)
        await #expect(throws: ServerMigrationError.validationFailed) {
            try await runner.migrate(to: 2, using: [
                .init(fromVersion: 1, toVersion: 2, transform: { state in
                    var value = state
                    value.records["ledger"]?["currency"] = ""
                    return value
                }, validate: { $0.records["ledger"]?["currency"]?.isEmpty == false })
            ])
        }
        #expect(try await store.load() == original)
    }

    @Test func productionCannotBypassRequiredStagingExecution() async throws {
        let store = FileBackedServerSchemaStore(stateURL: stateURL())
        try await store.seed(.init(version: 1, records: [:]))
        let runner = StagingServerMigrationRunner(environment: .production, store: store)
        await #expect(throws: ServerMigrationError.stagingRequired) {
            try await runner.migrate(to: 1, using: [])
        }
    }

    private func stateURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("ua-server-migration-\(UUID().uuidString)/state.json")
    }
}
