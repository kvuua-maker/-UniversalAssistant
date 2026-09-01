import Foundation
import Testing
@testable import UniversalAssistant

private struct TicketProviderFixture: TicketProvider {
    let providerID: String
    let offers: [TicketOffer]
    var delay: Duration = .zero
    var fails = false

    func search(_ request: TicketSearchRequest) async throws -> [TicketOffer] {
        if delay > .zero { try await Task.sleep(for: delay) }
        if fails { throw FixtureFailure.failed }
        return offers
    }
    private enum FixtureFailure: Error { case failed }
}

private func providerTicket(_ id: String, now: Date, provider: String) -> TicketOffer {
    .init(id: id, providerID: provider, mode: .rail,
          segments: [.init(origin: "Kyiv", destination: "Lviv",
                           departure: now.addingTimeInterval(3_600), arrival: now.addingTimeInterval(7_200))],
          fare: .init(amount: 1_000, currency: "UAH"),
          inventory: .verifiedAvailable(source: provider, observedAt: now), fareObservedAt: now,
          exactPurchaseURL: URL(string: "https://tickets.example/\(id)")!)
}

@Suite("Bounded provider degradation") struct ProviderFanoutEngineTests {
    @Test func ticketProviderFailureReturnsRankedPartialResults() async throws {
        let now = Date()
        let response = try await TicketProviderCoordinator(providers: [
            TicketProviderFixture(providerID: "good", offers: [providerTicket("valid", now: now, provider: "good")]),
            TicketProviderFixture(providerID: "broken", offers: [], fails: true)
        ]).search(.init(requiresVerifiedInventory: true), now: now)
        #expect(response.offers.map(\.id) == ["valid"])
        #expect(response.coverage == .partial)
        #expect(response.failures == [.init(providerID: "broken", reason: "provider_error")])
    }

    @Test func timeoutIsBoundedAndDoesNotDiscardFastProvider() async throws {
        let now = Date()
        let response = try await TicketProviderCoordinator(
            providers: [
                TicketProviderFixture(providerID: "fast", offers: [providerTicket("fast", now: now, provider: "fast")]),
                TicketProviderFixture(providerID: "slow", offers: [], delay: .seconds(2))
            ], timeout: .milliseconds(20)
        ).search(.init(), now: now)
        #expect(response.offers.map(\.id) == ["fast"])
        #expect(response.failures == [.init(providerID: "slow", reason: "timeout")])
    }

    @Test func allProviderFailuresProduceFailedCoverage() async throws {
        let response = try await TicketProviderCoordinator(providers: [
            TicketProviderFixture(providerID: "broken", offers: [], fails: true)
        ]).search(.init())
        #expect(response.offers.isEmpty)
        #expect(response.coverage == .failed)
    }

    @Test func duplicateOrUnboundedProviderSetsAreRejected() async throws {
        let operation = ProviderOperation<Int>(providerID: "same") { [1] }
        await #expect(throws: ProviderFanoutError.invalidConfiguration) {
            try await ProviderFanoutEngine<Int>(maximumProviders: 1).execute([operation, operation])
        }
    }
}
