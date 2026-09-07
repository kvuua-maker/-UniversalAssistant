import Foundation
import Testing
@testable import UniversalAssistant

@MainActor
struct ProductionContextContinuationTests {
    private let now = Date(timeIntervalSince1970: 10_000)
    private func result(_ ids: [String]) throws -> DeterministicResult {
        try DeterministicResultComposer().compose(primaryAnswer: "Found", facts: ids.enumerated().map { .init(id: $0.element, label: $0.element, value: "value", state: .verified, source: "local", observedAt: now, priority: 100 - $0.offset) }, actions: ids.map { .init(id: $0, title: "Open", kind: .open, destination: URL(string: "https://example.com/\($0)")!) })
    }
    @Test func storeReplaceExpireAndResetAreBounded() throws {
        let store = CurrentContextStore(); store.replaceResults(try result(["one", "two"]), now: now, lifetime: 10)
        #expect(store.context.resultEntities.map(\.id) == ["one", "two"])
        store.replaceResults(try result(["new"]), now: now.addingTimeInterval(1), lifetime: 10)
        #expect(store.context.resultEntities.map(\.id) == ["new"])
        _ = store.select(LocalCommandEngine().parse("Відкрий перший"), now: now.addingTimeInterval(12))
        #expect(store.context.resultEntities.isEmpty)
        store.replaceResults(try result(["again"]), now: now); store.reset(); #expect(store.context.resultEntities.isEmpty)
    }
    @Test func ordinalSelectionUsesExactIDAndPreventsReplay() throws {
        let store = CurrentContextStore(); store.replaceResults(try result(["one", "two"]), now: now)
        let selected = store.select(LocalCommandEngine().parse("Відкрий другий"), now: now)
        #expect(selected?.id == "two")
        #expect(store.consumeSelectedAction(now: now)?.absoluteString == "https://example.com/two")
        #expect(store.consumeSelectedAction(now: now) == nil)
    }
    @Test func typedPhotoContextSelectsReplacesAndExpiresWithoutStaleReuse() throws {
        let store = CurrentContextStore()
        let first = try DeterministicResultComposer().compose(primaryAnswer: "Photo", facts: [.init(id: "photos:asset-a", label: "A", value: "image", state: .verified, source: "Photos", observedAt: now, priority: 100)], actions: [.init(id: "photos:asset-a", title: "Open", kind: .showPhoto, destination: nil)])
        store.replacePhotoResults(first, now: now, lifetime: 10)
        #expect(store.context.resultEntities.first?.kind == .photo)
        #expect(store.freshPhotoAssetIdentifier(at: now) == "asset-a")
        let second = try DeterministicResultComposer().compose(primaryAnswer: "Photo", facts: [.init(id: "photos:asset-b", label: "B", value: "image", state: .verified, source: "Photos", observedAt: now.addingTimeInterval(1), priority: 100)], actions: [.init(id: "photos:asset-b", title: "Open", kind: .showPhoto, destination: nil)])
        store.replacePhotoResults(second, now: now.addingTimeInterval(1), lifetime: 10)
        #expect(store.freshPhotoAssetIdentifier(at: now.addingTimeInterval(1)) == "asset-b")
        #expect(store.freshPhotoAssetIdentifier(at: now.addingTimeInterval(12)) == nil)
    }

    @Test func productionExecutorShowsAndOpensStoredPersonalResult() async throws {
        let store = CurrentContextStore()
        let contact = ContactCandidate(identifier: "contact-1", displayName: "Mama", phoneNumbers: ["+380501234567"])
        let executor = ProductionCanonicalCapabilityExecutor(contacts: ContextContactResolverFixture(.resolved(contact)), currentContext: store, personalSearchSources: [])
        let search = StructuredCommand(originalText: "Знайди контакт мама", normalizedText: "знайди контакт мама", language: .uk, intent: .contactLookup, entities: ["contact":"мама"])
        _ = try await executor.execute(search)
        let show = StructuredCommand(originalText: "Покажи перший", normalizedText: "покажи перший", language: .uk, intent: .contextualSelection, constraints: .init(ordinal: 1))
        guard case let .result(value) = try await executor.execute(show) else { Issue.record("Expected result"); return }
        #expect(value.facts.first?.id == "phone-0")
        let open = StructuredCommand(originalText: "Відкрий перший", normalizedText: "відкрий перший", language: .uk, intent: .open, constraints: .init(ordinal: 1))
        guard case let .handoff(value) = try await executor.execute(open) else { Issue.record("Expected handoff"); return }
        #expect(value.destination.absoluteString == "tel:+380501234567")
        await #expect(throws: CanonicalCapabilityExecutionError.unavailable("context_action_unavailable_or_replayed")) { try await executor.execute(open) }
    }

    @Test func typedTranslationAndSharedContentReplaceExpireAndReset() {
        let store = CurrentContextStore()
        store.replaceTranslation(sourceText: "Original", sourceLanguage: "en", now: now, lifetime: 10)
        #expect(store.freshTranslation(at: now)?.sourceText == "Original")
        store.replaceTranslation(sourceText: "New", sourceLanguage: "uk", now: now.addingTimeInterval(1), lifetime: 10)
        #expect(store.freshTranslation(at: now.addingTimeInterval(1))?.sourceText == "New")
        store.replaceShared(kind: .url, value: "https://example.com", observedAt: now, lifetime: 10)
        #expect(store.freshShared(at: now)?.kind == .url)
        store.replaceShared(kind: .image, value: "payload", observedAt: now.addingTimeInterval(1), lifetime: 10)
        #expect(store.freshShared(at: now.addingTimeInterval(1))?.kind == .image)
        #expect(store.freshShared(at: now.addingTimeInterval(12)) == nil)
        store.reset()
        #expect(store.freshTranslation(at: now.addingTimeInterval(1)) == nil)
    }
}

private actor ContextContactResolverFixture: ContactResolving {
    let resolution: ContactResolution
    init(_ resolution: ContactResolution) { self.resolution = resolution }
    func requestAccessIfNeeded() async throws {}
    func resolve(name: String) async throws -> ContactResolution { resolution }
    func resolve(exactIdentifier identifier: String) async throws -> ContactResolution { resolution }
}
