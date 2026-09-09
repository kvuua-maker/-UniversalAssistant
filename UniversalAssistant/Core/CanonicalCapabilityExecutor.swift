import Foundation
import MessageUI
import SwiftUI
import UIKit
import Contacts
import ContactsUI

enum DocumentScanOutputMode: String, Equatable, Sendable { case recognizedText, pdf }
enum PDFWorkflowOperation: String, Equatable, Sendable { case read, merge, split, rotate, compress, highlight, redact }

enum CapabilityPresentation: Equatable, Sendable, Identifiable {
    case camera
    case ocrCamera
    case ocrDocuments
    case scanDocument(DocumentScanOutputMode)
    case scanner
    case documents
    case share(String)
    case message(recipients: [String], body: String?)
    case email(recipients: [String], subject: String?, body: String?)
    case contactImport(Data)
    case contactAccess(query: String, command: StructuredCommand)
    case translationTarget(String)
    case translation(LocalTranslationPlan)
    case photoAsset(String)
    case photoOCR(String)
    case photoShare(String)
    case audioFile(URL)
    case documentFile(URL)
    case documentFiles([URL])
    case pdfWorkflow(PDFWorkflowOperation, text: String?)

    var id: String {
        switch self {
        case .camera: "camera"
        case .ocrCamera: "ocr-camera"
        case .ocrDocuments: "ocr-documents"
        case .scanDocument: "scan-document"
        case .scanner: "scanner"
        case .documents: "documents"
        case .share: "share"
        case .message: "message"
        case .email: "email"
        case .contactImport: "contact-import"
        case .contactAccess: "contact-access"
        case .translationTarget: "translation-target"
        case .translation: "translation"
        case .photoAsset: "photo-asset"
        case .photoOCR: "photo-ocr"
        case .photoShare: "photo-share"
        case .audioFile: "audio-file"
        case .documentFile: "document-file"
        case .documentFiles: "document-files"
        case .pdfWorkflow: "pdf-workflow"
        }
    }
}

enum CapabilityExecutionOutcome: Equatable, Sendable {
    case result(DeterministicResult)
    case handoff(WebHandoffResult)
    case presentation(CapabilityPresentation)
    case suspended(CapabilityPresentation, CanonicalCapabilityContinuation)
}

enum CanonicalDependencyOutput: Equatable, Sendable {
    case recognizedText(String)
    case selectedEntity(ContextEntity)
}

enum CanonicalDependencyBinder {
    static func bind(_ command: StructuredCommand, output: CanonicalDependencyOutput) throws -> StructuredCommand {
        var entities = command.entities
        switch output {
        case let .recognizedText(text):
            guard command.intent == .translation else {
                throw CanonicalCapabilityExecutionError.unavailable("dependency_output_type_mismatch")
            }
            entities["source_text"] = text
        case let .selectedEntity(entity):
            guard [.navigation, .routeSearch].contains(command.intent),
                  let latitude = entity.latitude, let longitude = entity.longitude else {
                throw CanonicalCapabilityExecutionError.unavailable("dependency_output_type_mismatch")
            }
            entities["destination"] = entity.displayName
            entities["destination_latitude"] = String(latitude)
            entities["destination_longitude"] = String(longitude)
        }
        return .init(id: command.id, originalText: command.originalText, normalizedText: command.normalizedText,
                     language: command.language, intent: command.intent, entities: entities,
                     constraints: command.constraints, risk: command.risk, needsClarification: false)
    }
}

struct CanonicalCapabilityContinuation: Equatable, Sendable {
    let remainingCommands: [StructuredCommand]

    func consuming(_ output: CanonicalDependencyOutput) throws -> [StructuredCommand] {
        guard let command = remainingCommands.first else { return [] }
        let first = try CanonicalDependencyBinder.bind(command, output: output)
        return [first] + remainingCommands.dropFirst()
    }
}

enum CanonicalCapabilityExecutionError: Error, Equatable, Sendable {
    case missingParameter(String)
    case ambiguous([String])
    case unavailable(String)
    case externalProviderRequired(String)
}

private enum PhotoSearchDeadlineResult: Sendable {
    case values([PhotoAssetReference])
    case timedOut
    case cancelled
}

private final class PhotoSearchDeadlineCompletion: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<PhotoSearchDeadlineResult, Never>?
    private var result: PhotoSearchDeadlineResult?

    func install(_ continuation: CheckedContinuation<PhotoSearchDeadlineResult, Never>) {
        lock.lock()
        if let result { lock.unlock(); continuation.resume(returning: result) }
        else { self.continuation = continuation; lock.unlock() }
    }

    func finish(_ result: PhotoSearchDeadlineResult) {
        lock.lock()
        guard self.result == nil else { lock.unlock(); return }
        self.result = result
        let continuation = continuation
        self.continuation = nil
        lock.unlock()
        continuation?.resume(returning: result)
    }
}

@MainActor
protocol CanonicalCapabilityExecuting: AnyObject {
    func execute(_ command: StructuredCommand) async throws -> CapabilityExecutionOutcome
    func resume(_ continuation: CanonicalCapabilityContinuation, with output: CanonicalDependencyOutput) async throws -> CapabilityExecutionOutcome
}

extension CanonicalCapabilityExecuting {
    func resume(_ continuation: CanonicalCapabilityContinuation, with output: CanonicalDependencyOutput) async throws -> CapabilityExecutionOutcome {
        throw CanonicalCapabilityExecutionError.unavailable("compound_continuation_unsupported")
    }
}

@MainActor
final class ProductionCanonicalCapabilityExecutor: CanonicalCapabilityExecuting {
    private let deviceRouter: UniversalDeviceCommandRouter
    private let contacts: any ContactResolving
    private let photos: any PhotoLibrarySearching
    private let photoSemanticLoader: any PhotoAssetImageLoading
    private let photoSemanticLabeler: any PhotoSemanticLabeling
    private let podcasts: ApplePodcastSearchProvider
    private let media: MediaIntegrationEngine?
    private let locationResolver: ManualLocationContextResolver
    private let placeSearch: PlaceSearchEngine
    private let navigation = NavigationHandoff()
    private let currentLocation: any CurrentLocationResolving
    private let personalSearch: UniversalPersonalSearchEngine
    private let currentContext: CurrentContextStore
    private let routeAwareSearch: RouteAwareSearchEngine
    private let routeProvider: any RouteProvider
    private let reverseLocation: any ReverseLocationGeocoding
    private var multiStep: ProductionMultiStepCoordinator
    private let multiStepOperationFactory: ProductionStepOperationFactory?
    private let recorder: AudioRecorderController
    private let eventKit: any EventKitCommandExecuting
    private let publicDeviceExecute: @MainActor (SystemQuickAction) throws -> String
    private let clipboardRead: @MainActor () throws -> SharedContent
    private let fx: any CurrentFXProviding
    private let photoSearchTimeout: Duration
    private let alarmExecute: ( (SystemQuickAction) async throws -> String)?

    init(
        deviceRouter: UniversalDeviceCommandRouter = .init(applications: .init(applications: LaunchDeviceApplications.verified)),
        contacts: any ContactResolving = LocalContactResolver(),
        photos: any PhotoLibrarySearching = PhotoKitLibrarySearch(),
        photoSemanticLoader: any PhotoAssetImageLoading = PhotoKitAssetImageLoader(),
        photoSemanticLabeler: any PhotoSemanticLabeling = VisionPhotoSemanticLabeler(),
        podcasts: ApplePodcastSearchProvider = .init(),
        mediaOverride: MediaIntegrationEngine? = nil,
        locationResolver: ManualLocationContextResolver = .init(),
        placeSearch: PlaceSearchEngine = .init(providers: [MapKitPlaceProvider()]),
        currentLocation: any CurrentLocationResolving = AppleCurrentLocationResolver(),
        reverseLocation: any ReverseLocationGeocoding = AppleReverseLocationGeocoder(),
        currentContext: CurrentContextStore = CurrentContextStore(),
        routeProvider: any RouteProvider = MapKitRouteProvider(),
        multiStepOperationFactory: ProductionStepOperationFactory? = nil,
        eventKit: any EventKitCommandExecuting = ProductionEventKitCommandExecutor(),
        recorder: AudioRecorderController = AudioRecorderController(),
        publicDeviceExecute: @escaping @MainActor (SystemQuickAction) throws -> String = { try ProductionPublicDeviceExecutor().execute($0) },
        clipboardRead: @escaping @MainActor () throws -> SharedContent = { try SystemUserInitiatedClipboardReader().readAfterUserAction() },
        fx: any CurrentFXProviding = ECBCurrentFXProvider(),
        alarmExecute: (  (SystemQuickAction) async throws -> String)? = nil,
        photoSearchTimeout: Duration = .seconds(3),
        personalSearchSources: [any PersonalSearchSource] = [ContactsPersonalSearchSource(), PhotosPersonalSearchSource(), LocalPersonalSearchSourceAdapter(source: AuthorizedFileSearchSource())]
    ) {
        self.deviceRouter = deviceRouter
        self.contacts = contacts
        self.photos = photos
        self.photoSemanticLoader = photoSemanticLoader
        self.photoSemanticLabeler = photoSemanticLabeler
        self.podcasts = podcasts
        self.locationResolver = locationResolver
        self.placeSearch = placeSearch
        self.currentLocation = currentLocation
        self.personalSearch = UniversalPersonalSearchEngine(sources: personalSearchSources)
        self.currentContext = currentContext
        self.routeAwareSearch = RouteAwareSearchEngine(routeProvider: routeProvider)
        self.routeProvider = routeProvider
        self.reverseLocation = reverseLocation
        self.eventKit = eventKit
        self.recorder = recorder
        self.publicDeviceExecute = publicDeviceExecute
        self.clipboardRead = clipboardRead
        self.fx = fx
        self.alarmExecute = alarmExecute
        self.photoSearchTimeout = photoSearchTimeout
        self.multiStepOperationFactory = multiStepOperationFactory
        if let multiStepOperationFactory {
            self.multiStep = ProductionMultiStepCoordinator(operationFactory: multiStepOperationFactory)
        } else {
            let operationMap = ProductionStepOperationMap(eventKit: eventKit, currentLocation: currentLocation, locationResolver: locationResolver, places: placeSearch, typedExecutor: nil)
            self.multiStep = ProductionMultiStepCoordinator { command, plan in
                operationMap.operations(for: command, plan: plan)
            }
        }
#if canImport(MusicKit)
        self.media = mediaOverride ?? MediaIntegrationEngine(adapters: [AppleMusicProviderAdapter()])
#else
        self.media = mediaOverride
#endif
        if multiStepOperationFactory == nil {
            let operationMap = ProductionStepOperationMap(eventKit: eventKit, currentLocation: currentLocation, locationResolver: locationResolver, places: placeSearch) { [weak self] subcommand, step in
                guard let self else { throw CanonicalCapabilityExecutionError.unavailable("multi_step_executor_released") }
                return try await self.executeTypedStep(subcommand, step: step)
            }
            self.multiStep = ProductionMultiStepCoordinator { command, plan in operationMap.operations(for: command, plan: plan) }
        }
    }

    func execute(_ command: StructuredCommand) async throws -> CapabilityExecutionOutcome {
        switch command.intent {
        case .open, .appAction:
            if command.constraints.ordinal != nil { return try await contextual(command, opensSelection: true) }
            return try await app(command)
        case .contactLookup:
            return try await contact(command, preparesCall: false)
        case .contactCall:
            if command.entities["contact"] == nil { return try await contextual(command, opensSelection: true) }
            return try await contact(command, preparesCall: true)
        case .messageCompose:
            return try await message(command)
        case .noteCreate:
            let value = try required(command.entities["content"] ?? subject(after: ["створи нову нотатку", "створи нотатку", "создай заметку", "create a note"], in: command.originalText), "note_content")
            let content = value.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: ":,-")))
            return .presentation(.share(try required(content, "note_content")))
        case .noteQuery:
            throw CanonicalCapabilityExecutionError.unavailable("notes_database_not_publicly_available")
        case .fileSearch:
            // iOS does not expose a public API for silently searching every Files provider.
            // The document picker is the system-owned, security-scoped production boundary.
            if let raw = command.entities["pdf_operation"], let operation = PDFWorkflowOperation(rawValue: raw) {
                return .presentation(.pdfWorkflow(operation, text: command.entities["pdf_text"]))
            }
            return .presentation(.documents)
        case .cameraCapture:
            if command.entities["capture_mode"] == "code_scan" { return .presentation(.scanner) }
            if command.entities["capture_mode"] == "text_scan" {
                if command.entities["input_source"] == "document_camera" {
                    let mode: DocumentScanOutputMode = command.entities["output_format"] == "pdf" ? .pdf : .recognizedText
                    return .presentation(.scanDocument(mode))
                }
                return .presentation(command.entities["input_source"] == "document" ? .ocrDocuments : .ocrCamera)
            }
            return .presentation(.camera)
        case .translation:
            let text = try required(command.entities["source_text"], "translation_source_text")
            let target = try required(command.entities["target_language"], "translation_target_language")
            let source = command.entities["source_language"] ?? TranslationSourceLanguageResolver().resolve(text)
            return .presentation(.translation(try CameraIntelligenceCore().translationPlan(text: text, sourceLanguage: source, targetLanguage: target)))
        case .photoSearch:
            return try await photo(command)
        case .podcastSearch:
            let query = try required(command.entities["query"], "podcast_query")
            let values = try await podcasts.search(query, limit: 3, country: Locale.current.region?.identifier ?? "UA")
            return .result(try result("Знайдено подкасти", facts: values.enumerated().map { index, item in
                ResultFact(id: item.id, label: item.title, value: item.show ?? "Podcast", state: .verified, source: "Apple Podcasts", observedAt: .now, priority: 100 - index)
            }, actions: values.map { .init(id: $0.id, title: "Відкрити", kind: .open, destination: $0.exactURL) }))
        case .musicRecognition:
            return .result(try result(musicRecognitionAvailabilityMessage(for: command.language), facts: []))
        case .mediaSearch:
            let requestedApp = command.entities["app"]?.lowercased()
            if requestedApp == "spotify" {
                // Spotify documents its iOS app scheme for app detection/opening.
                // Catalog item discovery itself requires a registered Web API app
                // and OAuth; do not silently execute this query in Apple Music.
                guard let url = URL(string: "spotify:") else {
                    throw CanonicalCapabilityExecutionError.unavailable("spotify_handoff_invalid")
                }
                return .handoff(.init(query: command.originalText, destination: url, kind: .system))
            }
            if requestedApp == "youtube" {
                guard let url = URL(string: "https://www.youtube.com") else {
                    throw CanonicalCapabilityExecutionError.unavailable("youtube_handoff_invalid")
                }
                return .handoff(.init(query: command.originalText, destination: url, kind: .system))
            }
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
            guard command.entities["settings_target"] == "application" else {
                throw CanonicalCapabilityExecutionError.unavailable("system_settings_destination_not_publicly_available")
            }
            guard let url = URL(string: UIApplication.openSettingsURLString) else {
                throw CanonicalCapabilityExecutionError.unavailable("app_settings_unavailable")
            }
            return .handoff(.init(query: command.originalText, destination: url, kind: .system))
        case .help:
            return .result(try result("Скажіть або введіть, що потрібно зробити", facts: []))
        case .localUtility:
            let value = try LocalUtilityEngine().execute(command.originalText, locale: Locale(identifier: command.language == .ru ? "ru_RU" : "uk_UA"), timeZone: .autoupdatingCurrent, now: .now)
            return .result(try result(value, facts: []))
        case .currencyConversion:
            guard let request = FXConversionRequestParser().parse(command.originalText) else {
                throw CanonicalCapabilityExecutionError.missingParameter("currency_conversion")
            }
            do {
                let conversion = try await fx.convert(request)
                let formatted = conversion.convertedAmount.formatted(.number.precision(.fractionLength(0...4)))
                let fact = ResultFact(id: "fx", label: "\(request.source) → \(request.destination)", value: "\(formatted) \(request.destination)", state: .verified, source: conversion.provider, observedAt: conversion.observedAt, priority: 100)
                return .result(try result("\(formatted) \(request.destination)", facts: [fact]))
            } catch CurrentFXError.unsupportedCurrency {
                throw CanonicalCapabilityExecutionError.externalProviderRequired("current_fx_rate_for_currency")
            }
        case .show, .contextualSelection:
            return try await contextual(command, opensSelection: command.normalizedText.contains("відк") || command.normalizedText.contains("откр") || command.normalizedText.contains("open"))
        case .cancel:
            return .result(try result("Скасовано", facts: []))
        case .transportRoute:
            return try await route(command, mode: .transit)
        case .productSearch, .fashionDiscovery, .groceryBasket, .serviceSearch, .restaurantSearch,
             .reservation, .taxiSearch, .taxiCompare, .publicTransport,
             .ticketSearch, .ticketPurchaseHandoff, .hotelSearch, .travelPlan, .parcelTrack:
            throw CanonicalCapabilityExecutionError.externalProviderRequired(command.intent.rawValue)
        case .placeSearch:
            return try await places(command)
        case .navigation, .routeSearch:
            if command.entities["destination"] == nil { return try await contextual(command, opensSelection: true) }
            return try await route(command)
        case .routeAwareSearch:
            return try await routeAware(command)
        case .multiStep:
            return try await executeCompound(command)
        case .reminderComplete, .reminderDelete, .shoppingList, .undo:
            throw CanonicalCapabilityExecutionError.unavailable("canonical_mutation_context_required")
        case .calendarUpdate:
            return try await contextualReschedule(command)
        case .deviceAction:
            return try await systemQuickAction(command)
        case .calendarCreate, .calendarQuery, .calendarDelete, .reminderCreate,
             .reminderQuery, .weather, .webSearch, .deviceAction, .audioRecord, .unknown:
            throw CanonicalCapabilityExecutionError.unavailable("handled_by_specialized_executor")
        }
    }

    private func executeCompound(_ command: StructuredCommand) async throws -> CapabilityExecutionOutcome {
        let plan = try DeterministicExecutionPlanBuilder().plan(for: command)
        let commands = plan.steps.compactMap(\.command)
        guard commands.count == plan.steps.count, !commands.isEmpty else {
            return .result(try await multiStep.execute(command))
        }
        return try await executeCompound(commands, aggregate: [], dependencyOutput: nil)
    }

    func resume(_ continuation: CanonicalCapabilityContinuation, with output: CanonicalDependencyOutput) async throws -> CapabilityExecutionOutcome {
        try await executeCompound(continuation.consuming(output), aggregate: [], dependencyOutput: nil)
    }

    private func executeCompound(_ commands: [StructuredCommand], aggregate: [ResultFact], dependencyOutput: CanonicalDependencyOutput?) async throws -> CapabilityExecutionOutcome {
        guard var command = commands.first else {
            return .result(try result("Виконано", facts: aggregate))
        }
        if let dependencyOutput { command = try CanonicalDependencyBinder.bind(command, output: dependencyOutput) }
        let outcome = try await execute(command)
        let remaining = Array(commands.dropFirst())
        switch outcome {
        case let .result(value):
            let fact = ResultFact(id: command.id.uuidString, label: value.primaryAnswer, value: value.primaryAnswer,
                                  state: .verified, source: "UniversalAssistant", observedAt: .now, priority: 100 - aggregate.count)
            if remaining.isEmpty { return .result(value) }
            let output: CanonicalDependencyOutput? = [.placeSearch, .restaurantSearch, .serviceSearch].contains(command.intent)
                ? currentContext.selectFirstResult().map(CanonicalDependencyOutput.selectedEntity)
                : nil
            return try await executeCompound(remaining, aggregate: aggregate + [fact], dependencyOutput: output)
        case let .handoff(value):
            if remaining.isEmpty { return .handoff(value) }
            let fact = ResultFact(id: command.id.uuidString, label: command.intent.rawValue, value: value.destination.absoluteString,
                                  state: .verified, source: "UniversalAssistant", observedAt: .now, priority: 100 - aggregate.count)
            return try await executeCompound(remaining, aggregate: aggregate + [fact], dependencyOutput: nil)
        case let .presentation(presentation):
            return remaining.isEmpty ? .presentation(presentation) : .suspended(presentation, .init(remainingCommands: remaining))
        case .suspended:
            throw CanonicalCapabilityExecutionError.unavailable("nested_compound_continuation")
        }
    }

    private func executeTypedStep(_ command: StructuredCommand, step: ExecutionPlanStep) async throws -> ResultFact {
        if [.calendarCreate, .calendarQuery, .calendarUpdate, .calendarDelete, .reminderCreate, .reminderQuery, .reminderComplete, .reminderDelete, .shoppingList, .undo].contains(command.intent) {
            let value = try await eventKit.execute(command)
            return .init(id: step.id, label: command.intent.rawValue, value: value.title + ": " + value.detail, state: .verified, source: "EventKit", observedAt: .now, priority: 100)
        }
        if command.intent == .audioRecord {
            let action = AudioRecorderCommand(rawValue: command.entities["recorder_action"] ?? "start") ?? .start
            await recorder.execute(action)
            guard recorder.state != .failed && recorder.state != .denied else { throw CanonicalCapabilityExecutionError.unavailable("recorder_unavailable") }
            return .init(id: step.id, label: command.intent.rawValue, value: String(describing: recorder.state), state: .verified, source: "AudioRecorderController", observedAt: .now, priority: 100)
        }
        if [.navigation, .routeSearch].contains(command.intent), command.entities["destination"] == nil {
            guard currentContext.selectFirstResult() != nil, let destination = currentContext.consumeSelectedAction(), destination.host == "maps.apple.com" else {
                throw CanonicalCapabilityExecutionError.missingParameter("resolved_place_destination")
            }
            return .init(id: step.id, label: command.intent.rawValue, value: destination.absoluteString, state: .verified, source: "MapKit", observedAt: .now, priority: 100)
        }
        let outcome = try await execute(command)
        switch outcome {
        case let .result(value): return .init(id: step.id, label: command.intent.rawValue, value: value.primaryAnswer, state: .verified, source: "UniversalAssistant", observedAt: .now, priority: 100)
        case let .handoff(value): return .init(id: step.id, label: command.intent.rawValue, value: value.destination.absoluteString, state: .verified, source: "UniversalAssistant", observedAt: .now, priority: 100)
        case let .presentation(value):
            switch value {
            case .message, .email, .share, .documents, .contactImport, .photoAsset, .photoOCR, .photoShare, .audioFile, .documentFile, .documentFiles:
                return .init(id: step.id, label: command.intent.rawValue, value: value.id, state: .verified, source: "UniversalAssistant", observedAt: .now, priority: 100)
            case .camera, .ocrCamera, .ocrDocuments, .scanDocument, .scanner, .contactAccess, .translationTarget, .translation, .pdfWorkflow:
                throw CoordinationOperationError.confirmationRequired
            }
        case .suspended:
            throw CoordinationOperationError.confirmationRequired

        }
    }

    private func systemQuickAction(_ command: StructuredCommand) async throws -> CapabilityExecutionOutcome {
        let kind = command.entities["system_action"] ?? ""
        if kind == "clipboard_read" {
            switch try clipboardRead() {
            case let .url(url): return .result(try result(url.absoluteString, facts: []))
            case let .text(value): return .result(try result(value, facts: []))
            default: throw CanonicalCapabilityExecutionError.unavailable("clipboard_content_unsupported")
            }
        }
        if kind == "clipboard_open_url" {
            let content = try clipboardRead()
            let url: URL?
            switch content { case let .url(value): url = value; case let .text(value): url = URL(string: value.trimmingCharacters(in: .whitespacesAndNewlines)); default: url = nil }
            guard let url, ["http", "https"].contains(url.scheme?.lowercased() ?? ""), url.host != nil else { throw CanonicalCapabilityExecutionError.unavailable("clipboard_url_invalid") }
            return .handoff(.init(query: url.host ?? url.absoluteString, destination: url, kind: .system))
        }
        if kind == "clipboard_copy_context" {
            guard let value = currentContext.freshAnswer() else { throw CanonicalCapabilityExecutionError.missingParameter("current_result") }
            return .result(try result(try publicDeviceExecute(.copyToClipboard(value)), facts: []))
        }
        if kind == "share_context" {
            guard let value = currentContext.freshAnswer() else { throw CanonicalCapabilityExecutionError.missingParameter("current_result") }
            return .presentation(.share(value))
        }
        if kind == "current_location" {
            let location = try await currentLocation.resolveCurrent(for: .general)
            let coordinates = String(format: "%.5f, %.5f", location.sample.latitude, location.sample.longitude)
            return .result(try result("Поточне місцезнаходження", facts: [.init(id: "current-location", label: "Координати", value: coordinates, state: .verified, source: "CoreLocation", observedAt: location.sample.timestamp, priority: 100)]))
        }
        if kind == "current_locality" {
            let location = try await currentLocation.resolveCurrent(for: .general)
            let locality = try await reverseLocation.locality(for: location)
            return .result(try result(locality, facts: [.init(id: "current-locality", label: "Поточне місто", value: locality, state: .verified, source: "CoreLocation", observedAt: location.sample.timestamp, priority: 100)]))
        }
        if kind == "current_address" {
            let location = try await currentLocation.resolveCurrent(for: .general)
            let address = try await reverseLocation.address(for: location)
            return .result(try result(address, facts: [.init(id: "current-address", label: "Поточна адреса", value: address, state: .verified, source: "CoreLocation", observedAt: location.sample.timestamp, priority: 100)]))
        }
        if kind == "travel_time" {
            let destinationName = try required(command.entities["destination"], "destination")
            let origin = try await currentLocation.resolveCurrent(for: .navigation)
            let destination = try await locationResolver.resolve(destinationName)
            let mode: TravelMode = ["пішки", "пешком", "walking", "walk"].contains(where: command.normalizedText.contains) ? .walking : .driving
            let route = try await routeProvider.route(.init(origin: .init(latitude: origin.sample.latitude, longitude: origin.sample.longitude, name: "current location"), destination: .init(latitude: destination.sample.latitude, longitude: destination.sample.longitude, name: destinationName), mode: mode))
            let minutes = max(1, Int((route.expectedTravelTime / 60).rounded()))
            currentContext.replaceRoute(origin: origin, destination: destination, destinationName: destinationName)
            return .result(try result("Приблизно \(minutes) хв", facts: [.init(id: "travel-time", label: destinationName, value: "\(minutes) хв", state: .verified, source: route.source, observedAt: route.timestamp, priority: 100)]))
        }
        if kind == "unsupported_system_control" { throw CanonicalCapabilityExecutionError.unavailable("system_control_not_publicly_available") }
        let action: SystemQuickAction
        if kind == "timer", let seconds = Int(command.entities["duration_seconds"] ?? "") { action = .startTimer(seconds: seconds, label: command.entities["label"]) }
        else if kind == "alarm", let hour = Int(command.entities["hour"] ?? ""), let minute = Int(command.entities["minute"] ?? "") { action = .createAlarm(hour: hour, minute: minute, label: command.entities["label"]) }
        else if kind == "flashlight" { action = .flashlight(enabled: command.entities["enabled"] != "false") }
        else if kind == "battery" { action = .batteryLevel }
        else if kind == "storage" { action = .freeStorage }
        else if kind == "clipboard", let content = command.entities["content"], !content.isEmpty { action = .copyToClipboard(content) }
        else if !kind.isEmpty { throw CanonicalCapabilityExecutionError.unavailable("system_action_missing_value") }
        else { throw CanonicalCapabilityExecutionError.missingParameter("system_action") }

        switch action {
        case .startTimer, .createAlarm:
            if let alarmExecute {
                do { return .result(try result(try await alarmExecute(action), facts: [])) }
                catch { throw CanonicalCapabilityExecutionError.unavailable("alarmkit_execution_failed") }
            }
            guard #available(iOS 26.0, *) else { throw CanonicalCapabilityExecutionError.unavailable("alarmkit_requires_ios_26") }
            #if canImport(AlarmKit)
            do { return .result(try result(try await ProductionAlarmKitExecutor().execute(action), facts: [])) }
            catch ProductionAlarmKitExecutor.ExecutionError.denied { throw CanonicalCapabilityExecutionError.unavailable("alarmkit_permission_denied") }
            catch { throw CanonicalCapabilityExecutionError.unavailable("alarmkit_execution_failed") }
            #else
            throw CanonicalCapabilityExecutionError.unavailable("alarmkit_unavailable")
            #endif
        default:
            do { return .result(try result(try publicDeviceExecute(action), facts: [])) }
            catch { throw CanonicalCapabilityExecutionError.unavailable("public_system_action_unavailable") }
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
        let searchText = placeSearchText(for: command, category: category)
        let response = try await placeSearch.search(.init(text: searchText, category: category, location: location, limit: 5))
        let nearestRequested = ["найближ", "ближайш", "nearest", "closest"].contains(where: command.normalizedText.contains)
        let places = nearestRequested ? PlaceProximityOrdering().nearestFirst(response.places, from: location) : response.places
        guard !places.isEmpty else { throw CanonicalCapabilityExecutionError.unavailable("no_places_found") }
        let output = try result("Знайдено місця", facts: places.prefix(5).enumerated().map { index, place in
            ResultFact(id: place.id, label: place.name, value: place.address ?? place.category.rawValue, state: .verified, source: place.source, observedAt: place.timestamp, priority: 100 - index)
        }, actions: places.prefix(5).compactMap { place in
            guard let destination = try? navigation.url(provider: .appleMaps, destination: .init(latitude: place.latitude, longitude: place.longitude, name: place.name), mode: .walking) else { return nil }
            return ResultAction(id: place.id, title: "Маршрут", kind: .open, destination: destination)
        })
        currentContext.replacePlaceResults(output, places: Array(places.prefix(5)))
        return .result(output)
    }

    private func route(_ command: StructuredCommand, mode: TravelMode = .driving) async throws -> CapabilityExecutionOutcome {
        let destinationName = try required(command.entities["destination"], "destination")
        let destination: ValidatedLocation
        if let latitude = command.entities["destination_latitude"].flatMap(Double.init),
           let longitude = command.entities["destination_longitude"].flatMap(Double.init) {
            destination = .init(sample: .init(latitude: latitude, longitude: longitude, horizontalAccuracy: 0,
                                              timestamp: .now, speed: -1, course: -1, source: .manual),
                                quality: .precise, isSafeForLocationActions: true, manualLabel: destinationName)
        } else {
            destination = try await locationResolver.resolve(destinationName)
        }
        if let origin = try? await currentLocation.resolveCurrent(for: .navigation) { currentContext.replaceRoute(origin: origin, destination: destination, destinationName: destinationName) }
        let url = try navigation.url(provider: .appleMaps, destination: .init(latitude: destination.sample.latitude, longitude: destination.sample.longitude, name: destinationName), mode: mode)
        return .handoff(.init(query: command.originalText, destination: url, kind: .navigation))
    }

    private func routeAware(_ command: StructuredCommand) async throws -> CapabilityExecutionOutcome {
        guard let (origin, route) = currentContext.freshRoute(), let latitude = route.destination.latitude, let longitude = route.destination.longitude else { throw CanonicalCapabilityExecutionError.missingParameter("active_route_context") }
        let location = ValidatedLocation(sample: .init(latitude: origin.latitude, longitude: origin.longitude, horizontalAccuracy: origin.horizontalAccuracyMeters, timestamp: route.provenance.observedAt, speed: -1, course: -1, source: .device), quality: .good, isSafeForLocationActions: true, manualLabel: nil)
        let category = placeCategory(in: command.normalizedText)
        let response = try await placeSearch.search(.init(text: placeSearchText(for: command, category: category), category: category, location: location, limit: 8))
        let values = try await routeAwareSearch.evaluate(origin: .init(latitude: origin.latitude, longitude: origin.longitude, name: "origin"), destination: .init(latitude: latitude, longitude: longitude, name: route.destination.displayName), candidates: response.places, mode: .driving)
        guard !values.isEmpty else { throw CanonicalCapabilityExecutionError.unavailable("no_route_aware_places") }
        return .result(try result("Знайдено по дорозі", facts: values.prefix(3).enumerated().map { index, value in ResultFact(id: value.place.id, label: value.place.name, value: "\(Int(value.detourSeconds * 0.0166667)) хв відхилення", state: .verified, source: value.place.source, observedAt: value.place.timestamp, priority: 100 - index) }, actions: values.prefix(3).compactMap { value in try? ResultAction(id: value.place.id, title: "Маршрут", kind: .open, destination: navigation.url(provider: .appleMaps, destination: .init(latitude: value.place.latitude, longitude: value.place.longitude, name: value.place.name), mode: .driving)) }))
    }

    private func app(_ command: StructuredCommand) async throws -> CapabilityExecutionOutcome {
        if let rawURL = command.entities["direct_url"], let url = URL(string: rawURL), ["http", "https"].contains(url.scheme?.lowercased() ?? ""), url.host != nil {
            return .handoff(.init(query: url.host ?? rawURL, destination: url, kind: .system))
        }
        let target = (command.entities["app"] ?? "").folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        if ["файли", "файлы", "files"].contains(target) { return .presentation(.documents) }
        if ["камера", "camera"].contains(target) { return .presentation(.camera) }
        if ["календар", "календарь", "calendar"].contains(target) {
            let query = StructuredCommand(originalText: command.originalText, normalizedText: command.normalizedText, language: command.language, intent: .calendarQuery)
            let value = try await eventKit.execute(query)
            return .result(try result(value.title, facts: [.init(id: command.id.uuidString, label: value.title, value: value.detail, state: .verified, source: "EventKit", observedAt: .now, priority: 100)]))
        }
        switch deviceRouter.route(command) {
        case let .deviceApplication(_, destination, _): return .handoff(.init(query: command.originalText, destination: destination, kind: .system))
        case let .clarification(values): throw CanonicalCapabilityExecutionError.ambiguous(values)
        case let .unsupported(reason): throw CanonicalCapabilityExecutionError.unavailable(reason)
        default: throw CanonicalCapabilityExecutionError.unavailable("unsupported_app_route")
        }
    }

    private func boundedPhotoSearch(_ criteria: PhotoSearchCriteria, limit: Int) async throws -> [PhotoAssetReference] {
        let completion = PhotoSearchDeadlineCompletion()
        let result = await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                completion.install(continuation)
                Task { [photos] in completion.finish(.values(await photos.search(criteria, limit: limit))) }
                Task { [photoSearchTimeout] in
                    try? await Task.sleep(for: photoSearchTimeout)
                    completion.finish(.timedOut)
                }
            }
        } onCancel: {
            completion.finish(.cancelled)
        }
        switch result {
        case let .values(values): return values
        case .timedOut: throw CanonicalCapabilityExecutionError.unavailable("photos_search_timeout")
        case .cancelled: throw CancellationError()
        }
    }

    private func photo(_ command: StructuredCommand) async throws -> CapabilityExecutionOutcome {
        let query = command.entities["query"] ?? ""
        let latest = query.isEmpty || query == "latest" || query == "recent"
        let access = photos.authorization() == .permissionRequired ? await photos.requestAuthorization() : photos.authorization()
        guard access == .permitted || access == .limited else { throw CanonicalCapabilityExecutionError.unavailable("photos_access_unavailable") }
        let recentIndex = max(0, (command.constraints.ordinal ?? 1) - 1)
        let assets = try await boundedPhotoSearch(.init(), limit: latest ? recentIndex + 1 : 20)
        guard !assets.isEmpty else { throw CanonicalCapabilityExecutionError.unavailable("photos_empty") }
        if latest {
            guard assets.indices.contains(recentIndex) else { throw CanonicalCapabilityExecutionError.unavailable("photos_ordinal_unavailable") }
            let selected = assets[recentIndex]
            let action = ResultAction(id: "photos:" + selected.localIdentifier, title: "Відкрити", kind: .showPhoto, destination: nil)
            let output = try result(recentIndex == 0 ? "Найновіше фото" : "Вибране недавнє фото", facts: [.init(id: action.id, label: "Фото", value: selected.creationDate?.formatted(), state: .verified, source: "Photos", observedAt: selected.creationDate ?? .now, priority: 100)], actions: [action])
            currentContext.replacePhotoResults(output)
            switch command.entities["requested_action"] {
            case "open": return .presentation(.photoAsset(selected.localIdentifier))
            case "ocr": return .presentation(.photoOCR(selected.localIdentifier))
            case "share": return .presentation(.photoShare(selected.localIdentifier))
            default: break
            }
            return .result(output)
        }
        let response = await PhotosPersonalSearchSource(library: photos, loader: photoSemanticLoader, labeler: photoSemanticLabeler).search(query: query, limit: 5)
        guard !response.results.isEmpty else { throw CanonicalCapabilityExecutionError.unavailable("photos_no_semantic_match") }
        let facts = response.results.enumerated().map { index, value in
            ResultFact(id: value.id, label: value.title, value: value.subtitle ?? value.sourceObjectID, state: .verified, source: "Photos", observedAt: .now, priority: 100 - index)
        }
        let actions = response.results.map { ResultAction(id: $0.id, title: "Відкрити", kind: .showPhoto, destination: nil) }
        let output = try result("Знайдено у Фото", facts: facts, actions: actions)
        currentContext.replacePhotoResults(output)
        if let first = response.results.first {
            switch command.entities["requested_action"] {
            case "open": return .presentation(.photoAsset(first.sourceObjectID))
            case "ocr": return .presentation(.photoOCR(first.sourceObjectID))
            case "share": return .presentation(.photoShare(first.sourceObjectID))
            default: break
            }
        }
        return .result(output)
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
        let output = try result("Знайдено на iPhone", facts: facts, actions: actions)
        currentContext.replaceResults(output); return .result(output)
    }

    private func contextual(_ command: StructuredCommand, opensSelection: Bool) async throws -> CapabilityExecutionOutcome {
        let selected = command.constraints.ordinal != nil ? currentContext.select(command) : currentContext.freshSelected()
        guard let selected else { throw CanonicalCapabilityExecutionError.missingParameter("active_result_context") }
        if command.intent == .contactCall {
            if selected.phoneNumber != nil {
                guard let destination = currentContext.consumeSelectedAction() else { throw CanonicalCapabilityExecutionError.unavailable("context_action_unavailable_or_replayed") }
                return .handoff(.init(query: selected.displayName, destination: destination, kind: .system))
            }
            let followUp = StructuredCommand(originalText: command.originalText, normalizedText: command.normalizedText, language: command.language, intent: .contactCall, entities: ["contact": selected.displayName])
            return try await contact(followUp, preparesCall: true)
        }
        if opensSelection {
            guard let destination = currentContext.consumeSelectedAction() else { throw CanonicalCapabilityExecutionError.unavailable("context_action_unavailable_or_replayed") }
            return .handoff(.init(query: selected.displayName, destination: destination, kind: .system))
        }
        return .result(try result(selected.displayName, facts: [.init(id: selected.id, label: selected.displayName, value: selected.kind.rawValue, state: .verified, source: selected.provenance.source, observedAt: selected.provenance.observedAt, priority: 100)]))
    }

    private func contextualReschedule(_ command: StructuredCommand) async throws -> CapabilityExecutionOutcome {
        var entities = command.entities
        if let selected = currentContext.freshSelected() { entities["selected_item_id"] = selected.id; entities["subject"] = selected.displayName }
        let resolved = StructuredCommand(id: command.id, originalText: command.originalText, normalizedText: command.normalizedText, language: command.language, intent: .calendarUpdate, entities: entities, constraints: command.constraints, risk: command.risk, needsClarification: command.needsClarification)
        let value = try await eventKit.execute(resolved)
        return .result(try result(value.title, facts: [.init(id: entities["selected_item_id"] ?? command.id.uuidString, label: value.title, value: value.detail, state: .verified, source: "EventKit", observedAt: .now, priority: 100)]))
    }

    private func personalSourceName(_ source: PersonalSearchSourceID) -> String {
        switch source { case let .local(kind): return kind.rawValue; case let .connectedEmail(value), let .connectedService(value): return value }
    }
    private func personalObservedAt(_ freshness: PersonalSearchFreshness) -> Date {
        switch freshness { case let .live(date), let .cached(date): return date; case .local, .unknown: return .now }
    }

    private func contact(_ command: StructuredCommand, preparesCall: Bool) async throws -> CapabilityExecutionOutcome {
        let requestedService = command.entities["call_service"]
        if preparesCall, let rawNumber = command.entities["phone_number"] {
            return .handoff(.init(query: rawNumber, destination: try callDestination(number: rawNumber, service: requestedService), kind: .system))
        }
        let name = try required(command.entities["contact"], "contact_name")
        try await contacts.requestAccessIfNeeded()
        let resolution: ContactResolution
        if let identifier = command.entities["contact_identifier"] {
            resolution = try await contacts.resolve(exactIdentifier: identifier)
        } else {
            resolution = try await contacts.resolve(name: name)
        }
        switch resolution {
        case .notFound:
            if await contacts.authorizationState() == .limited, command.entities["contact_identifier"] == nil {
                return .presentation(.contactAccess(query: name, command: command))
            }
            throw CanonicalCapabilityExecutionError.unavailable("contact_not_found")
        case let .ambiguous(values): throw CanonicalCapabilityExecutionError.ambiguous(values.map(\.displayName))
        case let .resolved(value):
            if preparesCall {
                guard !value.phoneNumbers.isEmpty else {
                    throw CanonicalCapabilityExecutionError.unavailable("contact_has_no_phone_number")
                }
                guard value.phoneNumbers.count == 1, let number = value.phoneNumbers.first else {
                    throw CanonicalCapabilityExecutionError.ambiguous(value.phoneNumbers)
                }
                return .handoff(.init(query: value.displayName, destination: try callDestination(number: number, service: requestedService), kind: .system))
            }
            let facts = value.phoneNumbers.enumerated().map { index, number in
                ResultFact(id: "phone-\(index)", label: value.displayName, value: number, state: .verified, source: "Contacts", observedAt: .now, priority: 100 - index)
            }
            let actions = try value.phoneNumbers.enumerated().map { index, number in
                ResultAction(id: "phone-\(index)", title: "Подзвонити", kind: .open, destination: try callDestination(number: number, service: nil))
            }
            let output = try result(value.displayName, facts: facts, actions: actions)
            currentContext.replaceResults(output)
            return .result(output)
        }
    }

    private func message(_ command: StructuredCommand) async throws -> CapabilityExecutionOutcome {
        let service = command.entities["message_service"]?.lowercased()
        let body = command.entities["message_body"]
        if service == "email" || service == "mail" {
            let rawRecipient = command.entities["recipient"]?.trimmingCharacters(in: .whitespacesAndNewlines)
            let recipients: [String]
            if let rawRecipient, !rawRecipient.isEmpty, rawRecipient.contains("@") {
                recipients = [rawRecipient]
            } else {
                recipients = []
            }
            return .presentation(.email(recipients: recipients, subject: command.entities["message_subject"], body: body))
        }
        guard let rawRecipient = command.entities["recipient"]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !rawRecipient.isEmpty else {
            guard service == nil || service == "messages" else {
                throw CanonicalCapabilityExecutionError.missingParameter("message_recipient")
            }
            return .presentation(.message(recipients: [], body: body))
        }

        let directDigits = rawRecipient.filter(\.isNumber)
        let phoneNumber: String
        if directDigits.count >= 7 {
            phoneNumber = rawRecipient
        } else {
            try await contacts.requestAccessIfNeeded()
            switch try await contacts.resolve(name: rawRecipient) {
            case .notFound:
                throw CanonicalCapabilityExecutionError.unavailable("message_contact_not_found")
            case let .ambiguous(values):
                throw CanonicalCapabilityExecutionError.ambiguous(values.map(\.displayName))
            case let .resolved(value):
                guard value.phoneNumbers.count == 1, let number = value.phoneNumbers.first else {
                    throw CanonicalCapabilityExecutionError.ambiguous(value.phoneNumbers)
                }
                phoneNumber = number
            }
        }

        let messenger: MessengerKind
        switch service {
        case nil, "messages": messenger = .messages
        case "whatsapp": messenger = .whatsapp
        case "telegram": messenger = .telegram
        case "viber": messenger = .viber
        case "signal": messenger = .signal
        default: throw CanonicalCapabilityExecutionError.unavailable("unsupported_message_service")
        }
        switch try MessengerHandoffPlanner().plan(messenger: messenger, recipient: phoneNumber, body: body) {
        case let .systemComposer(recipients, body):
            return .presentation(.message(recipients: recipients, body: body))
        case let .verifiedHandoff(url):
            return .handoff(.init(query: command.originalText, destination: url, kind: .system))
        case let .unavailable(reason):
            throw CanonicalCapabilityExecutionError.unavailable(reason)
        }
    }

    private func callDestination(number: String, service: String?) throws -> URL {
        let digits = number.filter(\.isNumber)
        guard digits.count >= 7 else { throw CanonicalCapabilityExecutionError.unavailable("invalid_phone_number") }
        if service == "whatsapp" {
            guard let url = URL(string: "https://wa.me/\(digits)") else { throw CanonicalCapabilityExecutionError.unavailable("invalid_whatsapp_handoff") }
            return url
        }
        guard let url = URL(string: "tel:\(number.hasPrefix("+") ? "+" : "")\(digits)") else { throw CanonicalCapabilityExecutionError.unavailable("invalid_phone_handoff") }
        return url
    }

    private func result(_ answer: String, facts: [ResultFact], actions: [ResultAction] = []) throws -> DeterministicResult {
        try DeterministicResultComposer().compose(primaryAnswer: answer, facts: facts, actions: actions)
    }

    private func placeCategory(in text: String) -> PlaceCategory? {
        if ["кав", "кафе", "кофе", "coffee", "cafe"].contains(where: text.contains) { return .cafe }
        if ["ресторан", "restaurant"].contains(where: text.contains) { return .restaurant }
        if ["супермаркет", "supermarket", "grocer"].contains(where: text.contains) { return .supermarket }
        if ["аптек", "pharmacy", "drugstore"].contains(where: text.contains) { return .pharmacy }
        if ["заправ", "азс", "fuel", "gas station", "petrol"].contains(where: text.contains) { return .fuel }
        if ["магазин", "store", "shop"].contains(where: text.contains) { return .shop }
        return nil
    }

    private func placeSearchText(for command: StructuredCommand, category: PlaceCategory?) -> String {
        if let explicit = command.entities["serviceCategory"]?.trimmingCharacters(in: .whitespacesAndNewlines), !explicit.isEmpty { return explicit }
        switch category {
        case .cafe: return "coffee"
        case .restaurant: return "restaurant"
        case .supermarket: return "supermarket"
        case .pharmacy: return "pharmacy"
        case .fuel: return "gas station"
        case .shop: return command.entities["query"] ?? command.entities["brand"] ?? "shop"
        default: return command.entities["query"] ?? command.originalText
        }
    }

    private func musicRecognitionAvailabilityMessage(for language: CommandLanguage) -> String {
        switch language {
        case .uk: "Розпізнавання музики потребує авторизованої для цього застосунку ShazamKit capability."
        case .ru: "Распознавание музыки требует авторизованной для этого приложения ShazamKit capability."
        case .de: "Die Musikerkennung benötigt eine für diese App autorisierte ShazamKit-Funktion."
        case .fr: "La reconnaissance musicale nécessite une capacité ShazamKit autorisée pour cette app."
        default: "Music recognition requires a ShazamKit capability authorized for this app."
        }
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
