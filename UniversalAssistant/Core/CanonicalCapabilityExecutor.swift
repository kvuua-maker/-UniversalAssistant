import Foundation
import MessageUI
import SwiftUI
import UIKit

enum CapabilityPresentation: Equatable, Sendable, Identifiable {
    case camera
    case documents
    case share(String)
    case message(recipients: [String], body: String?)

    var id: String {
        switch self {
        case .camera: "camera"
        case .documents: "documents"
        case .share: "share"
        case .message: "message"
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

    init(
        deviceRouter: UniversalDeviceCommandRouter = .init(applications: .init(applications: LaunchDeviceApplications.verified)),
        contacts: LocalContactResolver = .init(),
        photos: any PhotoLibrarySearching = PhotoKitLibrarySearch(),
        podcasts: ApplePodcastSearchProvider = .init(),
        locationResolver: ManualLocationContextResolver = .init(),
        placeSearch: PlaceSearchEngine = .init(providers: [MapKitPlaceProvider()])
    ) {
        self.deviceRouter = deviceRouter
        self.contacts = contacts
        self.photos = photos
        self.podcasts = podcasts
        self.locationResolver = locationResolver
        self.placeSearch = placeSearch
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
            return try await contact(command, preparesCall: false)
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
        case .noteQuery, .fileSearch:
            return .presentation(.documents)
        case .cameraCapture:
            return .presentation(.camera)
        case .photoSearch:
            let query = command.entities["query"] ?? ""
            guard [.permitted, .limited].contains(photos.authorization()) else {
                throw CanonicalCapabilityExecutionError.unavailable("photos_permission_required")
            }
            let values = await PhotoSemanticSearchEngine(library: photos, loader: PhotoKitAssetImageLoader(), labeler: VisionPhotoSemanticLabeler()).search(query, limit: 5)
            return .result(try result(
                values.isEmpty ? "Немає підтверджених збігів" : "Знайдено фото: \(values.count)",
                facts: values.enumerated().map { index, value in
                    ResultFact(id: "photo-\(index)", label: "Фото \(index + 1)", value: value.creationDate?.formatted() ?? "Доступне фото", state: .verified, source: "PhotoKit", observedAt: .now, priority: 100 - index)
                }
            ))
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
            return .handoff(.init(query: command.originalText, destination: url))
        case .settings:
            guard let url = URL(string: "app-settings:") else { throw CanonicalCapabilityExecutionError.unavailable("settings_unavailable") }
            return .handoff(.init(query: command.originalText, destination: url))
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
        let area = try required(command.entities["location"], "location")
        let location = try await locationResolver.resolve(area)
        let category: PlaceCategory? = command.intent == .placeSearch ? .cafe : nil
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
        return .handoff(.init(query: command.originalText, destination: url))
    }

    private func app(_ command: StructuredCommand) throws -> CapabilityExecutionOutcome {
        switch deviceRouter.route(command) {
        case let .deviceApplication(_, destination, _): return .handoff(.init(query: command.originalText, destination: destination))
        case let .clarification(values): throw CanonicalCapabilityExecutionError.ambiguous(values)
        case let .unsupported(reason): throw CanonicalCapabilityExecutionError.unavailable(reason)
        default: throw CanonicalCapabilityExecutionError.unavailable("unsupported_app_route")
        }
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
                return .handoff(.init(query: value.displayName, destination: url))
            }
            return .result(try result(value.displayName, facts: value.phoneNumbers.enumerated().map { index, number in
                ResultFact(id: "phone-\(index)", label: "Телефон", value: number, state: .verified, source: "Contacts", observedAt: .now, priority: 100 - index)
            }))
        }
    }

    private func result(_ answer: String, facts: [ResultFact], actions: [ResultAction] = []) throws -> DeterministicResult {
        try DeterministicResultComposer().compose(primaryAnswer: answer, facts: facts, actions: actions)
    }

    private func required(_ value: String?, _ key: String) throws -> String {
        guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw CanonicalCapabilityExecutionError.missingParameter(key) }
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func subject(after prefixes: [String], in text: String) -> String? {
        prefixes.compactMap { prefix in text.range(of: prefix, options: [.caseInsensitive, .diacriticInsensitive]).map { String(text[$0.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines) } }.first
    }
}


struct SystemShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
