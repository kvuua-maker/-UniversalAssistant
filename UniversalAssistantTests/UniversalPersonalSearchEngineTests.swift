import Foundation
import Testing
@testable import UniversalAssistant

private actor PersonalSearchProbe { var active = 0; var maxActive = 0; func enter() { active += 1; maxActive = max(maxActive, active) }; func leave() { active -= 1 } }
private struct PersonalSourceStub: PersonalSearchSource {
    let id: PersonalSearchSourceID; let values: [PersonalSearchResult]; let complete: Bool; let probe: PersonalSearchProbe?
    func search(query: String, limit: Int) async -> PersonalSearchSourceResponse {
        await probe?.enter(); try? await Task.sleep(for: .milliseconds(20)); await probe?.leave()
        return .init(source: id, results: Array(values.prefix(limit)), isComplete: complete, unavailableReason: complete ? nil : "provider_timeout")
    }
}
private func personal(_ id: String, source: PersonalSearchSourceID, relevance: Int = 50, exact: Bool = false) -> PersonalSearchResult {
    .init(id: id, title: id, subtitle: nil, source: source, sourceObjectID: id, openReference: "open:\(id)", freshness: source.isLocal ? .local : .live(.now), relevance: relevance, exactMatch: exact)
}
private extension PersonalSearchSourceID { var isLocal: Bool { if case .local = self { true } else { false } } }

@Suite("Universal personal search") struct UniversalPersonalSearchEngineTests {
    @Test func dentistRecordRoutesPlausibleLocalSourcesInParallel() async {
        let probe = PersonalSearchProbe()
        let calendar: PersonalSearchSourceID = .local(.calendar), notes: PersonalSearchSourceID = .local(.notes), photos: PersonalSearchSourceID = .local(.photos)
        let engine = UniversalPersonalSearchEngine(sources: [
            PersonalSourceStub(id: calendar, values: [personal("event", source: calendar, relevance: 80, exact: true)], complete: true, probe: probe),
            PersonalSourceStub(id: notes, values: [personal("note", source: notes)], complete: true, probe: probe),
            PersonalSourceStub(id: photos, values: [personal("photo", source: photos)], complete: true, probe: probe)])
        let report = await engine.search("Знайди запис стоматолога", requestsImmediateOpen: true)
        #expect(await probe.maxActive == 2)
        #expect(report.searchedSources == [calendar, notes])
        guard case let .exactOpen(result) = report.presentation else { Issue.record("expected exact result"); return }
        #expect(result.sourceObjectID == "event")
    }

    @Test func documentSearchIncludesFilesAndConnectedEmailWithProvenance() async {
        let files: PersonalSearchSourceID = .local(.files), gmail: PersonalSearchSourceID = .connectedEmail("gmail")
        let engine = UniversalPersonalSearchEngine(sources: [
            PersonalSourceStub(id: files, values: [personal("contract-file", source: files)], complete: true, probe: nil),
            PersonalSourceStub(id: gmail, values: [personal("contract-mail", source: gmail, relevance: 60)], complete: true, probe: nil)])
        let report = await engine.search("Знайди договір")
        #expect(report.searchedSources == [files, gmail])
        guard case let .shortlist(results) = report.presentation else { Issue.record("expected shortlist"); return }
        #expect(results.map(\.sourceObjectID) == ["contract-mail", "contract-file"])
    }

    @Test func remoteFailureReturnsTruthfulLocalPartialResult() async {
        let files: PersonalSearchSourceID = .local(.files), gmail: PersonalSearchSourceID = .connectedEmail("gmail")
        let engine = UniversalPersonalSearchEngine(sources: [
            PersonalSourceStub(id: files, values: [personal("contract", source: files)], complete: true, probe: nil),
            PersonalSourceStub(id: gmail, values: [], complete: false, probe: nil)])
        let report = await engine.search("document")
        #expect(report.isPartial)
        #expect(report.failedSources[gmail] == "provider_timeout")
        #expect(report.presentation != .noResult)
    }

    @Test func ambiguousResultsAreCappedAtThreeAndNeverAutoOpened() async {
        let notes: PersonalSearchSourceID = .local(.notes)
        let values = (0..<8).map { personal("n\($0)", source: notes, relevance: 50) }
        let report = await UniversalPersonalSearchEngine(sources: [PersonalSourceStub(id: notes, values: values, complete: true, probe: nil)]).search("notes", requestsImmediateOpen: true)
        guard case let .shortlist(results) = report.presentation else { Issue.record("expected shortlist"); return }
        #expect(results.count == 3)
    }
}
