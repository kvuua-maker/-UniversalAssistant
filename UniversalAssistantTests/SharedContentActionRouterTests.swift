import Foundation
import Testing
@testable import UniversalAssistant

@Suite("Shared content, clipboard and scanner routing")
struct SharedContentActionRouterTests {
    let router = SharedContentActionRouter()

    @Test func sharedURLPreservesExactContextAndRequiresConfirmationToOpen() throws {
        let url = try #require(URL(string: "https://example.com/item?id=42"))
        let route = try router.route(.url(url), requested: .open)
        #expect(route.content == .url(url))
        #expect(route.requiresConfirmation)
    }

    @Test func contentCannotBeRoutedToAnUnrelatedAction() {
        #expect(throws: SharedContentRoutingError.unsupportedAction) {
            try router.route(.imageReference("asset-1"), requested: .call)
        }
    }

    @Test func qrRoutesURLAndVCardButRejectsPaymentAutomation() throws {
        #expect(try router.routeQR("https://example.com/ticket").action == .open)
        #expect(try router.routeQR("BEGIN:VCARD\nFN:Test Person\nEND:VCARD").action == .importContact)
        #expect(throws: SharedContentRoutingError.unsupportedAction) {
            try router.routeQR("bitcoin:bc1qexample?amount=1")
        }
    }

    @Test func onlyValidatedGTINCanEnterProductIdentification() throws {
        let exact = try router.routeRetailBarcode("0194253406532")
        #expect(exact.content == .retailBarcode("0194253406532"))
        #expect(throws: SharedContentRoutingError.invalidPayload) {
            try router.routeRetailBarcode("0194253406533")
        }
    }

    @MainActor @Test func sharedInboxIsConsumedExactlyOnce() throws {
        let suite = "ua-share-test-" + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let item = SharedInboxEnvelope(kind: "url", value: "https://example.com/a", receivedAt: .now)
        defaults.set(try JSONEncoder().encode(item), forKey: SharedInboxStore.inboxKey)
        let store = SharedInboxStore(defaults: defaults)
        #expect(store.consume() == item)
        #expect(store.consume() == nil)
    }

      func sharedImageFilePayloadIsReadableByHostWithoutUserDefaultsBlob() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let expected = Data([1, 2, 3, 4])
        try expected.write(to: url, options: .atomic)
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(SharedInboxStore.imageData(from: url.absoluteString) == expected)
        #expect(SharedInboxStore.imageData(from: expected.base64EncodedString()) == expected)
    }
}
