import Foundation
import Testing
@testable import UniversalAssistant

@MainActor
@Suite("Notes and clipboard production boundary")
struct NotesClipboardProductionTests {
    @Test func noteSynonymsConvergeOnPublicShareHandoffWithoutWeb() async throws {
        let executor = ProductionCanonicalCapabilityExecutor(personalSearchSources: [])
        for input in ["Створи нотатку: купити молоко", "Створи нову нотатку: купити молоко", "Создай заметку: купить молоко"] {
            let command = LocalCommandEngine().parse(input)
            #expect(command.intent == .noteCreate)
            guard case let .presentation(.share(value)) = try await executor.execute(command) else {
                Issue.record("Expected public share-sheet handoff"); continue
            }
            #expect(!value.hasPrefix(":"))
            #expect(value.localizedCaseInsensitiveContains("молоко"))
        }
    }

    @Test func clipboardNaturalInputExecutesTypedLocalPasteboardAction() async throws {
        let command = LocalCommandEngine().parse("Скопіюй у буфер: зустріч завтра о десятій")
        #expect(command.intent == .deviceAction)
        var received: SystemQuickAction?
        let executor = ProductionCanonicalCapabilityExecutor(publicDeviceExecute: { action in
            received = action
            return "Скопійовано"
        }, personalSearchSources: [])
        guard case let .result(result) = try await executor.execute(command) else {
            Issue.record("Expected local deterministic result"); return
        }
        #expect(received == .copyToClipboard("зустріч завтра о десятій"))
        #expect(result.primaryAnswer == "Скопійовано")
    }
}
