import Foundation
import Testing
@testable import UniversalAssistant

private struct ParcelFake: ParcelDeliveryProvider {
    let carrier: ParcelCarrier
    let result: Result<ParcelTrackingResult, Error>
    func track(_ number: String) async throws -> ParcelTrackingResult { try result.get() }
    func branches(near latitude: Double, longitude: Double) async throws -> [ParcelBranch] { [] }
}

private actor ParcelTransportRecorder: ParcelHTTPTransport {
    private let responseData: Data
    private let responseStatus: Int
    private(set) var requests: [URLRequest] = []

    init(json: String, status: Int = 200) {
        responseData = Data(json.utf8); responseStatus = status
    }
    func data(for request: URLRequest) async throws -> (Data, Int) {
        requests.append(request); return (responseData, responseStatus)
    }
    func lastRequest() -> URLRequest? { requests.last }
}

@Suite("Parcel delivery")
struct ParcelDeliveryEngineTests {
    @Test func providerFailureReturnsTruthfulPartialResult() async throws {
        let now = Date()
        let value = ParcelTrackingResult(carrier: .novaPoshta, trackingNumber: "20400000000000",
            status: "At branch", estimatedDelivery: nil, knowledge: .confirmedEvent,
            events: [], observedAt: now, sourceReference: "nova:event-1")
        let engine = ParcelDeliveryEngine(providers: [
            ParcelFake(carrier: .novaPoshta, result: .success(value)),
            ParcelFake(carrier: .ukrposhta, result: .failure(ParcelDeliveryError.noVerifiedResult))
        ])
        let report = try await engine.track(number: "20400000000000")
        #expect(report.results == [value])
        #expect(report.isPartial)
        #expect(report.failures[.ukrposhta] != nil)
    }

    @Test func invalidTrackingNumberNeverCallsProviders() async {
        let engine = ParcelDeliveryEngine(providers: [])
        await #expect(throws: ParcelDeliveryError.invalidTrackingNumber) {
            try await engine.track(number: "../secret")
        }
    }

    @Test func branchRouteUsesExactVerifiedCoordinates() throws {
        let branch = ParcelBranch(id: "1", carrier: .meest, name: "Locker", latitude: 50.45,
                                  longitude: 30.52, sourceReference: "meest:point-1")
        let url = try #require(ParcelDeliveryEngine(providers: []).navigationURL(for: branch))
        #expect(url.absoluteString.contains("50.45,30.52"))
    }

    @Test func novaPoshtaAdapterSendsExactContractAndParsesConfirmedStatus() async throws {
        let transport = ParcelTransportRecorder(json: #"{"success":true,"data":[{"Status":"At branch","RefEW":"event-1"}]}"#)
        let provider = try NovaPoshtaParcelProvider(apiKey: "secret-key", transport: transport)
        let result = try await provider.track("20400000000000")
        let request = try #require(await transport.lastRequest())
        #expect(request.httpMethod == "POST")
        #expect(request.url?.absoluteString == "https://api.novaposhta.ua/v2.0/json/")
        let body = try #require(request.httpBody)
        let object = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(object["apiKey"] as? String == "secret-key")
        #expect(object["modelName"] as? String == "TrackingDocument")
        #expect(object["calledMethod"] as? String == "getStatusDocuments")
        let properties = try #require(object["methodProperties"] as? [String: Any])
        let documents = try #require(properties["Documents"] as? [[String: String]])
        #expect(documents.first?["DocumentNumber"] == "20400000000000")
        #expect(result.status == "At branch")
        #expect(result.knowledge == .confirmedEvent)
        #expect(result.sourceReference == "novaPoshta:event-1")
    }

    @Test func officialAdapterUsesBearerQueryAndParsesNestedProviderResponse() async throws {
        let transport = ParcelTransportRecorder(json: #"{"statuses":[{"statusName":"Delivered","eventId":"evt-7"}]}"#)
        let provider = try ParcelProviderFactory(transport: transport).meest(accessToken: "oauth-token")
        let result = try await provider.track("CV123456789UA")
        let request = try #require(await transport.lastRequest())
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer oauth-token")
        #expect(URLComponents(url: try #require(request.url), resolvingAgainstBaseURL: false)?
            .queryItems?.contains(.init(name: "trackingNumber", value: "CV123456789UA")) == true)
        #expect(result.carrier == .meest)
        #expect(result.status == "Delivered")
        #expect(result.sourceReference == "meest:evt-7")
    }

    @Test func officialBranchResponseRequiresVerifiedCoordinates() async throws {
        let transport = ParcelTransportRecorder(json: #"{"items":[{"id":"p1","name":"Locker","latitude":"50.45","longitude":"30.52"},{"id":"bad","name":"Missing coordinate"}]}"#)
        let provider = try ParcelProviderFactory(transport: transport).ukrposhta(bearerToken: "token")
        let branches = try await provider.branches(near: 50.4, longitude: 30.5)
        #expect(branches.count == 1)
        #expect(branches.first?.sourceReference == "ukrposhta:p1")
    }

    @Test func adapterMapsAuthenticationAndRateLimitWithoutFakeResult() async throws {
        let unauthorized = ParcelTransportRecorder(json: "{}", status: 401)
        let limited = ParcelTransportRecorder(json: "{}", status: 429)
        let a = OfficialParcelHTTPProvider(carrier: .other,
            trackingEndpoint: URL(string: "https://provider.example/track")!,
            branchesEndpoint: URL(string: "https://provider.example/branches")!,
            authorizationHeader: nil, transport: unauthorized)
        let b = OfficialParcelHTTPProvider(carrier: .other,
            trackingEndpoint: URL(string: "https://provider.example/track")!,
            branchesEndpoint: URL(string: "https://provider.example/branches")!,
            authorizationHeader: nil, transport: limited)
        await #expect(throws: ParcelAdapterError.unauthorized) { try await a.track("12345") }
        await #expect(throws: ParcelAdapterError.rateLimited) { try await b.track("12345") }
    }

    @Test func credentialFactoriesRejectBlankSecrets() throws {
        let factory = ParcelProviderFactory(transport: ParcelTransportRecorder(json: "{}"))
        #expect(throws: ParcelAdapterError.missingCredential) { try factory.novaPoshta(apiKey: "  ") }
        #expect(throws: ParcelAdapterError.missingCredential) { try factory.ukrposhta(bearerToken: "") }
        #expect(throws: ParcelAdapterError.missingCredential) { try factory.meest(accessToken: "\n") }
    }

    @Test func watchPlannerExpiresAndOnlyRecognizesMatchingChangedProviderEvidence() throws {
        let now = Date(), planner = ParcelWatchPlanner()
        let watch = try planner.create(carrier: .novaPoshta, trackingNumber: "20400000000000", now: now)
        #expect(watch.expiresAt == now.addingTimeInterval(30 * 24 * 3_600))
        let first = ParcelTrackingResult(carrier: .novaPoshta, trackingNumber: watch.trackingNumber,
            status: "At branch", estimatedDelivery: nil, knowledge: .confirmedEvent, events: [],
            observedAt: now, sourceReference: "novaPoshta:event-1")
        #expect(planner.changed(watch, result: first, now: now))
        let seen = ParcelWatch(id: watch.id, carrier: watch.carrier, trackingNumber: watch.trackingNumber,
            lastSourceReference: first.sourceReference, expiresAt: watch.expiresAt)
        #expect(!planner.changed(seen, result: first, now: now))
        #expect(!planner.changed(watch, result: first, now: watch.expiresAt))
    }
}
