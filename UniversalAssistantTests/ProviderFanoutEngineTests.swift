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
    private actor CancellationProbe {
        private(set) var observed = false
        func mark() { observed = true }
    }

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

    @Test func providerThatNeverRespondsIsBoundedByTimeout() async throws {
        let operation = ProviderOperation<Int>(providerID: "never") {
            try await Task.sleep(for: .seconds(60))
            return [1]
        }
        let response = try await ProviderFanoutEngine<Int>(timeout: .milliseconds(15)).execute([operation])
        #expect(response.coverage == .failed)
        #expect(response.failures == [.init(providerID: "never", reason: "timeout")])
    }

    @Test func lateProviderIsCancelledAndCannotLeakAResult() async throws {
        let probe = CancellationProbe()
        let operation = ProviderOperation<Int>(providerID: "late") {
            do {
                try await Task.sleep(for: .seconds(60))
                return [99]
            } catch is CancellationError {
                await probe.mark()
                throw CancellationError()
            }
        }
        let response = try await ProviderFanoutEngine<Int>(timeout: .milliseconds(15)).execute([operation])
        #expect(response.values.isEmpty)
        #expect(response.failures == [.init(providerID: "late", reason: "timeout")])
        #expect(await probe.observed)
    }

    @Test func simultaneousBackendAndNetworkFailuresRemainIsolated() async throws {
        enum Outage: Error { case backendDown, networkLost }
        let response = try await ProviderFanoutEngine<Int>().execute([
            .init(providerID: "backend") { throw Outage.backendDown },
            .init(providerID: "network") { throw Outage.networkLost },
            .init(providerID: "local") { [7] }
        ])
        #expect(response.values == [7])
        #expect(response.coverage == .partial)
        #expect(response.failures == [
            .init(providerID: "backend", reason: "provider_error"),
            .init(providerID: "network", reason: "provider_error")
        ])
    }

    @Test func cancellingOldCommandDoesNotReturnAStaleAggregate() async throws {
        let oldCommand = Task {
            try await ProviderFanoutEngine<Int>(timeout: .seconds(5)).execute([
                .init(providerID: "old") {
                    try await Task.sleep(for: .seconds(60))
                    return [1]
                }
            ])
        }
        oldCommand.cancel()
        await #expect(throws: CancellationError.self) { try await oldCommand.value }

        let current = try await ProviderFanoutEngine<Int>().execute([
            .init(providerID: "new") { [2] }
        ])
        #expect(current.values == [2])
        #expect(current.coverage == .complete)
    }
}
