import SwiftUI

/// Single composition root used by the shipped app and Production-configuration E2E.
/// Tests may replace only an external side-effect boundary; parser, router, context,
/// executor graph and rendering lifecycle remain identical to Release.
@MainActor
enum ProductionAssistantComposition {
    static func makeModel(
        contacts: any ContactResolving = LocalContactResolver(),
        languageUnderstanding: LanguageUnderstandingBlock = .init(),
        photos: any PhotoLibrarySearching = PhotoKitLibrarySearch(),
        photoSemanticLoader: any PhotoAssetImageLoading = PhotoKitAssetImageLoader(),
        photoSemanticLabeler: any PhotoSemanticLabeling = VisionPhotoSemanticLabeler(),
        podcasts: ApplePodcastSearchProvider = .init(),
        mediaOverride: MediaIntegrationEngine? = nil,
        locationResolver: ManualLocationContextResolver = .init(),
        placeSearch: PlaceSearchEngine = .init(providers: [MapKitPlaceProvider(), OSMFuelPOIProvider()]),
        commerceSearch: CommerceSearchEngine = .init(providers: [SilpoRetailProvider(), OpenFoodFactsOpenPricesProvider()]),
        jobsDiscovery: JobDiscoveryEngine = .init(providers: [StateEmploymentOpenDataProvider()]),
        currentLocation: any CurrentLocationResolving = AppleCurrentLocationResolver(),
        reverseLocation: any ReverseLocationGeocoding = AppleReverseLocationGeocoder(),
        routeProvider: any RouteProvider = MapKitRouteProvider(),
        recorder: AudioRecorderController? = nil,
        personalSearchSources: [any PersonalSearchSource] = [
            ContactsPersonalSearchSource(), PhotosPersonalSearchSource(),
            LocalPersonalSearchSourceAdapter(source: AuthorizedFileSearchSource())
        ],
        compactResultDuration: Duration = .seconds(2),
        weather: any WeatherCommandExecuting = ProductionWeatherCommandExecutor(),
        fx: any CurrentFXProviding = RegionalCurrentFXProvider(),
        restaurantProviders: [any ReservationProvider] = [],
        affiliateConfigurations: [String: AffiliateRoutingConfiguration] = [:],
        alarmExecute: (  (SystemQuickAction) async throws -> String)? = nil,
        genericDiscovery: GenericUnknownRequestCoordinator? = nil,
        eventKit: any EventKitCommandExecuting = ProductionEventKitCommandExecutor(),
        publicDeviceExecute: @escaping @MainActor (SystemQuickAction) throws -> String = { try ProductionPublicDeviceExecutor().execute($0) },
        clipboardRead: @escaping @MainActor () throws -> SharedContent = { try SystemUserInitiatedClipboardReader().readAfterUserAction() },
        notificationEnable: @escaping @MainActor () async -> ProactiveNotificationEnableResult = { await ProductionNotificationRegistration.enable() },
        voiceInputOverride: (any VoiceInputControlling)? = nil,
        quickLaunchStore: QuickLaunchRequestStore = QuickLaunchRequestStore(),
        systemHandoffOpen: (@MainActor (URL) -> Void)? = nil,
        systemHandoffOpenResult: (@MainActor (URL) async -> Bool)? = nil
    ) -> AssistantViewModel {
        // Built in the body: inline default arguments crash Swift 6.1 SILGen
        // when this module is compiled with -O.
        let recorder = recorder ?? AudioRecorderController()
        let context = CurrentContextStore()
        let voiceInput: any VoiceInputControlling = voiceInputOverride ?? VoiceInputController(contextualVocabulary: {
            var vocabulary = languageUnderstanding.requestScopedCatalogVocabulary(limit: 64)
            // App names are the most error-prone words for uk-UA recognition,
            // so they are always present even when the catalogue is trimmed.
            vocabulary += ["Telegram", "Телеграм", "Телега", "Viber", "Вайбер", "WhatsApp",
                           "Ватсап", "YouTube", "Ютуб", "Налаштування", "Повідомлення"]
            return Array(Set(vocabulary)).sorted()
        })
        let executor = ProductionCanonicalCapabilityExecutor(
            contacts: contacts, photos: photos, photoSemanticLoader: photoSemanticLoader, photoSemanticLabeler: photoSemanticLabeler, podcasts: podcasts, mediaOverride: mediaOverride, locationResolver: locationResolver, placeSearch: placeSearch,
            commerceSearch: commerceSearch, jobsDiscovery: jobsDiscovery,
            currentLocation: currentLocation, reverseLocation: reverseLocation, currentContext: context, routeProvider: routeProvider,
            eventKit: eventKit, recorder: recorder,
            publicDeviceExecute: publicDeviceExecute, clipboardRead: clipboardRead, fx: fx,
            restaurantProviders: restaurantProviders, alarmExecute: alarmExecute,
            personalSearchSources: personalSearchSources, affiliateConfigurations: affiliateConfigurations
        )
        let productionGenericDiscovery = genericDiscovery
        return AssistantViewModel(
            commandEngine: languageUnderstanding, weatherExecutor: weather,
            genericDiscovery: productionGenericDiscovery,
            semanticCommandResolver: genericDiscovery == nil ? GroqSemanticCommandResolver() : nil,
            contacts: contacts,
            eventKitExecutor: eventKit,
            capabilityExecutor: executor,
            configuredRestaurantReservationProviderIDs: Set(restaurantProviders.map(\.providerID)),
            currentContext: context, recorder: recorder,
            compactResultDuration: compactResultDuration, voiceInput: voiceInput,
            notificationEnable: notificationEnable, quickLaunchStore: quickLaunchStore,
            systemHandoffOpen: systemHandoffOpen,
            systemHandoffOpenResult: systemHandoffOpenResult
        )
    }
}

@main
struct UniversalAssistantApp: App {
    @State private var model: AssistantViewModel
    @Environment(\.scenePhase) private var scenePhase
    // Without an app delegate nothing receives the APNs device token, so the
    // entitlement and the registration call were both inert.
    @UIApplicationDelegateAdaptor(RemoteNotificationBridge.self) private var notificationBridge

    init() {
        CrashlyticsDiagnosticBridge.configureProductionCollection()
        _model = State(initialValue: ProductionAssistantComposition.makeModel())
    }

    var body: some Scene {
        WindowGroup {
            AssistantHomeView(model: model)
                .task {
                    PhysicalMetricKitDiagnostics.shared.start()
                    _ = model.ingestPendingShare()
                    if let recovered = LocalVoiceDiagnosticReport.shared.recoveredIncompleteSession() {
                        await PhysicalDiagnosticDelivery.shared.enqueue(recovered)
                    }
                    await PhysicalDiagnosticDelivery.shared.flush()
                    // Token is requested only when the user already granted
                    // notification permission; this never prompts.
                    AudioSessionPrewarm.prepare()
                    await RemoteNotificationBridge.registerIfAuthorized()
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
