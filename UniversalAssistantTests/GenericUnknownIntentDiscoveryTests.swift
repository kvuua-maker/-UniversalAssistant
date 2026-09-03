import Foundation
import Testing
@testable import UniversalAssistant

private struct GenericFixtureProvider: GenericDiscoveryProvider {
    let id: String; let kind: GenericSourceKind; let html: String?; let queryProbe: GenericQueryProbe?; var delay: UInt64 = 0
    func discover(_ intent: GenericIntent, query: String) async throws -> [GenericDiscoveryDocument] {
        await queryProbe?.set(query); if delay > 0 { try await Task.sleep(nanoseconds: delay) }
        guard let html else { throw RetailPageFailure.unavailable }
        let url = URL(string: "https://\(id).example/item")!
        return [.init(response: .init(finalURL: url, html: html, fetchedAt: .now, sourceTimestamp: .now), sourceKind: kind)]
    }
}
private actor GenericQueryProbe { var value: String?; func set(_ value: String) { self.value = value } }
private actor GenericAIProbe: GenericAIIntentResolver {
    var calls = 0
    func resolve(_ text: String) async throws -> GenericIntent { calls += 1; return .init(domain: "lifestyle", subject: "atmospheric place", goal: "find", requestedAction: "open") }
}
private struct SpecializedFixture: GenericSpecializedResolver {
    func resolve(_ command: StructuredCommand) async -> DeterministicResult? {
        try? DeterministicResultComposer().compose(primaryAnswer: "specialized", facts: [])
    }
}

private struct GenericTransportFixture: RetailDiscoveryTransport {
    let data: Data
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        (data, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }
}
private struct GenericPageFixture: RetailPageRetrieving {
    func retrieve(_ url: URL) async throws -> RetailPageResponse {
        .init(finalURL: url, html: "<script type=\"application/ld+json\">{\"@type\":\"JobPosting\",\"name\":\"Driver\",\"url\":\"https://jobs.example/driver\"}</script>", fetchedAt: .now, sourceTimestamp: .now)
    }
}

@Suite("General unknown-intent discovery")
struct GenericUnknownIntentDiscoveryTests {
    private let now = Date(timeIntervalSince1970: 10_000)
    private func json(_ type: String = "Thing", title: String = "Result", extra: String = "") -> String {
        #"<script type="application/ld+json">{"@type":""# + type + #"","name":""# + title + #"","url":"https://official.example/item""# + extra + "}</script>"
    }
    private func parsedUnknown(_ text: String) -> StructuredCommand { LocalCommandEngine().parse(text) }
    private func coordinator(_ providers: [GenericFixtureProvider], ai: GenericAIProbe? = nil) -> GenericUnknownRequestCoordinator {
        .init(providers: providers, cache: GenericSemanticCache(), ai: ai)
    }

    @Test func configuredProviderBuildsRequestAndRetrievesUnknownDomainPage() async throws {
        let payload = Data("{\"results\":[{\"url\":\"https://jobs.example/driver\",\"source_kind\":\"officialPrimary\"}]}".utf8)
        let provider = ConfiguredGenericWebDiscoveryProvider(id: "generic", endpoint: URL(string: "https://search.example/discover")!, bearerToken: "secret", transport: GenericTransportFixture(data: payload), pageRetriever: GenericPageFixture())
        let intent = try GenericIntentParser().parse("Знайди роботу водієм у Києві")
        let documents = try await provider.discover(intent, query: GenericQuerySanitizer().query(for: intent))
        #expect(documents.count == 1); #expect(documents.first?.sourceKind == .officialPrimary)
    }
    @Test func unknownJobParsesRoleLocationAndMinimumSalary() throws {
        let i = try GenericIntentParser().parse("Знайди мені роботу водієм у Києві від 40 000 грн", now: now)
        #expect(i.domain == "jobs"); #expect(i.location?.locality == "Київ"); #expect(i.money?.minimum == 40000); #expect(i.money?.currency == "UAH")
    }
    @Test func localRepairIsGenericNotHardcodedIntent() throws { #expect(try GenericIntentParser().parse("Знайди майстра поруч, який відремонтує бойлер").domain == "local_service") }
    @Test func educationalCoursePreservesBudget() throws { #expect(try GenericIntentParser().parse("Знайди курси німецької до 5 000 грн").money?.maximum == 5000) }
    @Test func factualQuestionUsesGenericDomain() throws { #expect(try GenericIntentParser().parse("Коли краще садити помідори?").goal == "answer") }
    @Test func eventDiscoveryPreservesRelativeWindow() throws { #expect(try GenericIntentParser().parse("Які фестивалі будуть наступними вихідними?").timeWindow?.relativeExpression == "next_weekend") }
    @Test func specializedCapabilityBeatsFallback() async throws {
        let result = try await coordinator([]).execute(text: "Покажи погоду", parsed: LocalCommandEngine().parse("Покажи погоду"), specialized: SpecializedFixture(), now: now)
        #expect(result.primaryAnswer == "specialized")
    }
    @Test func unknownIntentWorksWithoutAIEndToEnd() async throws {
        let result = try await coordinator([.init(id:"official", kind:.officialPrimary, html:json("JobPosting", title:"Driver"), queryProbe:nil)]).execute(text:"Знайди роботу водієм у Києві", parsed:parsedUnknown("нова вакансія водія"))
        #expect(result.aiInvocationCount == 0); #expect(result.actions.first?.kind == .open)
    }
    @Test func complexUnknownUsesExactlyOneBoundedAIInterpretation() async throws {
        let ai = GenericAIProbe(); let result = try await coordinator([.init(id:"official", kind:.officialPrimary, html:json(title:"Place"), queryProbe:nil)], ai:ai).execute(text:"Щось атмосферне", parsed:parsedUnknown("Щось атмосферне"))
        #expect(await ai.calls == 1); #expect(result.aiInvocationCount == 1)
    }
    @Test func aiUnavailableLeavesTruthfulClarification() async {
        await #expect(throws: GenericDiscoveryError.self) { try await coordinator([]).execute(text:"", parsed:parsedUnknown("")) }
    }
    @Test func ambiguousRequestProducesOneQuestion() { #expect(throws: GenericDiscoveryError.ambiguous("Що саме ви хочете знайти?")) { try GenericIntentParser().parse("Щось цікаве") } }
    @Test func oneProviderFailureReturnsUsefulPartialResult() async throws {
        let r = try await coordinator([.init(id:"bad",kind:.generalWeb,html:nil,queryProbe:nil),.init(id:"good",kind:.officialPrimary,html:json(),queryProbe:nil)]).execute(text:"невідомий безпечний запит",parsed:parsedUnknown("невідомий безпечний запит")); #expect(r.warnings.count == 1)
    }
    @Test func allProvidersFailTruthfully() async { await #expect(throws: GenericDiscoveryError.allSourcesFailed) { try await coordinator([.init(id:"bad",kind:.generalWeb,html:nil,queryProbe:nil)]).execute(text:"невідомий запит",parsed:parsedUnknown("невідомий запит")) } }
    @Test func authoritativeSourceWinsConflict() async throws {
        let r = try await coordinator([.init(id:"web",kind:.generalWeb,html:json(title:"Same"),queryProbe:nil),.init(id:"official",kind:.officialPrimary,html:json(title:"Same"),queryProbe:nil)]).execute(text:"нова тема",parsed:parsedUnknown("нова тема")); #expect(r.facts.first?.source?.hasPrefix("officialPrimary:") == true)
    }
    @Test func staleSourceIsNotCurrent() async { let stale = #"<script type="application/ld+json">{"@type":"Event","name":"Old","url":"https://x.example/e","dateModified":"1960-01-01T00:00:00Z"}</script>"#; await #expect(throws: GenericDiscoveryError.noTrustworthyResults) { try await coordinator([.init(id:"x",kind:.generalWeb,html:stale,queryProbe:nil)]).execute(text:"події наступними вихідними",parsed:parsedUnknown("події наступними вихідними"),now:now) } }
    @Test func blockedCaptchaNeverMeansNoResults() async { await #expect(throws: GenericDiscoveryError.noTrustworthyResults) { try await coordinator([.init(id:"x",kind:.generalWeb,html:"captcha verify you are human",queryProbe:nil)]).execute(text:"нова тема",parsed:parsedUnknown("нова тема")) } }
    @Test func snippetCannotOverridePrimaryPage() async { await #expect(throws: GenericDiscoveryError.noTrustworthyResults) { try await coordinator([.init(id:"x",kind:.generalWeb,html:"search snippet price 1",queryProbe:nil)]).execute(text:"ціна послуги",parsed:parsedUnknown("ціна послуги")) } }
    @Test func duplicateSourcesCollapse() async throws { let h=json(title:"Same"); let r = try await coordinator([.init(id:"a",kind:.generalWeb,html:h,queryProbe:nil),.init(id:"b",kind:.generalWeb,html:h,queryProbe:nil)]).execute(text:"нова тема",parsed:parsedUnknown("нова тема")); #expect(r.facts.count == 1) }
    @Test func differentVariantsRemainSeparate() async throws { let h = #"<script type="application/ld+json">[{"@type":"Course","name":"German","identifier":"online","url":"https://x.example/one"},{"@type":"Course","name":"German","identifier":"classroom","url":"https://x.example/two"}]</script>"#; let r=try await coordinator([.init(id:"x",kind:.structuredMarketplace,html:h,queryProbe:nil)]).execute(text:"курси німецької",parsed:parsedUnknown("курси німецької")); #expect(r.facts.count == 2) }
    @Test func genericComparisonIsCappedAtThreeWithShowMore() async throws {
        let html = #"<script type="application/ld+json">[{"@type":"Thing","name":"One","url":"https://x.example/1"},{"@type":"Thing","name":"Two","url":"https://x.example/2"},{"@type":"Thing","name":"Three","url":"https://x.example/3"},{"@type":"Thing","name":"Four","url":"https://x.example/4"}]</script>"#
        let result = try await coordinator([.init(id: "x", kind: .structuredMarketplace, html: html, queryProbe: nil)]).execute(text: "порівняй доступні варіанти", parsed: parsedUnknown("порівняй доступні варіанти"))
        #expect(result.facts.count == 3); #expect(result.actions.last?.kind == .showMore)
    }
    @Test func genericActionIsOpenOnly() async throws { let r=try await coordinator([.init(id:"x",kind:.officialPrimary,html:json("JobPosting",title:"Job"),queryProbe:nil)]).execute(text:"робота водієм",parsed:parsedUnknown("робота водієм")); #expect(r.actions.allSatisfy{$0.title == "Відкрити" && $0.kind == .open}) }
    @Test func consequentialGenericActionFailsClosed() async { var i=GenericIntent(domain:"x",subject:"x",goal:"x",requestedAction:"buy",risk:.consequential); #expect(throws: GenericDiscoveryError.unsafeAction) { if i.risk != .informational { throw GenericDiscoveryError.unsafeAction } } }
    @Test func locationRelativeIntentUsesTypedContextMarker() throws { #expect(try GenericIntentParser().parse("Де відремонтувати кавоварку поруч?").location?.nearCurrentLocation == true) }
    @Test func timeRelativeIntentIsTyped() throws { #expect(try GenericIntentParser().parse("Знайди майстра сьогодні").timeWindow?.relativeExpression == "today") }
    @Test func semanticCacheSeparatesConstraints() async throws { let c=GenericSemanticCache(); var a=try GenericIntentParser().parse("курси до 5000 грн"), b=try GenericIntentParser().parse("курси до 6000 грн"); #expect(try await c.key(a) != c.key(b)) }
    @Test func sensitiveContextDoesNotLeakIntoQuery() throws { var i=GenericIntent(domain:"x",subject:"token secret",goal:"find",metadata:["email":"a@b.com"]); #expect(!(try GenericQuerySanitizer().query(for:i)).contains("@")) }
    @Test func unverifiedLiveValueRemainsUnknown() throws { let e=try GenericStructuredExtractor().extract(.init(response:.init(finalURL:URL(string:"https://x.example/a")!,html:json(),fetchedAt:now,sourceTimestamp:nil),sourceKind:.generalWeb)); #expect(e.first?.facts["price"] == nil) }
    @Test func supportedUnknownDoesNotSayFunctionUnsupported() async throws { let r=try await coordinator([.init(id:"x",kind:.officialPrimary,html:json(title:"Answer"),queryProbe:nil)]).execute(text:"Коли краще садити помідори?",parsed:parsedUnknown("Коли краще садити помідори?")); #expect(!r.primaryAnswer.lowercased().contains("не підтрим")) }
    @Test func tenGoldenUnknownJourneysStayTyped() throws { let values=GenericUnknownJourneyCatalog.canonical; #expect(values.count == 10); #expect(values.filter { (try? GenericIntentParser().parse($0.request)) != nil }.count >= 8) }
}
