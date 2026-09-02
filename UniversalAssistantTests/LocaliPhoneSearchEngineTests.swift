import Foundation
import Testing
@testable import UniversalAssistant

private actor SearchConcurrencyProbe {
    var active = 0
    var maximum = 0
    func enter() { active += 1; maximum = max(maximum, active) }
    func leave() { active -= 1 }
}

private struct SearchSourceStub: LocalSearchSource {
    let kind: LocalSearchSourceKind
    let access: LocalSearchAccess
    let values: [LocalSearchResult]
    let probe: SearchConcurrencyProbe?

    func search(_ query: LocalSearchQuery) async -> LocalSearchSourceResponse {
        await probe?.enter()
        try? await Task.sleep(for: .milliseconds(20))
        await probe?.leave()
        return .init(source: kind, access: access, results: access == .permitted || access == .limited ? values : [])
    }
}

@Suite("Local iPhone search") struct LocaliPhoneSearchEngineTests {
    @Test func searchesPermittedSourcesConcurrentlyAndRanksDeterministically() async {
        let probe = SearchConcurrencyProbe()
        let date = Date(timeIntervalSince1970: 100)
        let sources: [any LocalSearchSource] = [
            SearchSourceStub(kind: .calendar, access: .permitted,
                values: [.init(id: "event", source: .calendar, title: "Стоматолог", subtitle: nil, occurredAt: date, exactNameMatch: true, relevance: 80, openReference: "event:event")], probe: probe),
            SearchSourceStub(kind: .notes, access: .permitted,
                values: [.init(id: "note", source: .notes, title: "Нотатка стоматолога", subtitle: nil, occurredAt: date, exactNameMatch: false, relevance: 80, openReference: "note:note")], probe: probe)
        ]
        let report = await LocaliPhoneSearchEngine(sources: sources).search(.init(text: "стоматолог"))
        #expect(await probe.maximum == 2)
        #expect(report.results.map(\.id) == ["event", "note"])
        #expect(report.clearResult?.id == "event")
    }

    @Test func permissionFailureIsTruthfulAndDoesNotInventResults() async {
        let denied = SearchSourceStub(kind: .photos, access: .denied,
            values: [.init(id: "fake", source: .photos, title: "Фото", subtitle: nil, occurredAt: nil, exactNameMatch: true, relevance: 100, openReference: "photo:fake")], probe: nil)
        let report = await LocaliPhoneSearchEngine(sources: [denied]).search(.init(text: "фото"))
        #expect(report.results.isEmpty)
        #expect(report.accessBySource[.photos] == .denied)
    }

    @Test func shortlistIsBoundedAndDateConstraintIsHard() async {
        let values = (0..<20).map { index in
            LocalSearchResult(id: "\(index)", source: .actionHistory, title: "Запис", subtitle: nil,
                occurredAt: Date(timeIntervalSince1970: TimeInterval(index)), exactNameMatch: false,
                relevance: index, openReference: "history:\(index)")
        }
        let source = SearchSourceStub(kind: .actionHistory, access: .permitted, values: values, probe: nil)
        let report = await LocaliPhoneSearchEngine(sources: [source]).search(
            .init(text: "запис", dateRange: Date(timeIntervalSince1970: 5)..<Date(timeIntervalSince1970: 10), limit: 3)
        )
        #expect(report.results.map(\.id) == ["9", "8", "7"])
    }

    @Test func permissionChangeRemovesStaleIndexedReferences() async {
        let index = PrivacySafeLocalSearchIndex()
        await index.upsert([.init(id: "asset", source: .photos, title: "Берлін", subtitle: nil,
            occurredAt: nil, exactNameMatch: true, relevance: 1, openReference: "photo:asset")])
        #expect(await index.search("Берлін", permittedSources: [.photos]).count == 1)
        await index.remove(source: .photos)
        #expect(await index.search("Берлін", permittedSources: [.photos]).isEmpty)
    }
}
