import Foundation
import Testing
@testable import UniversalAssistant

@Suite("Ride provider truth and handoff") struct RideProviderRegistryTests {
    @Test func researchedProvidersCannotSupplyInventedComparisonEvidence() throws {
        let registry = RideProviderRegistry()
        let bolt = try #require(registry.capabilities(for: "bolt"))
        let uklon = try #require(registry.capabilities(for: "uklon"))
        #expect(!bolt.canSupplyComparisonEvidence)
        #expect(!uklon.canSupplyComparisonEvidence)
        #expect(!bolt.supportsRoutePrefillHandoff)
        #expect(!uklon.supportsRoutePrefillHandoff)
    }

    @Test func uberHandoffIsSupportedButLiveFieldsRemainCredentialGated() throws {
        let uber = try #require(RideProviderRegistry().capabilities(for: "uber"))
        #expect(uber.status == .credentialRequired)
        #expect(uber.supportsRoutePrefillHandoff)
        #expect(!uber.canSupplyComparisonEvidence)
    }

    @Test func uberBuilderRequiresCredentialAndExactValidLocations() throws {
        let pickup = RideHandoffLocation(latitude: 50.4501, longitude: 30.5234,
                                         nickname: "Pickup", address: "Kyiv")
        let dropoff = RideHandoffLocation(latitude: 50.4547, longitude: 30.5238,
                                          nickname: "Destination", address: "Maidan, Kyiv")
        #expect(throws: RideHandoffError.missingCredential) {
            try UberRideHandoffBuilder().destination(clientID: "", pickup: pickup, dropoff: dropoff)
        }
        let url = try UberRideHandoffBuilder().destination(clientID: "public-client-id", pickup: pickup, dropoff: dropoff)
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        #expect(url.scheme == "https")
        #expect(url.host == "m.uber.com")
        #expect(url.path == "/looking")
        #expect(components.queryItems?.first(where: { $0.name == "dropoff[formatted_address]" })?.value == "Maidan, Kyiv")
    }
}
