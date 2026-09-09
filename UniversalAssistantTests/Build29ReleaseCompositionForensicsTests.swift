import Foundation
import Testing
@testable import UniversalAssistant

private actor Build29ReleaseContactBoundary: ContactResolving {
    let resolution: ContactResolution
    init(_ resolution: ContactResolution) { self.resolution = resolution }
    func authorizationState() async -> ContactAuthorizationState { .authorized }
    func requestAccessIfNeeded() async throws {}
    func resolve(name: String) async throws -> ContactResolution { resolution }
    func resolve(exactIdentifier identifier: String) async throws -> ContactResolution { resolution }
}

@MainActor
private final class Build29SystemOpenCapture {
    private(set) var urls: [URL] = []
    func open(_ url: URL) { urls.append(url) }
}

@Suite("Build 29 Release composition forensics", .serialized)
@MainActor
struct Build29ReleaseCompositionForensicsTests {
    @Test func physicalContactAndMessageEvidenceReachesTypedFamiliesBeforeFallback() {
        let parser = LocalCommandEngine()
        let expectations: [(String, CommandIntent)] = [
            ("Подзвони мама", .contactCall),
            ("Подзвони Сашко", .contactCall),
            ("Подзвони Влад", .contactCall),
            ("Напиши мама", .messageCompose),
            ("Напиши Сашко", .messageCompose),
            ("Напиши Влад", .messageCompose)
        ]
        for (input, expected) in expectations {
            let command = parser.parse(input)
            #expect(command.intent == expected, "Release parser selected \(command.intent) for \(input)")
            #expect(command.intent != .webSearch && command.intent != .unknown)
        }
    }

    @Test func releaseHomeCallUsesCanonicalExecutorAndTelephoneHandoff() async throws {
        let contact = ContactCandidate(identifier: "release-contact", displayName: "Наталія", phoneNumbers: ["+380 67 111 22 33"])
        let capture = Build29SystemOpenCapture()
        let model = ProductionAssistantComposition.makeModel(
            contacts: Build29ReleaseContactBoundary(.resolved(contact)),
            personalSearchSources: [], compactResultDuration: .seconds(60),
            systemHandoffOpen: capture.open
        )
        model.input = "Набери Наталія"
        model.submit()
        for _ in 0..<100 where capture.urls.isEmpty { try await Task.sleep(for: .milliseconds(10)) }
        #expect(capture.urls.first?.scheme == "tel")
        #expect(model.statusText != AppText.value("processing"))
    }

    @Test func releaseHomeMessageProducesSystemComposerWithoutWeb() async throws {
        let contact = ContactCandidate(identifier: "release-message-contact", displayName: "Марко", phoneNumbers: ["+380 93 555 66 77"])
        let model = ProductionAssistantComposition.makeModel(
            contacts: Build29ReleaseContactBoundary(.resolved(contact)),
            personalSearchSources: [], compactResultDuration: .seconds(60)
        )
        model.input = "Напиши Марко що зустрінемось пізніше"
        model.submit()
        for _ in 0..<100 where model.capabilityPresentation == nil { try await Task.sleep(for: .milliseconds(10)) }
        guard case let .message(recipients, _)? = model.capabilityPresentation else {
            Issue.record("Release Home did not reach MessageUI presentation")
            return
        }
        #expect(recipients == ["380935556677"])
        #expect(model.statusText != AppText.value("processing"))
    }

    @Test func nearbyNaturalRequestCannotResolveAsGenericWeb() {
        let parser = LocalCommandEngine()
        for input in ["Перекусити неподалік", "Знайди пекарню поблизу", "Де поруч випити чаю"] {
            let command = parser.parse(input)
            #expect([.placeSearch, .restaurantSearch, .serviceSearch].contains(command.intent), "Selected \(command.intent) for \(input)")
            #expect(command.intent != .webSearch && command.intent != .unknown)
        }
    }
}
