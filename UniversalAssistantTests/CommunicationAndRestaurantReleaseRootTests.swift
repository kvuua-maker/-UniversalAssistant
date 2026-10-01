import Foundation
import Testing
import UIKit
@testable import UniversalAssistant

private actor AddedCommunicationContactBoundary: ContactResolving {
    let value: ContactResolution
    private(set) var accessRequestCount = 0

    init(_ value: ContactResolution) { self.value = value }

    func authorizationState() async -> ContactAuthorizationState { .authorized }
    func requestAccessIfNeeded() async throws { accessRequestCount += 1 }
    func resolve(name: String) async throws -> ContactResolution { value }
    func resolve(exactIdentifier identifier: String) async throws -> ContactResolution { value }
}

@MainActor
private final class AddedSystemOpenCapture {
    private(set) var values: [URL] = []
    func open(_ url: URL) { values.append(url) }
}

@Suite("General communication channels through shipped Release root", .serialized)
@MainActor
struct CommunicationReleaseRootTests {
    private func waitUntil(_ predicate: @escaping @MainActor () -> Bool) async throws {
        for _ in 0..<200 {
            if predicate() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        Issue.record("Timed out waiting for shipped Release-root result")
    }

    @Test func unqualifiedMessageAndExplicitEmailUseDifferentPublicComposers() async throws {
        let generic = LanguageUnderstandingBlock().parse("Надішли повідомлення")
        #expect(generic.intent == .messageCompose)
        #expect(generic.entities["message_service"] == MessengerKind.messages.rawValue)
        #expect(!generic.needsClarification)

        let messagesContacts = AddedCommunicationContactBoundary(.notFound)
        let messagesModel = ProductionAssistantComposition.makeModel(
            contacts: messagesContacts,
            personalSearchSources: [], compactResultDuration: .seconds(60)
        )
        messagesModel.input = "Надішли повідомлення"
        messagesModel.submit()
        try await waitUntil { messagesModel.capabilityPresentation != nil }
        guard case let .message(recipients, body)? = messagesModel.capabilityPresentation else {
            Issue.record("Generic message did not reach MessageUI")
            return
        }
        #expect(recipients.isEmpty)
        #expect(body == nil)
        #expect(await messagesContacts.accessRequestCount == 0)

        let emailInput = "Напиши email qa.team@example.org: Перевір оновлений звіт"
        let email = LanguageUnderstandingBlock().parse(emailInput)
        #expect(email.intent == .messageCompose)
        #expect(email.entities["message_service"] == "email")
        #expect(email.entities["recipient"] == "qa.team@example.org")

        let emailModel = ProductionAssistantComposition.makeModel(
            personalSearchSources: [], compactResultDuration: .seconds(60)
        )
        emailModel.input = emailInput
        emailModel.submit()
        try await waitUntil { emailModel.capabilityPresentation != nil }
        guard case let .email(recipients, _, body)? = emailModel.capabilityPresentation else {
            Issue.record("Explicit email did not reach Mail composer")
            return
        }
        #expect(recipients == ["qa.team@example.org"])
        #expect(body == "Перевір оновлений звіт")
    }

    @Test func explicitSupportedMessengerOwnsTheHandoffWithoutChangingGenericMessageDefault() async throws {
        let contact = ContactCandidate(
            identifier: "unseen-recipient", displayName: "Дарина",
            phoneNumbers: ["+380 63 246 80 12"]
        )
        let whatsappCapture = AddedSystemOpenCapture()
        let whatsapp = ProductionAssistantComposition.makeModel(
            contacts: AddedCommunicationContactBoundary(.resolved(contact)),
            personalSearchSources: [], compactResultDuration: .seconds(60),
            systemHandoffOpen: whatsappCapture.open
        )
        whatsapp.input = "Відправ повідомлення Дарині через WhatsApp"
        whatsapp.submit()
        try await waitUntil { !whatsappCapture.values.isEmpty }
        #expect(whatsappCapture.values.first?.host == "wa.me")
        #expect(whatsappCapture.values.first?.path == "/380632468012")

        let telegramCapture = AddedSystemOpenCapture()
        let telegramInput = "Напиши через Telegram @orbit_team: Зустріч перенесено"
        let telegramCommand = LanguageUnderstandingBlock().parse(telegramInput)
        #expect(telegramCommand.entities["message_service"] == MessengerKind.telegram.rawValue)
        #expect(telegramCommand.entities["recipient"] == "@orbit_team")
        let telegram = ProductionAssistantComposition.makeModel(
            personalSearchSources: [], compactResultDuration: .seconds(60),
            systemHandoffOpen: telegramCapture.open
        )
        telegram.input = telegramInput
        telegram.submit()
        try await waitUntil { !telegramCapture.values.isEmpty }
        #expect(telegramCapture.values.first?.scheme == "tg")
        #expect(URLComponents(url: telegramCapture.values[0], resolvingAgainstBaseURL: false)?
            .queryItems?.contains(.init(name: "domain", value: "orbit_team")) == true)

        let viberCapture = AddedSystemOpenCapture()
        let viber = ProductionAssistantComposition.makeModel(
            personalSearchSources: [], compactResultDuration: .seconds(60),
            systemHandoffOpen: viberCapture.open
        )
        viber.input = "Напиши через Viber: Буду за десять хвилин"
        viber.submit()
        try await waitUntil { !viberCapture.values.isEmpty }
        #expect(viberCapture.values.first?.scheme == "viber")
    }

    @Test func channelEvidenceDoesNotStealCallsOrOrdinaryWebRequests() {
        let parser = LanguageUnderstandingBlock()
        let call = parser.parse("Набери Дарину звичайним телефоном")
        #expect(call.intent == .contactCall)
        #expect(call.entities["call_service"] != MessengerKind.whatsapp.rawValue)

        let web = parser.parse("Поясни історію електронної пошти")
        #expect(web.intent != .messageCompose)
    }
}

@MainActor
private final class AddedRestaurantLocationBoundary: CurrentLocationResolving {
    let value: ValidatedLocation
    init(_ value: ValidatedLocation) { self.value = value }
    func resolveCurrent(for purpose: LocationPurpose) async throws -> ValidatedLocation { value }
}

private struct AddedRestaurantPlaceBoundary: PlaceProvider {
    let providerID = "mapkit-release-boundary"
    let restaurant: Place
    func search(_ query: PlaceQuery) async throws -> [Place] { [restaurant] }
}

private struct AddedEmptyRestaurantPlaceBoundary: PlaceProvider {
    let providerID = "empty-place-release-boundary"
    func search(_ query: PlaceQuery) async throws -> [Place] { [] }
}

private actor AddedRestaurantProviderBoundary: ReservationProvider {
    nonisolated let providerID = "official-table-provider"
    nonisolated let capabilities: Set<RestaurantProviderCapability> = [
        .availability, .booking, .modification, .cancellation
    ]
    private var currentSlotID = "slot-a"
    private var recordedOperations: [String] = []

    func availability(
        restaurantID: String,
        partySize: Int,
        interval: DateInterval
    ) async throws -> [RestaurantReservationSlot] {
        recordedOperations.append("availability:\(restaurantID):\(partySize)")
        return [
            .init(
                id: "slot-a", providerID: providerID, restaurantID: restaurantID,
                interval: .init(start: interval.start, duration: 1_800), partySize: partySize,
                availabilityVerified: true, observedAt: .now, sourceReference: "provider:slot-a"
            ),
            .init(
                id: "slot-b", providerID: providerID, restaurantID: restaurantID,
                interval: .init(start: interval.start.addingTimeInterval(1_800), duration: 1_800),
                partySize: partySize, availabilityVerified: true, observedAt: .now,
                sourceReference: "provider:slot-b"
            )
        ]
    }

    func book(slotID: String) async throws -> RestaurantReservation {
        currentSlotID = slotID
        recordedOperations.append("book:\(slotID)")
        return reservation(state: .confirmed)
    }

    func modify(bookingID: String, slotID: String) async throws -> RestaurantReservation {
        guard bookingID == "booking-a" else { throw RestaurantDiscoveryError.providerMismatch }
        currentSlotID = slotID
        recordedOperations.append("modify:\(slotID)")
        return reservation(state: .confirmed)
    }

    func cancel(bookingID: String) async throws -> RestaurantReservation {
        guard bookingID == "booking-a" else { throw RestaurantDiscoveryError.providerMismatch }
        recordedOperations.append("cancel:\(bookingID)")
        return reservation(state: .cancelled)
    }

    func operations() -> [String] { recordedOperations }

    private func reservation(state: AppointmentBookingState) -> RestaurantReservation {
        .init(
            id: "booking-a", providerID: providerID, slotID: currentSlotID,
            state: state, providerReference: "provider:booking-a", observedAt: .now
        )
    }
}

@Suite("Restaurant reservation family through shipped Release root", .serialized)
@MainActor
struct RestaurantReservationReleaseRootTests {
    private func waitUntil(_ predicate: @escaping @MainActor () -> Bool) async throws {
        for _ in 0..<250 {
            if predicate() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        Issue.record("Timed out waiting for restaurant Release-root result")
    }

    private func makeLocation() -> ValidatedLocation {
        .init(
            sample: .init(
                latitude: 50.45, longitude: 30.52, horizontalAccuracy: 5,
                timestamp: .now, speed: 0, course: 0, source: .device
            ),
            quality: .precise, isSafeForLocationActions: true, manualLabel: nil
        )
    }

    private func restaurant(website: URL? = nil) -> Place {
        .init(
            id: "restaurant-a", providerID: "mapkit", name: "River Bistro",
            category: .restaurant, latitude: 50.451, longitude: 30.521,
            address: "Набережна", distanceMeters: 180, phone: "+380441112233",
            officialWebsite: website, source: "MapKit release boundary",
            timestamp: .now, verification: .providerReturned
        )
    }

    @Test func availabilityBookingModificationAndCancellationUseVerifiedProviderState() async throws {
        let provider = AddedRestaurantProviderBoundary()
        let model = ProductionAssistantComposition.makeModel(
            placeSearch: .init(providers: [AddedRestaurantPlaceBoundary(restaurant: restaurant())]),
            currentLocation: AddedRestaurantLocationBoundary(makeLocation()),
            personalSearchSources: [], compactResultDuration: .seconds(60),
            restaurantProviders: [provider]
        )

        let availabilityInput = "Знайди столик у ресторані післязавтра о 19:30 для 3 гостей"
        let availability = LanguageUnderstandingBlock().parse(availabilityInput)
        #expect(availability.intent == .reservation)
        #expect(availability.entities["reservation_operation"] == "availability")
        #expect(availability.entities["party_size"] == "3")
        #expect(!availability.needsClarification)
        model.input = availabilityInput
        model.submit()
        try await waitUntil {
            if case let .deterministic(result) = model.resultState { return result.facts.count == 2 }
            return false
        }

        let bookingInput = "Забронюй перший столик у ресторані післязавтра о 19:30 для 3 гостей"
        let booking = LanguageUnderstandingBlock().parse(bookingInput)
        #expect(booking.entities["reservation_operation"] == "book")
        model.input = bookingInput
        model.submit()
        try await waitUntil { if case .actionRequired = model.resultState { return true }; return false }
        model.resolveActionRequiredChoice(AppText.value("confirm"))
        try await waitUntil {
            if case let .deterministic(result) = model.resultState {
                return result.facts.first?.value == "provider:booking-a"
            }
            return false
        }

        model.input = "Перенеси бронювання на другий варіант"
        model.submit()
        try await waitUntil { if case .actionRequired = model.resultState { return true }; return false }
        model.resolveActionRequiredChoice(AppText.value("confirm"))
        try await waitUntil {
            if case let .deterministic(result) = model.resultState {
                return result.primaryAnswer.contains("змінено")
            }
            return false
        }

        model.input = "Скасуй бронювання"
        model.submit()
        try await waitUntil { if case .actionRequired = model.resultState { return true }; return false }
        model.resolveActionRequiredChoice(AppText.value("confirm"))
        try await waitUntil {
            if case let .deterministic(result) = model.resultState {
                return result.primaryAnswer.contains("скасовано")
            }
            return false
        }

        let operations = await provider.operations()
        #expect(operations.contains("availability:restaurant-a:3"))
        #expect(operations.contains("book:slot-a"))
        #expect(operations.contains("modify:slot-b"))
        #expect(operations.contains("cancel:booking-a"))
    }

    @Test func absentBookingProviderReturnsOnlyTruthfulVerifiedHandoffs() async throws {
        let model = ProductionAssistantComposition.makeModel(
            placeSearch: .init(providers: [AddedRestaurantPlaceBoundary(
                restaurant: restaurant(website: URL(string: "https://river.example/reservations"))
            )]),
            currentLocation: AddedRestaurantLocationBoundary(makeLocation()),
            personalSearchSources: [], compactResultDuration: .seconds(60),
            restaurantProviders: []
        )
        model.input = "Покажи доступний ресторан завтра о 18:45 для 4 гостей"
        model.submit()
        try await waitUntil { if case .webHandoff = model.resultState { return true }; return false }
        guard case let .webHandoff(result) = model.resultState else {
            Issue.record("Missing truthful restaurant fallback")
            return
        }
        #expect(result.destination.host == "www.google.com")
        #expect(result.destination.path == "/search")
        #expect(result.query.contains("ресторан"))
    }

    @Test func emptyDedicatedDiscoveryUsesOneExactGoogleQueryWithoutDeadEnd() async throws {
        let input = "Знайди столик у ресторані в Чернівцях післязавтра о 18:45 для 4 гостей"
        let model = ProductionAssistantComposition.makeModel(
            placeSearch: .init(providers: [AddedEmptyRestaurantPlaceBoundary()]),
            currentLocation: AddedRestaurantLocationBoundary(makeLocation()),
            personalSearchSources: [], compactResultDuration: .seconds(60),
            restaurantProviders: []
        )
        model.input = input
        model.submit()
        try await waitUntil { if case .webHandoff = model.resultState { return true }; return false }
        guard case let .webHandoff(handoff) = model.resultState else {
            Issue.record("Missing exact Google fallback"); return
        }
        let destination = handoff.destination
        #expect(destination.host == "www.google.com")
        #expect(destination.path == "/search")
        let query = try #require(URLComponents(url: destination, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "q" })?.value)
        #expect(query.contains(input))
        #expect(query.contains("Чернівцях"))
        #expect(query.contains("18:45"))
    }

    @Test func reservationMutationsWithoutAuthoritativeBookingNeverFakeSuccess() async throws {
        let model = ProductionAssistantComposition.makeModel(
            personalSearchSources: [], compactResultDuration: .seconds(60),
            restaurantProviders: []
        )
        for request in ["Перенеси бронювання на третій варіант", "Скасуй бронювання"] {
            model.input = request
            model.submit()
            try await waitUntil { if case .failure = model.resultState { return true }; return false }
            #expect({ if case .deterministic = model.resultState { return false }; return true }())
            #expect({ if case .webHandoff = model.resultState { return false }; return true }())
        }
    }
}
