import Foundation
import MessageUI
import SwiftUI
import UIKit
import Contacts
import ContactsUI

enum CapabilityPresentation: Equatable, Sendable, Identifiable {
    case camera
    case ocrCamera
    case ocrDocuments
    case scanner
    case documents
    case share(String)
    case message(recipients: [String], body: String?)
    case contactImport(Data)
    case translationTarget(String)
    case translation(LocalTranslationPlan)

    var id: String {
        switch self {
        case .camera: "camera"
        case .ocrCamera: "ocr-camera"
        case .ocrDocuments: "ocr-documents"
        case .scanner: "scanner"
        case .documents: "documents"
        case .share: "share"
        case .message: "message"
        case .contactImport: "contact-import"
        case .translationTarget: "translation-target"
        case .translation: "translation"
        }
    }
}

enum CapabilityExecutionOutcome: Equatable, Sendable {
    case result(DeterministicResult)
    case handoff(WebHandoffResult)
    case presentation(CapabilityPresentation)
}

enum CanonicalCapabilityExecutionError: Error, Equatable, Sendable {
    case missingParameter(String)
    case ambiguous([String])
    case unavailable(String)
    case externalProviderRequired(String)
}

@MainActor
protocol CanonicalCapabilityExecuting: AnyObject {
    func execute(_ command: StructuredCommand) async throws -> CapabilityExecutionOutcome
}

@MainActor
final class ProductionCanonicalCapabilityExecutor: CanonicalCapabilityExecuting {
    private let deviceRouter: UniversalDeviceCommandRouter
    private let contacts: LocalContactResolver
    private let photos: any PhotoLibrarySearching
    private let podcasts: ApplePodcastSearchProvider
    private let media: MediaIntegrationEngine?
    private let locationResolver: ManualLocationContextResolver
    private let placeSearch: PlaceSearchEngine
    private let navigation = NavigationHandoff()
    private let currentLocation: any CurrentLocationResolving
    private let personalSearch: UniversalPersonalSearchEngine

    init(
        deviceRouter: UniversalDeviceCommandRouter = .init(applications: .init(applications: LaunchDeviceApplications.verified)),
        contacts: LocalContactResolver = .init(),
        photos: any PhotoLibrarySearching = PhotoKitLibrarySearch(),
        podcasts: ApplePodcastSearchProvider = .init(),
        locationResolver: ManualLocationContextResolver = .init(),
        placeSearch: PlaceSearchEngine = .init(providers: [MapKitPlaceProvider()]),
        currentLocation: any CurrentLocationResolving = AppleCurrentLocationResolver(),
        personalSearchSources: [any PersonalSearchSource] = [ContactsPersonalSearchSource(), PhotosPersonalSearchSource(), LocalPersonalSearchSourceAdapter(source: AuthorizedFileSearchSource())]
    ) {
        self.deviceRouter = deviceRouter
        self.contacts = contacts
        self.photos = photos
        self.podcasts = podcasts
        self.locationResolver = locationResolver
        self.placeSearch = placeSearch
        self.currentLocation = currentLocation
        self.personalSearch = UniversalPersonalSearchEngine(sources: personalSearchSources)
#if canImport(MusicKit)
        self.media = MediaIntegrationEngine(adapters: [AppleMusicProviderAdapter()])
#else
        self.media = nil
#endif
    }

    func execute(_ command: StructuredCommand) async throws -> CapabilityExecutionOutcome {
        switch command.intent {
        case .open, .appAction:
            return try app(command)
        case .contactLookup:
            return try await personal(command, query: try required(command.entities["contact"], "contact_name"), immediateOpen: true)
        case .contactCall:
            return try await contact(command, preparesCall: true)
        case .messageCompose:
            return .presentation(.message(
                recipients: command.entities["recipient"].map { [$0] } ?? [],
                body: command.entities["message_body"]
            ))
        case .noteCreate:
            let value = try required(command.entities["content"] ?? subject(after: ["створи нотатку", "создай заметку", "create a note"], in: command.originalText), "note_content")
            return .presentation(.share(value))
        case .noteQuery:
            return .presentation(.documents)
        case .fileSearch:
            return try await personal(command, query: try required(command.entities["query"], "file_query"), immediateOpen: true)
        case .cameraCapture:
            if command.entities["capture_mode"] == "code_scan" { return .presentation(.scanner) }
            if command.entities["capture_mode"] == "text_scan" { return .presentation(command.entities["input_source"] == "document" ? .ocrDocuments : .ocrCamera) }
            return .presentation(.camera)
        case .photoSearch:
            return try await personal(command, query: command.entities["query"] ?? "", immediateOpen: false)
        case .podcastSearch:
            let query = try required(command.entities["query"], "podcast_query")
            let values = try await podcasts.search(query, limit: 3, country: Locale.current.region?.identifier ?? "UA")
            return .result(try result("Знайдено подкасти", facts: values.enumerated().map { index, item in
                ResultFact(id: item.id, label: item.title, value: item.show ?? "Podcast", state: .verified, source: "Apple Podcasts", observedAt: .now, priority: 100 - index)
            }, actions: values.map { .init(id: $0.id, title: "Відкрити", kind: .open, destination: $0.exactURL) }))
        case .mediaSearch:
            guard let media else { throw CanonicalCapabilityExecutionError.unavailable("musickit_unavailable") }
            let query = try required(command.entities["query"], "media_query")
            let values = try await media.search(providerID: "apple-music", query: query, kinds: [.song, .album, .artist, .playlist], limit: 3, requestAuthorization: true)
            return .result(try result("Знайдено в Apple Music", facts: values.enumerated().map { index, item in
                ResultFact(id: item.id, label: item.title, value: item.artist ?? item.kind.rawValue, state: .verified, source: "Apple Music", observedAt: .now, priority: 100 - index)
            }, actions: values.compactMap { item in item.exactURL.map { .init(id: item.id, title: "Відкрити", kind: .open, destination: $0) } }))
        case .emergency:
            guard let url = URL(string: "tel:112") else { throw CanonicalCapabilityExecutionError.unavailable("invalid_emergency_handoff") }
            return .handoff(.init(query: command.originalText, destination: url, kind: .system))
        case .settings:
            guard let url = URL(string: "app-settings:") else { throw CanonicalCapabilityExecutionError.unavailable("settings_unavailable") }
            return .handoff(.init(query: command.originalText, destination: url, kind: .system))
        case .help:
            return .result(try result("Скажіть або введіть, що потрібно зробити", facts: []))
        case .show, .contextualSelection:
            throw CanonicalCapabilityExecutionError.missingParameter("active_result_context")
        case .cancel:
            return .result(try result("Скасовано", facts: []))
        case .productSearch, .fashionDiscovery, .groceryBasket, .serviceSearch, .restaurantSearch,
             .reservation, .taxiSearch, .taxiCompare, .publicTransport, .transportRoute,
             .ticketSearch, .ticketPurchaseHandoff, .hotelSearch, .travelPlan, .parcelTrack:
            throw CanonicalCapabilityExecutionError.externalProviderRequired(command.intent.rawValue)
        case .placeSearch:
            return try await places(command)
        case .navigation, .routeSearch:
            return try await route(command)
        case .routeAwareSearch:
            throw CanonicalCapabilityExecutionError.unavailable("active_route_context_required")
        case .reminderComplete, .reminderDelete, .shoppingList, .undo, .multiStep:
            throw CanonicalCapabilityExecutionError.unavailable("canonical_mutation_context_required")
        case .calendarCreate, .calendarQuery, .calendarUpdate, .calendarDelete, .reminderCreate,
             .reminderQuery, .weather, .webSearch, .deviceAction, .audioRecord, .unknown:
            throw CanonicalCapabilityExecutionError.unavailable("handled_by_specialized_executor")
        }
    }

    private func places(_ command: StructuredCommand) async throws -> CapabilityExecutionOutcome {
        let location: ValidatedLocation
        if let area = command.entities["location"], !area.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            location = try await locationResolver.resolve(area)
        } else {
            location = try await currentLocation.resolveCurrent(for: .nearbySearch)
        }
        let category = placeCategory(in: command.normalizedText)
        let response = try await placeSearch.search(.init(text: command.entities["serviceCategory"] ?? command.originalText, category: category, location: location, limit: 5))
        guard !response.places.isEmpty else { throw CanonicalCapabilityExecutionError.unavailable("no_places_found") }
        return .result(try result("Знайдено місця", facts: response.places.prefix(5).enumerated().map { index, place in
            ResultFact(id: place.id, label: place.name, value: place.address ?? place.category.rawValue, state: .verified, source: place.source, observedAt: place.timestamp, priority: 100 - index)
        }, actions: response.places.prefix(5).compactMap { place in
            guard let destination = try? navigation.url(provider: .appleMaps, destination: .init(latitude: place.latitude, longitude: place.longitude, name: place.name), mode: .walking) else { return nil }
            return ResultAction(id: place.id, title: "Маршрут", kind: .open, destination: destination)
        }))
    }

    private func route(_ command: StructuredCommand) async throws -> CapabilityExecutionOutcome {
        let destinationName = try required(command.entities["destination"], "destination")
        let destination = try await locationResolver.resolve(destinationName)
        let url = try navigation.url(provider: .appleMaps, destination: .init(latitude: destination.sample.latitude, longitude: destination.sample.longitude, name: destinationName), mode: .driving)
        return .handoff(.init(query: command.originalText, destination: url, kind: .navigation))
    }

    private func app(_ command: StructuredCommand) throws -> CapabilityExecutionOutcome {
        switch deviceRouter.route(command) {
        case let .deviceApplication(_, destination, _): return .handoff(.init(query: command.originalText, destination: destination, kind: .system))
        case let .clarification(values): throw CanonicalCapabilityExecutionError.ambiguous(values)
        case let .unsupported(reason): throw CanonicalCapabilityExecutionError.unavailable(reason)
        default: throw CanonicalCapabilityExecutionError.unavailable("unsupported_app_route")
        }
    }

    private func personal(_ command: StructuredCommand, query: String, immediateOpen: Bool) async throws -> CapabilityExecutionOutcome {
        let report = await personalSearch.search(query, requestsImmediateOpen: immediateOpen)
        let values: [PersonalSearchResult] = switch report.presentation {
        case let .exactOpen(value): [value]
        case let .shortlist(values): values
        case .noResult: []
        }
        guard !values.isEmpty else { throw CanonicalCapabilityExecutionError.unavailable(report.isPartial ? "personal_search_partial_no_result" : "personal_search_no_result") }
        let facts = values.enumerated().map { index, value in ResultFact(id: value.id, label: value.title, value: value.subtitle ?? value.sourceObjectID, state: .verified, source: personalSourceName(value.source), observedAt: personalObservedAt(value.freshness), priority: 100 - index) }
        let actions = values.compactMap { value -> ResultAction? in guard let url = URL(string: value.openReference) else { return nil }; return .init(id: value.id, title: "Відкрити", kind: .open, destination: url) }
        return .result(try result("Знайдено на iPhone", facts: facts, actions: actions))
    }

    private func personalSourceName(_ source: PersonalSearchSourceID) -> String {
        switch source { case let .local(kind): return kind.rawValue; case let .connectedEmail(value), let .connectedService(value): return value }
    }
    private func personalObservedAt(_ freshness: PersonalSearchFreshness) -> Date {
        switch freshness { case let .live(date), let .cached(date): return date; case .local, .unknown: return .now }
    }

    private func contact(_ command: StructuredCommand, preparesCall: Bool) async throws -> CapabilityExecutionOutcome {
        let name = try required(command.entities["contact"], "contact_name")
        try await contacts.requestAccessIfNeeded()
        switch try await contacts.resolve(name: name) {
        case .notFound: throw CanonicalCapabilityExecutionError.unavailable("contact_not_found")
        case let .ambiguous(values): throw CanonicalCapabilityExecutionError.ambiguous(values.map(\.displayName))
        case let .resolved(value):
            if preparesCall {
                guard value.phoneNumbers.count == 1,
                      let digits = value.phoneNumbers.first?.filter(\.isNumber),
                      let url = URL(string: "tel:\(digits)") else {
                    throw CanonicalCapabilityExecutionError.ambiguous(value.phoneNumbers)
                }
                return .handoff(.init(query: value.displayName, destination: url, kind: .system))
            }
            return .result(try result(value.displayName, facts: value.phoneNumbers.enumerated().map { index, number in
                ResultFact(id: "phone-\(index)", label: "Телефон", value: number, state: .verified, source: "Contacts", observedAt: .now, priority: 100 - index)
            }))
        }
    }

    private func result(_ answer: String, facts: [ResultFact], actions: [ResultAction] = []) throws -> DeterministicResult {
        try DeterministicResultComposer().compose(primaryAnswer: answer, facts: facts, actions: actions)
    }

    private func placeCategory(in text: String) -> PlaceCategory? {
        if ["кав", "кафе", "кофе", "coffee", "cafe"].contains(where: text.contains) { return .cafe }
        if ["ресторан", "restaurant"].contains(where: text.contains) { return .restaurant }
        if ["супермаркет", "supermarket", "grocer"].contains(where: text.contains) { return .supermarket }
        if ["магазин", "store", "shop"].contains(where: text.contains) { return .shop }
        return nil
    }

    private func required(_ value: String?, _ key: String) throws -> String {
        guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw CanonicalCapabilityExecutionError.missingParameter(key) }
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func subject(after prefixes: [String], in text: String) -> String? {
        prefixes.compactMap { prefix in text.range(of: prefix, options: [.caseInsensitive, .diacriticInsensitive]).map { String(text[$0.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines) } }.first
    }
}


struct VCardImportConfirmationView: UIViewControllerRepresentable {
    let data: Data
    let onComplete: () -> Void
    func makeUIViewController(context: Context) -> UINavigationController {
        let controller = (try? VCardImportIntegration().makeConfirmationController(data: data)) ?? CNContactViewController(forNewContact: CNMutableContact())
        controller.delegate = context.coordinator
        return UINavigationController(rootViewController: controller)
    }
    func updateUIViewController(_ controller: UINavigationController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(onComplete: onComplete) }
    final class Coordinator: NSObject, CNContactViewControllerDelegate {
        let onComplete: () -> Void
        init(onComplete: @escaping () -> Void) { self.onComplete = onComplete }
        func contactViewController(_ viewController: CNContactViewController, didCompleteWith contact: CNContact?) { onComplete() }
    }
}

struct SystemShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
