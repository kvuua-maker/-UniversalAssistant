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

    @Test func clipboardWriteDoesNotRequireColonAndPreservesPayload() async throws {
        let command = LocalCommandEngine().parse("Скопіюй в буфер Зустріч завтра о десятій")
        #expect(command.intent == .deviceAction)
        #expect(command.entities["content"] == "Зустріч завтра о десятій")
        var received: SystemQuickAction?
        let executor = ProductionCanonicalCapabilityExecutor(publicDeviceExecute: { action in received = action; return "Скопійовано" }, personalSearchSources: [])
        _ = try await executor.execute(command)
        #expect(received == .copyToClipboard("Зустріч завтра о десятій"))
    }

    @Test func clipboardReadAndVerifiedURLUseUserInitiatedBoundary() async throws {
        let read = LocalCommandEngine().parse("Що зараз у буфері?")
        let reader = ProductionCanonicalCapabilityExecutor(clipboardRead: { .text("Приватний локальний текст") }, personalSearchSources: [])
        guard case let .result(value) = try await reader.execute(read) else { Issue.record("Expected clipboard result"); return }
        #expect(value.primaryAnswer == "Приватний локальний текст")

        let url = try #require(URL(string: "https://www.apple.com/ua/"))
        let open = LocalCommandEngine().parse("Відкрий посилання з буфера")
        let opener = ProductionCanonicalCapabilityExecutor(clipboardRead: { .url(url) }, personalSearchSources: [])
        guard case let .handoff(handoff) = try await opener.execute(open) else { Issue.record("Expected verified URL handoff"); return }
        #expect(handoff.kind == .system)
        #expect(handoff.destination.host == "www.apple.com")
    }

    @Test func copyLastResultUsesFreshTypedContextAndRejectsExpiredContext() async throws {
        let now = Date()
        let current = CurrentContextStore()
        current.replaceAnswer("9716", now: now, lifetime: 60)
        var received: SystemQuickAction?
        let executor = ProductionCanonicalCapabilityExecutor(currentContext: current, publicDeviceExecute: { action in received = action; return "Скопійовано" }, personalSearchSources: [])
        _ = try await executor.execute(LocalCommandEngine().parse("Скопіюй останній результат"))
        #expect(received == .copyToClipboard("9716"))

        let expired = CurrentContextStore()
        expired.replaceAnswer("старе", now: now.addingTimeInterval(-120), lifetime: 1)
        let staleExecutor = ProductionCanonicalCapabilityExecutor(currentContext: expired, publicDeviceExecute: { _ in "unexpected" }, personalSearchSources: [])
        await #expect(throws: CanonicalCapabilityExecutionError.self) {
            _ = try await staleExecutor.execute(LocalCommandEngine().parse("Скопіюй останній результат"))
        }
    }
}
