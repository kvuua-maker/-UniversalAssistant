import Foundation
import Testing
@testable import UniversalAssistant

private func phone(gtin: String? = "0194253406532", sku: String? = "IP15-128-BLK",
                   storage: String = "128 GB", color: String = "Black") -> ProductIdentity {
    .init(brand: "Apple", model: "iPhone 15", productType: "phone", sku: sku, gtin: gtin,
          variant: .init(storage: storage, color: color, condition: .new, quantity: 1, quantityUnit: "piece"))
}

@Suite("Commerce identity and registry") struct CommerceIdentityRegistryTests {
    @Test func validatesRealGTINChecksumAndRejectsInventedCode() throws {
        #expect(GTINValidator().isValid("0194253406532"))
        #expect(!GTINValidator().isValid("0194253406533"))
        #expect(throws: ProductIdentityError.invalidGTIN) { try phone(gtin: "123").validated() }
    }

    @Test func barcodeIsExactOnlyWithoutVariantConflict() {
        let resolver = ProductIdentityResolver()
        #expect(resolver.match(query: phone(), candidate: phone()).level == .exact)
        let conflict = resolver.match(query: phone(), candidate: phone(storage: "256 GB"))
        #expect(conflict.level == .approximate)
        #expect(conflict.conflicts.contains("storage"))
    }

    @Test func visualLikeAttributesNeverBecomeExactWithoutStrongIdentifier() {
        let query = phone(gtin: nil, sku: nil)
        let candidate = phone(gtin: nil, sku: nil)
        #expect(ProductIdentityResolver().match(query: query, candidate: candidate).level == .compatible)
    }

    @Test func registryIsRegionCapabilityAndStatusAware() async {
        let usable = ProviderCapabilityRecord(
            id: "ua-ready", displayName: "UA Ready", regions: ["UA"], capabilities: [.search, .exactProduct],
            requiresCredentials: false, requiresOwnerRegistration: false, requiresApproval: false,
            restrictions: [], status: .adapterReady, enabled: true
        )
        var blocked = usable
        blocked = .init(id: "ua-blocked", displayName: "UA Blocked", regions: ["UA"], capabilities: [.search],
                        requiresCredentials: true, requiresOwnerRegistration: true, requiresApproval: false,
                        restrictions: [], status: .credentialRequired, enabled: true)
        let registry = ProviderCapabilityRegistry(records: [usable, blocked])
        let result = await registry.eligible(region: "ua", requiring: .search)
        #expect(result.map(\.id) == ["ua-ready"])
    }

    @Test func researchedProviderIsNeverExecutableButSilpoOfficialMCPIsAdapterReady() async {
        let registry = ProviderCapabilityRegistry(records: UkrainianRetailerRegistry.records)
        let eligible = await registry.eligible(region: "UA", requiring: [.search, .availability])
        #expect(eligible.map(\.id) == ["ua.silpo.mcp"])
        #expect(await registry.record(id: "ua.atb.web")?.status == .researched)
        #expect(await registry.record(id: "ua.atb.web")?.enabled == false)
        #expect(await registry.record(id: "ua.silpo.mcp")?.officialDocumentationURL?.host == "ai-factory.silpo.ua")
        #expect(await registry.record(id: "ua.silpo.mcp")?.affiliateNetwork == nil)
    }
}
