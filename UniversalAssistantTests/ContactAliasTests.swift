import Foundation
import Testing
@testable import UniversalAssistant

private actor MemoryAliasPersistence: ContactAliasPersisting {
    var aliases: [ContactAlias] = []
    func load() -> [ContactAlias] { aliases }
    func save(_ aliases: [ContactAlias]) { self.aliases = aliases }
}

struct ContactAliasTests {
    @Test func confirmedMultilingualAliasMapsOnlyToExactIdentifier() async throws {
        let persistence = MemoryAliasPersistence()
        let directory = ContactAliasDirectory(persistence: persistence)
        try await directory.confirm(alias: "  МА́МА ", forExactContactIdentifier: "contact-42")
        #expect(await directory.exactIdentifier(for: "мама") == "contact-42")
        #expect(await persistence.aliases.count == 1)
    }

    @Test func replacingAliasUpdatesExactTargetWithoutDuplicates() async throws {
        let persistence = MemoryAliasPersistence()
        let directory = ContactAliasDirectory(persistence: persistence)
        try await directory.confirm(alias: "лікар", forExactContactIdentifier: "old")
        try await directory.confirm(alias: "Лікар", forExactContactIdentifier: "new")
        #expect(await directory.exactIdentifier(for: "лікар") == "new")
        #expect(await persistence.aliases.count == 1)
    }

    @Test func invalidMappingIsRejected() async {
        let directory = ContactAliasDirectory(persistence: MemoryAliasPersistence())
        await #expect(throws: ContactAliasError.invalidAlias) {
            try await directory.confirm(alias: "  ", forExactContactIdentifier: "contact")
        }
        await #expect(throws: ContactAliasError.invalidContactIdentifier) {
            try await directory.confirm(alias: "мама", forExactContactIdentifier: " ")
        }
    }

    @Test func aliasesRestoreLocally() async throws {
        let persistence = MemoryAliasPersistence()
        await persistence.save([.init(normalizedAlias: "тато", contactIdentifier: "7", confirmedAt: .now)])
        let directory = ContactAliasDirectory(persistence: persistence)
        try await directory.restore()
        #expect(await directory.exactIdentifier(for: "ТАТО") == "7")
    }
}
