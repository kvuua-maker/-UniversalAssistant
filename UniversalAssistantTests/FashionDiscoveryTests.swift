import Foundation
import Testing
@testable import UniversalAssistant

@Suite("Fashion discovery and official opening") struct FashionDiscoveryTests {
    private let parser = LocalCommandEngine()

    @Test func multilingualFashionFiltersRemainHardConstraints() throws {
        let command = parser.parse("Покажи нову жіночу колекцію Baldinini: чорне взуття 43 розміру до 12000 грн")
        let request = try FashionDiscoveryRequest(command: command)
        #expect(request.audience == .women)
        #expect(request.category == .footwear)
        #expect(request.brand == "Baldinini")
        #expect(request.size == "43")
        #expect(request.color == "black")
        #expect(request.maximumPrice == Money(amount: 12000, currency: "UAH"))
        #expect(request.requestedClaims == [.latestCollection])
    }

    @Test func officialAppPrecedesExactOfficialWebPage() throws {
        let request = try FashionDiscoveryRequest(command: parser.parse("Zeige neue Kollektion Baldinini"))
        let result = FashionSourceResult(id: "collection", providerID: "brand", title: "New",
                                         officialWebURL: URL(string: "https://shop.example/collections/new")!,
                                         officialAppURL: URL(string: "brandapp://collections/new")!, verifiedAt: .now,
                                         sourceClaims: [.latestCollection])
        let config = OfficialFashionSourceConfiguration(providerID: "brand", allowedHosts: ["shop.example"], allowedAppSchemes: ["brandapp"])
        #expect(try FashionOfficialSourceRouter().destination(for: result, request: request, configuration: config) == result.officialAppURL)
    }

    @Test func latestAndDiscountAreNeverInvented() throws {
        let request = try FashionDiscoveryRequest(command: parser.parse("Show latest collection with discount"))
        let result = FashionSourceResult(id: "collection", providerID: "brand", title: "Collection",
                                         officialWebURL: URL(string: "https://shop.example/collections/all")!,
                                         verifiedAt: .now, sourceClaims: [.latestCollection])
        let config = OfficialFashionSourceConfiguration(providerID: "brand", allowedHosts: ["shop.example"])
        #expect(throws: FashionDiscoveryError.unverifiedClaim) {
            try FashionOfficialSourceRouter().destination(for: result, request: request, configuration: config)
        }
    }

    @Test func homepageAndUnapprovedHostAreRejected() throws {
        let request = try FashionDiscoveryRequest(command: parser.parse("Show collection"))
        let config = OfficialFashionSourceConfiguration(providerID: "brand", allowedHosts: ["official.example"])
        let homepage = FashionSourceResult(id: "home", providerID: "brand", title: "Home",
                                           officialWebURL: URL(string: "https://official.example/")!, verifiedAt: .now)
        #expect(throws: FashionDiscoveryError.invalidOfficialDestination) {
            try FashionOfficialSourceRouter().destination(for: homepage, request: request, configuration: config)
        }
    }
}
