import Testing
@testable import UniversalAssistant

@Suite("Regional service configuration")
struct RegionalServiceConfigurationTests {
    @Test func ukraineIsAFullServiceMarketNotOnlyALocale() throws {
        let profile = try #require(RegionalServiceRegistry().profile(countryCode: "ua"))
        #expect(profile.defaultCurrencyCode == "UAH")
        #expect(profile.measurementSystem == .metric)
        #expect(profile.retailerProviderIDs.contains("ua.silpo.mcp"))
        #expect(profile.rideProviderIDs.contains("uklon"))
        #expect(profile.ticketProviderIDs.contains("uz"))
        #expect(profile.emergencyServices.map(\.number) == ["112", "101", "102", "103", "104"])
        #expect(!profile.emergencyServices.contains { !$0.userInitiatedCallOnly })
    }

    @Test func countrySelectionChangesProvidersEmergencyCurrencyAndUnits() throws {
        let registry = RegionalServiceRegistry()
        let germany = try #require(registry.profile(countryCode: "DE"))
        let unitedStates = try #require(registry.profile(countryCode: "US"))
        #expect(germany.defaultCurrencyCode == "EUR")
        #expect(germany.emergencyServices.contains { $0.number == "110" })
        #expect(unitedStates.defaultCurrencyCode == "USD")
        #expect(unitedStates.measurementSystem == .usCustomary)
        #expect(unitedStates.emergencyServices.map(\.number) == ["911"])
        #expect(registry.profile(countryCode: "ZZ") == nil)
    }
}
