import Foundation
import Testing
@testable import UniversalAssistant

private actor B27PersonalSearchProbe {
    private(set) var calls = 0
    func record() { calls += 1 }
}

private struct B27UnexpectedPersonalSource: PersonalSearchSource {
    let id: PersonalSearchSourceID = .local(.photos)
    let probe: B27PersonalSearchProbe
    func search(query: String, limit: Int) async -> PersonalSearchSourceResponse {
        await probe.record()
        return .init(source: id, results: [], isComplete: false, unavailableReason: "unexpected_fanout")
    }
}

private actor B27ContactResolverStub: ContactResolving {
    let resolution: ContactResolution
    init(_ resolution: ContactResolution) { self.resolution = resolution }
    func requestAccessIfNeeded() async throws {}
    func resolve(name: String) async throws -> ContactResolution { resolution }
    func resolve(exactIdentifier identifier: String) async throws -> ContactResolution { resolution }
}

@Suite("B27 production personal routing boundaries")
@MainActor
struct ProductionPersonalRoutingBoundaryTests {
    @Test func contactLookupUsesOnlyBoundedContactsResolver() async throws {
        let contact = ContactCandidate(identifier: "sashko", displayName: "Сашко", phoneNumbers: ["+380501234567"])
        let probe = B27PersonalSearchProbe()
        let executor = ProductionCanonicalCapabilityExecutor(
            contacts: B27ContactResolverStub(.resolved(contact)),
            personalSearchSources: [B27UnexpectedPersonalSource(probe: probe)]
        )
        let command = LocalCommandEngine().parse("Знайди контакт Сашко")
        #expect(command.intent == .contactLookup)
        guard case let .presentation(presentation) = try await executor.execute(command) else {
            Issue.record("Expected the official existing-contact presentation")
            return
        }
        #expect(presentation == .contactCard(identifier: "sashko"))
        #expect(await probe.calls == 0)
    }

    @Test func fileSearchUsesPublicDocumentPickerInsteadOfPersonalFanout() async throws {
        let probe = B27PersonalSearchProbe()
        let executor = ProductionCanonicalCapabilityExecutor(
            personalSearchSources: [B27UnexpectedPersonalSource(probe: probe)]
        )
        let command = LocalCommandEngine().parse("Знайди документ PDF")
        #expect(command.intent == .fileSearch)
        #expect(try await executor.execute(command) == .presentation(.documents))
        #expect(await probe.calls == 0)
    }
}
