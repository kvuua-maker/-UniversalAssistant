import Foundation
import Testing
@testable import UniversalAssistant

private struct FXStub: CurrentFXProviding {
    let result: Result<CurrentFXConversion, Error>
    func convert(_ request: FXConversionRequest) async throws -> CurrentFXConversion { try result.get() }
}

@MainActor
struct CurrentFXProviderTests {
    @Test func parserKeepsAmountAndCurrencyDirection() throws {
        let value = try #require(FXConversionRequestParser().parse("Конвертуй 275 євро у польські злоті"))
        #expect(value == .init(amount: 275, source: "EUR", destination: "PLN"))
    }

    @Test func officialCurrentRateReturnsSourcedInAppResult() async throws {
        let request = FXConversionRequest(amount: 275, source: "EUR", destination: "PLN")
        let executor = ProductionCanonicalCapabilityExecutor(
            fx: FXStub(result: .success(.init(request: request, convertedAmount: 1_185.3325, observedAt: Date(timeIntervalSince1970: 1_725_000_000), provider: "European Central Bank"))),
            personalSearchSources: []
        )
        let command = LocalCommandEngine().parse("Конвертуй 275 євро у польські злоті")
        #expect(command.intent == .currencyConversion)
        guard case let .result(result) = try await executor.execute(command) else {
            Issue.record("Expected an in-app sourced FX result")
            return
        }
        #expect(result.primaryAnswer.contains("PLN"))
        #expect(result.facts.first?.source == "European Central Bank")
    }

    @Test func currencyOutsideOfficialCoverageRemainsTruthfulDependency() async {
        let executor = ProductionCanonicalCapabilityExecutor(
            fx: FXStub(result: .failure(CurrentFXError.unsupportedCurrency("UAH"))),
            personalSearchSources: []
        )
        let command = LocalCommandEngine().parse("Переведи 80 доларів у гривні")
        await #expect(throws: CanonicalCapabilityExecutionError.externalProviderRequired("current_fx_rate_for_currency")) {
            try await executor.execute(command)
        }
    }
}
