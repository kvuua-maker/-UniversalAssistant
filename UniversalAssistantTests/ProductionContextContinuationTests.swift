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

    @Test func productionExecutorPresentsTheOfficialContactCardWithoutCreatingAStaleCustomResult() async throws {
        let store = CurrentContextStore()
        let contact = ContactCandidate(identifier: "contact-1", displayName: "Mama", phoneNumbers: ["+380501234567"])
        let executor = ProductionCanonicalCapabilityExecutor(contacts: ContextContactResolverFixture(.resolved(contact)), currentContext: store, personalSearchSources: [])
        let search = StructuredCommand(originalText: "Знайди контакт мама", normalizedText: "знайди контакт мама", language: .uk, intent: .contactLookup, entities: ["contact":"мама"])
        #expect(try await executor.execute(search) == .presentation(.contactCard(identifier: "contact-1")))
        let show = StructuredCommand(originalText: "Покажи перший", normalizedText: "покажи перший", language: .uk, intent: .contextualSelection, constraints: .init(ordinal: 1))
        await #expect(throws: CanonicalCapabilityExecutionError.missingParameter("active_result_context")) {
            try await executor.execute(show)
        }
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

private struct ContextPhotoLibraryFixture: PhotoLibrarySearching {
    let assets: [PhotoAssetReference]
    func authorization() -> LocalSearchAccess { .permitted }
    func requestAuthorization() async -> LocalSearchAccess { .permitted }
    func search(_ criteria: PhotoSearchCriteria, limit: Int) async -> [PhotoAssetReference] {
        Array(assets.prefix(limit))
    }
}

@MainActor
struct ProductionPhotoActionCompositionTests {
    @Test func latestShareVariantSelectsExactlyOneAssetAndOpensPublicPhotoPresentation() async throws {
        let newest = PhotoAssetReference(localIdentifier: "asset-new", creationDate: .now, coordinate: nil, album: nil)
        let executor = ProductionCanonicalCapabilityExecutor(
            photos: ContextPhotoLibraryFixture(assets: [newest]),
            personalSearchSources: []
        )
        let command = LocalCommandEngine().parse("Надішли щойно зроблену світлину")
        #expect(command.intent == .photoSearch)
        #expect(command.entities["requested_action"] == "share")
        #expect(try await executor.execute(command) == .presentation(.photoShare("asset-new")))
    }

    @Test func genericOpenAndOrdinalRecentPhotoUseMetadataSelectionWithoutSemanticClassification() async throws {
        let newest = PhotoAssetReference(localIdentifier: "asset-new", creationDate: .now, coordinate: nil, album: nil)
        let previous = PhotoAssetReference(localIdentifier: "asset-previous", creationDate: .now.addingTimeInterval(-10), coordinate: nil, album: nil)
        let executor = ProductionCanonicalCapabilityExecutor(
            photos: ContextPhotoLibraryFixture(assets: [newest, previous]),
            personalSearchSources: []
        )
        let generic = LocalCommandEngine().parse("Покажи мою фотографію")
        #expect(generic.entities["query"] == "recent")
        #expect(try await executor.execute(generic) == .result(try DeterministicResultComposer().compose(
            primaryAnswer: "Найновіше фото",
            facts: [.init(id: "photos:asset-new", label: "Фото", value: newest.creationDate?.formatted(), state: .verified, source: "Photos", observedAt: newest.creationDate, priority: 100)],
            actions: [.init(id: "photos:asset-new", title: "Відкрити", kind: .showPhoto, destination: nil)]
        )))
        let penultimate = LocalCommandEngine().parse("Покажи передостанню світлину")
        #expect(penultimate.constraints.ordinal == 2)
        guard case let .result(result) = try await executor.execute(penultimate) else { Issue.record("Expected ordinal photo result"); return }
        #expect(result.facts.first?.id == "photos:asset-previous")
    }

    @Test func naturalPhotoOCRCarriesTypedAutomaticAction() async throws {
        let asset = PhotoAssetReference(localIdentifier: "receipt", creationDate: .now, coordinate: nil, album: nil)
        let executor = ProductionCanonicalCapabilityExecutor(photos: ContextPhotoLibraryFixture(assets: [asset]), personalSearchSources: [])
        let command = LocalCommandEngine().parse("Прочитай текст на найсвіжішій світлині")
        #expect(command.entities["requested_action"] == "ocr")
        #expect(try await executor.execute(command) == .presentation(.photoOCR("receipt")))
    }

    @Test func demonstrativePhotoOCRUsesTypedSharedContextRole() {
        for input in ["Прочитай вміст на цьому знімку", "Які слова написані на цій світлині?", "Що написано на цій фотографії?"] {
            let result = CanonicalSemanticFrameAnalyzer().analyze(original: input, normalized: input.lowercased())
            #expect(result.frame.contextReference == .sharedContent)
            #expect(result.frame.action == .recognize)
            #expect(result.intent == .photoSearch)
        }
    }
}
