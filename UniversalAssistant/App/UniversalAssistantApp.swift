import SwiftUI

/// Single composition root used by the shipped app and Production-configuration E2E.
/// Tests may replace only an external side-effect boundary; parser, router, context,
/// executor graph and rendering lifecycle remain identical to Release.
@MainActor
enum ProductionAssistantComposition {
    static func makeModel(
        contacts: any ContactResolving = LocalContactResolver(),
        photos: any PhotoLibrarySearching = PhotoKitLibrarySearch(),
        locationResolver: ManualLocationContextResolver = .init(),
        placeSearch: PlaceSearchEngine = .init(providers: [MapKitPlaceProvider()]),
        currentLocation: any CurrentLocationResolving = AppleCurrentLocationResolver(),
        reverseLocation: any ReverseLocationGeocoding = AppleReverseLocationGeocoder(),
        routeProvider: any RouteProvider = MapKitRouteProvider(),
        recorder: AudioRecorderController = AudioRecorderController(),
        personalSearchSources: [any PersonalSearchSource] = [
            ContactsPersonalSearchSource(), PhotosPersonalSearchSource(),
            LocalPersonalSearchSourceAdapter(source: AuthorizedFileSearchSource())
        ],
        compactResultDuration: Duration = .seconds(2),
        weather: any WeatherCommandExecuting = ProductionWeatherCommandExecutor(),
        eventKit: any EventKitCommandExecuting = ProductionEventKitCommandExecutor(),
        publicDeviceExecute: @escaping @MainActor (SystemQuickAction) throws -> String = { try ProductionPublicDeviceExecutor().execute($0) },
        clipboardRead: @escaping @MainActor () throws -> SharedContent = { try SystemUserInitiatedClipboardReader().readAfterUserAction() },
        systemHandoffOpen: @escaping @MainActor (URL) -> Void = { UIApplication.shared.open($0) }
    ) -> AssistantViewModel {
        let context = CurrentContextStore()
        let executor = ProductionCanonicalCapabilityExecutor(
            contacts: contacts, photos: photos, locationResolver: locationResolver, placeSearch: placeSearch,
            currentLocation: currentLocation, reverseLocation: reverseLocation, currentContext: context, routeProvider: routeProvider,
            eventKit: eventKit, recorder: recorder,
            publicDeviceExecute: publicDeviceExecute, clipboardRead: clipboardRead,
            personalSearchSources: personalSearchSources
        )
        return AssistantViewModel(
            weatherExecutor: weather, eventKitExecutor: eventKit, capabilityExecutor: executor, currentContext: context, recorder: recorder,
            compactResultDuration: compactResultDuration, systemHandoffOpen: systemHandoffOpen
        )
    }
}

@main
struct UniversalAssistantApp: App {
    @State private var model = ProductionAssistantComposition.makeModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            AssistantHomeView(model: model)
                .task {
                    _ = model.ingestPendingShare()
                    if let recovered = LocalVoiceDiagnosticReport.shared.recoveredIncompleteSession() {
                        await PhysicalDiagnosticDelivery.shared.enqueue(recovered)
                    }
                    await PhysicalDiagnosticDelivery.shared.flush()
                }
        }
            .onChange(of: scenePhase) { _, phase in
                if phase != .active {
                    model.handleSceneBecameInactive()
                } else if model.ingestPendingShare() {
                    return
                } else {
                    model.handleQuickLaunch()
                }
            }
    }
}
