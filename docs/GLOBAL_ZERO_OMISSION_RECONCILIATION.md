# Global Zero-Omission Reconciliation

This is a cumulative evidence ledger, not a declaration of whole-product completion.

## Slice 1 — MS-737–850

- Source evidence: the 114 explicit per-ID rows in `M10_ZERO_OMISSION_AUDIT.md` and `M11_ZERO_OMISSION_ACCEPTANCE.md`.
- Validation: `Scripts/reconcile_requirement_evidence.py` rejects missing/duplicate IDs, unsupported statuses, empty evidence, unresolved Git commits and READY rows without a matching persistent live-queue contract.
- Behavioral evidence: `RequirementInventoryTests` requires all final statuses to carry implementation, test and commit evidence and all READY rows to name a remaining dependency.
- Result: 114/114 IDs reconciled; inventory totals are 212 VERIFIED_LOCAL, 12 READY_FOR_LIVE_VERIFICATION, 3 NOT_APPLICABLE_VERIFIED and 1560 NOT_IMPLEMENTED. The last count means “not yet reconciled or implemented”; it is not silently treated as product absence or completion.

Next: reconcile the next explicit, behaviorally supported canonical range. Range-only prose is not sufficient by itself.

## Slice 2 — MS-1–23

Each row was checked against the named production/repository path, current passing regression, and committed Git history.

| ID | Status | Implementation / behavioral evidence |
| --- | --- | --- |
| MS-1 | VERIFIED_LOCAL | launchable SwiftUI app plus backend; full iOS/backend regression |
| MS-2 | VERIFIED_LOCAL | LocalCommandEngine → typed routers/executors; GoldenUserJourneyAcceptanceTests |
| MS-3 | VERIFIED_LOCAL | InteractionDecisionEngine and verification/privacy policies; safety and partial-failure tests |
| MS-4 | VERIFIED_LOCAL | committed iOS/backend/provider/security/QA deliverables across M0–M12; ProductionEngineeringAuditTests |
| MS-5 | VERIFIED_LOCAL | CI, release/device matrices, migration/recovery and regression evidence |
| MS-6 | VERIFIED_LOCAL | EXECUTION_STATE exit contract plus atomic tested block history |
| MS-7 | VERIFIED_LOCAL | autonomous atomic Git history and persistent current/next state |
| MS-8 | VERIFIED_LOCAL | ATTEMPT_LEDGER failure→diagnosis→material-fix records; ExecutionStateGovernanceTests |
| MS-9 | VERIFIED_LOCAL | typed owner dependency/live queue contracts; IntegrationVerificationPolicyTests |
| MS-10 | VERIFIED_LOCAL | bounded provider failure isolation and independent queue entries; ProviderFanoutEngineTests |
| MS-11 | VERIFIED_LOCAL | designated Git source, synchronized origin/main, secret-scan policy/tests |
| MS-12 | VERIFIED_LOCAL | sequential build/test/state/docs atomic commits evidenced by Git history |
| MS-13 | VERIFIED_LOCAL | PROGRESS.md is present and non-empty; ProductionEngineeringAuditTests |
| MS-14 | VERIFIED_LOCAL | INTEGRATION_STATUS.md plus capability evidence policy/tests |
| MS-15 | VERIFIED_LOCAL | REAL_DEVICE_TEST_MATRIX.md plus persistent LIVE_VERIFICATION_QUEUE.json |
| MS-16 | VERIFIED_LOCAL | ARCHITECTURE.md covers app, backend, providers, sync, security and commerce |
| MS-17 | VERIFIED_LOCAL | PRIVACY_DATA_MAP.md and PrivacyComplianceTests |
| MS-18 | VERIFIED_LOCAL | RELEASE_CHECKLIST.md and executable production-surface audit |
| MS-19 | VERIFIED_LOCAL | EXECUTION_STATE/heartbeat/watchdog resume invariants; ExecutionStateGovernanceTests |
| MS-20 | VERIFIED_LOCAL | IntegrationVerificationPolicy rejects mock/internal evidence for live claims |
| MS-21 | VERIFIED_LOCAL | verified-fact models reject unknown/stale values; domain behavioral tests |
| MS-22 | VERIFIED_LOCAL | evidence-level policy requires E4/E5 for external/device live claims |
| MS-23 | VERIFIED_LOCAL | offer/feed/search fact models retain source timestamp/freshness/status; behavioral expiry tests |

## Slice 3 — MS-24–60

Every row maps the canonical behavior to a production path and a behavioral test; the commit column identifies the implementation tree containing that evidence.

| ID | Status | Implementation / behavioral evidence | Commit |
| --- | --- | --- | --- |
| MS-24 | VERIFIED_LOCAL | InteractionDecisionEngine direct-action path plus SpeechOutputPolicy; clear commands execute without processing narration; InteractionDecisionEngineTests and RuntimeExperiencePolicyTests | ffd98a9 |
| MS-25 | VERIFIED_LOCAL | SpeechOutputPolicy rejects obvious-processing and direct-action narration; speechNeverNarratesObviousWorkButAllowsNecessaryContent | ffd98a9 |
| MS-26 | VERIFIED_LOCAL | FashionOfficialSourceRouter opens an exact approved official destination without narration; FashionDiscoveryTests officialAppPrecedesExactOfficialWebPage/homepage rejection | ffd98a9 |
| MS-27 | VERIFIED_LOCAL | CurrentContext savedPlace plus NavigationHandoff exact destination/default provider flow; confirmedHomeAndWorkAreReusedOnlyWhileFresh and RouteNavigationTests | ffd98a9 |
| MS-28 | VERIFIED_LOCAL | UniversalDeviceCommandRouter and LaunchMarketAppMatrix exact Ukrzaliznytsia handoff; UniversalDeviceCommandRouterTests/LaunchMarketAppMatrixTests | ffd98a9 |
| MS-29 | VERIFIED_LOCAL | LocalCommandEngine calendarCreate direct-action decision and CalendarService validated mutation/undo; LocalCommandEngineTests, InteractionDecisionEngineTests, CalendarServiceTests | ffd98a9 |
| MS-30 | VERIFIED_LOCAL | AssistantViewModel cancellable compact-result auto-dismiss task; compactConfirmationDismissesAndNewSubmissionCancelsOldTimer | 3d9aaef |
| MS-31 | VERIFIED_LOCAL | SpeechOutputPolicy allowlists facts, ambiguity, warnings, inability, decisions and safety only; speechNeverNarratesObviousWorkButAllowsNecessaryContent | ffd98a9 |
| MS-32 | VERIFIED_LOCAL | CurrentContext confirmedPreference/savedPlace and persistent alias/map preference stores; StrongCurrentContextTests, RuntimeExperiencePolicyTests, ContactAliasTests, RouteNavigationTests | ffd98a9 |
| MS-33 | VERIFIED_LOCAL | CurrentContext savedPlace reuses owner-confirmed fresh Home/Work IDs; confirmedHomeAndWorkAreReusedOnlyWhileFresh | ffd98a9 |
| MS-34 | VERIFIED_LOCAL | ContactAliasDirectory persists normalized confirmed aliases to exact identifiers; ContactAliasTests | ffd98a9 |
| MS-35 | VERIFIED_LOCAL | NavigationPreferences persists/restores default provider and exact handoff uses the selected provider; defaultMapPersistsAndRestores | ffd98a9 |
| MS-36 | VERIFIED_LOCAL | TaxiPreference and KnownPreferenceResolver deterministically preserve cheapest/max-wait rule; explicitTaxiRuleBecomesDeterministicRequestWithoutClarification plus RideComparisonEngineTests | ffd98a9 |
| MS-37 | VERIFIED_LOCAL | LocalCommandEngine marks only unknown input unresolved and InteractionDecisionEngine emits one clarify pattern; unknownIsTruthful/ambiguityRequiresOneClarificationPattern | ffd98a9 |
| MS-38 | VERIFIED_LOCAL | DeterministicPlanExecutor and ProviderFanoutEngine bound stalled work; providerThatNeverRespondsIsBoundedByTimeout and timeout coordination tests | ffd98a9 |
| MS-39 | VERIFIED_LOCAL | async provider protocols, actors and task groups keep external operations outside synchronous UI work; ProviderFanoutEngineTests and CoordinationAcceptanceTests | ffd98a9 |
| MS-40 | VERIFIED_LOCAL | DeterministicPlanExecutor, CommerceSearchEngine and ProviderFanoutEngine race external work against configured timeout; timeout behavioral tests | ffd98a9 |
| MS-41 | VERIFIED_LOCAL | executor/fanout/search tasks propagate cancellation and cancel child work; lateProviderIsCancelledAndCannotLeakAResult and sufficientResultCancelsObsoleteParallelWork | ffd98a9 |
| MS-42 | VERIFIED_LOCAL | provider failures become typed partial outcomes without disabling successful providers; ticketProviderFailureReturnsRankedPartialResults | ffd98a9 |
| MS-43 | VERIFIED_LOCAL | all potentially stalled fanout paths terminate via timeout/partial result and AssistantResultState exits compact transient state; ProviderFanoutEngineTests/AssistantResultStateTests | ffd98a9 |
| MS-44 | VERIFIED_LOCAL | DeterministicExecutionPlanBuilder activationPath selects only intent-required capability modules; coffeeActivatesOnlyCanonicalMinimalPath/unrelatedProviderModulesStayOutOfSimplePaths | ffd98a9 |
| MS-45 | VERIFIED_LOCAL | CommerceSearchEngine and DeterministicPlanExecutor use task groups for independent calls; providerFanoutIsBounded and multi-module concurrency acceptance | ffd98a9 |
| MS-46 | VERIFIED_LOCAL | CommerceSearchEngine inFlight key shares equivalent simultaneous searches; identicalConcurrentRequestsShareOneProviderCall | ffd98a9 |
| MS-47 | VERIFIED_LOCAL | CommerceSearchEngine TTL plus LRU entry cap and PerformanceRecorder bounded ring; freshCacheIsReusedAndExpiresTruthfully/boundedSamplesDiscardOldest | ffd98a9 |
| MS-48 | VERIFIED_LOCAL | UI model retains only presentation state while async actors/task groups own provider, persistence and parsing work; concurrency behavioral suite and Swift 6 isolation build | ffd98a9 |
| MS-49 | VERIFIED_LOCAL | app launch constructs no provider engines; activationPath expresses on-demand intent modules; unrelatedProviderModulesStayOutOfSimplePaths and production app composition | ffd98a9 |
| MS-50 | VERIFIED_LOCAL | LocalCommandEngine recognizes “Хочу кави”; activationPath is exactly Voice→Command→Location→Places→Route; coffeeActivatesOnlyCanonicalMinimalPath | ffd98a9 |
| MS-51 | VERIFIED_LOCAL | RuntimeResourcePolicy tightens provider concurrency/cache/GPS under pressure; CommerceSearchEngine memory purge and AccurateLocationEngine purpose accuracy/timeout; resource policy/memory tests | ffd98a9 |
| MS-52 | VERIFIED_LOCAL | PerformanceRecorder/CoordinationObservation records timeToFirstUsefulResult and total completion from command coordination; PerformanceRecorderTests | ffd98a9 |
| MS-53 | VERIFIED_LOCAL | LocalCommandEngine and direct InteractionDecisionEngine path require no network/AI; localParserBaseline and clearOpenUsesDirectPattern | ffd98a9 |
| MS-54 | VERIFIED_LOCAL | progressive CommerceSearchEngine yields each verified provider aggregate and executor cancels obsolete work once sufficient; progressiveSearchFinishesWithStableAggregate/sufficientResultCancelsObsoleteParallelWork | ffd98a9 |
| MS-55 | VERIFIED_LOCAL | bounded timeouts, partial results, truthful failures, cache freshness and cancellation cover slow/offline/outage/interruption paths; ProviderFanoutEngineTests/CommerceSearchEngineTests | ffd98a9 |
| MS-56 | VERIFIED_LOCAL | UniversalAssistantApp scenePhase hook calls AssistantViewModel handleSceneBecameInactive to stop transient voice/timers; leavingActiveSceneStopsTransientListeningState | 5d369bf |
| MS-57 | VERIFIED_LOCAL | AccountPolicy keeps local features network-independent and fanout preserves local results through backend/network errors; simultaneousBackendAndNetworkFailuresRemainIsolated/AccountPolicyTests | ffd98a9 |
| MS-58 | VERIFIED_LOCAL | superseded Task cancellation prevents stale aggregate and new submit cancels prior result timer; cancellingOldCommandDoesNotReturnAStaleAggregate/AssistantResultStateTests | ffd98a9 |
| MS-59 | VERIFIED_LOCAL | ProviderFanoutEngine isolates simultaneous backend/network failures and returns verified local result; simultaneousBackendAndNetworkFailuresRemainIsolated | ffd98a9 |
| MS-60 | VERIFIED_LOCAL | CommerceSearchEngine handleMemoryPressure cancels in-flight work and purges cache; memoryPressureCancelsWorkAndPurgesCachedResults | 5d369bf |

## Slice 4 — MS-61–78

Each status below is grounded in a production path and behavior-level test; optional AI remains outside deterministic and factual authority paths.

| ID | Status | Implementation / behavioral evidence | Commit |
| --- | --- | --- | --- |
| MS-61 | VERIFIED_LOCAL | UILanguage defines Ukrainian, Russian, English, German and French; five localized resource sets and LocalizationAccessibilityTests verify coverage | 6c06260 |
| MS-62 | VERIFIED_LOCAL | LanguageConfiguration maps all five UI/command languages to explicit speech locales; localized UI, settings, onboarding and error resources are exercised by LocalizationAccessibilityTests | 6c06260 |
| MS-63 | VERIFIED_LOCAL | LanguageConfiguration independently stores uiLanguage and commandLanguage through LanguageConfigurationStore; uiAndCommandLanguagesAreIndependentAndPersistent | 6c06260 |
| MS-64 | VERIFIED_LOCAL | automatic command-language mode plus LocalCommandEngine script detection selects the actual input language; allFiveLanguagesHaveExplicitVoiceLocalesAndAutomaticMode and multilingual parser tests | 6c06260 |
| MS-65 | VERIFIED_LOCAL | LocalCommandEngine preserves English brand tokens inside Ukrainian/Russian context; mixedNaturalCommands and surroundingLanguageDoesNotCorruptBrandOrAppName | 26243b5 |
| MS-66 | VERIFIED_LOCAL | parser accepts polite and colloquial forms without AI; tolerantCommandGrammar | 26243b5 |
| MS-67 | VERIFIED_LOCAL | tolerant deterministic substring grammar handles imperfect/transcribed app input while retaining the requested entity; tolerantCommandGrammar | 26243b5 |
| MS-68 | VERIFIED_LOCAL | prefix and postfix command word order resolve to the same typed intent; mixedNaturalCommands | 26243b5 |
| MS-69 | VERIFIED_LOCAL | multilingual reminder infinitives/synonyms and inflected fashion/coffee forms map deterministically; tolerantCommandGrammar and mixedNaturalCommands | 26243b5 |
| MS-70 | VERIFIED_LOCAL | entity extraction preserves original capitalization and complete app/brand names after surrounding natural language; surroundingLanguageDoesNotCorruptBrandOrAppName | 26243b5 |
| MS-71 | VERIFIED_LOCAL | DeterministicExecutionPlan and LocalCommandEngine execute known commands with zero mandatory AI calls; CoordinationAcceptanceTests simple and multi-module zero-AI cases | ca92a6f |
| MS-72 | VERIFIED_LOCAL | LocalCommandEngine uses deterministic grammar/entity/date rules and VoiceInputController uses Apple's on-device speech boundary; LocalCommandEngineTests and LanguageAndAIConfigurationTests | 6c06260 |
| MS-73 | VERIFIED_LOCAL | UserConnectedAIConfiguration defaults disabled with no provider or credential; optionalUserConnectedAIDefaultsOffAndStoresOnlySecretReference | 6c06260 |
| MS-74 | VERIFIED_LOCAL | typed UserAIProvider supports OpenAI, Anthropic, Gemini and compatible future endpoints without routing them into the fast path; provider enumeration test | 6c06260 |
| MS-75 | VERIFIED_LOCAL | optional AI configuration retains only a user-controlled secure credential reference, never a credential value; optionalUserConnectedAIDefaultsOffAndStoresOnlySecretReference | 6c06260 |
| MS-76 | VERIFIED_LOCAL | BoundedAIInterpretationCoordinator invokes one schema-bound fallback only after explicit unresolved semantics; exactlyOneBoundedInterpretationResumesDeterministicExecution | ca92a6f |
| MS-77 | VERIFIED_LOCAL | AI interpretation schema allowlist rejects live fact fields and execution scripts; schemaRejectsLiveFacts and verified-facts-only coordination tests | ca92a6f |
| MS-78 | VERIFIED_LOCAL | AI timeout/unavailability returns deterministic unresolved/partial outcome without hanging or disabling core capabilities; timeoutFallsBackWithoutBlockingDeterministicCapabilities | ca92a6f |

## Slice 5 — MS-79–114

The complete canonical intent surface was traced from deterministic recognition into its real local, provider, handoff or safety path. The tests named below verify behavior rather than enum existence.

| ID | Status | Implementation / behavioral evidence | Commit |
| --- | --- | --- | --- |
| MS-79 | VERIFIED_LOCAL | LocalCommandEngine PLACE_SEARCH → PlaceSearchEngine/MapKitPlaceProvider; canonical intent matrix and PlaceSearchEngineTests | 27ad853 |
| MS-80 | VERIFIED_LOCAL | PRODUCT_SEARCH → CommerceSearchEngine normalized verified offers; parser constraint test and CommerceSearchEngineTests | 27ad853 |
| MS-81 | VERIFIED_LOCAL | FASHION_DISCOVERY → FashionDiscovery and official-source router; FashionDiscoveryTests | 27ad853 |
| MS-82 | VERIFIED_LOCAL | GROCERY_BASKET → GroceryBasketEngine with exact Decimal totals; GroceryBasketEngineTests | 27ad853 |
| MS-83 | VERIFIED_LOCAL | SERVICE_SEARCH → typed LocalServiceDomain categories/providers; LocalServiceDomainTests and parser category coverage | 27ad853 |
| MS-84 | VERIFIED_LOCAL | RESTAURANT_SEARCH recognized and routed to external place/food capability; canonical intent matrix, PlaceSearchEngineTests and FoodDeliveryComparisonEngineTests | 27ad853 |
| MS-85 | VERIFIED_LOCAL | RESERVATION uses verified AppointmentEngine availability/book/reschedule/cancel boundary with confirmation; AppointmentEngineTests | 27ad853 |
| MS-86 | VERIFIED_LOCAL | TAXI_SEARCH recognized and isolated behind verified provider registry/handoff; canonical intent matrix and RideProviderRegistryTests | 27ad853 |
| MS-87 | VERIFIED_LOCAL | TAXI_COMPARE ranks truthful quotes without fabricated values; RideComparisonEngineTests | 27ad853 |
| MS-88 | VERIFIED_LOCAL | NAVIGATION uses validated RouteEngine and exact map handoff; RouteNavigationTests | 27ad853 |
| MS-89 | VERIFIED_LOCAL | ROUTE_SEARCH deterministic intent routes to navigation capability; canonical intent matrix and RouteNavigationTests | 27ad853 |
| MS-90 | VERIFIED_LOCAL | ROUTE_AWARE_SEARCH computes bounded detours from route provider facts; canonical intent matrix and RouteNavigationTests | 27ad853 |
| MS-91 | VERIFIED_LOCAL | CalendarService implements EventKit create/query/update/delete with authoritative IDs and undo; CalendarServiceTests plus four-intent parser matrix | 27ad853 |
| MS-92 | VERIFIED_LOCAL | ReminderService implements EventKit operations and undo/update snapshots; ReminderServiceTests and reminder parser matrix | 27ad853 |
| MS-93 | VERIFIED_LOCAL | NOTE_CREATE/QUERY use truthful system share handoff because unrestricted Notes API is unavailable; LocalActionRouterTests and parser matrix | 27ad853 |
| MS-94 | VERIFIED_LOCAL | SHOPPING_LIST routes directly to EventKit reminders without duplicate storage; LocalActionRouterTests and parser matrix | 27ad853 |
| MS-95 | VERIFIED_LOCAL | CONTACT_LOOKUP/CALL use Contacts resolver, aliases and exact system call route; ContactAliasTests, LocalActionRouterTests and parser tests | 27ad853 |
| MS-96 | VERIFIED_LOCAL | MESSAGE_COMPOSE uses MessageUI system composer with recipient validation and truthful completion; MessagingIntegrationTests | 27ad853 |
| MS-97 | VERIFIED_LOCAL | WEATHER uses WeatherKit provider facts and contextual resolver; WeatherContextTests and parser tests | 27ad853 |
| MS-98 | VERIFIED_LOCAL | PUBLIC_TRANSPORT uses normalized TransportEngine provider boundary; TransportEngineTests and parser matrix | 27ad853 |
| MS-99 | VERIFIED_LOCAL | TRANSPORT_ROUTE uses verified itinerary segments and validation; TransportEngineTests and parser matrix | 27ad853 |
| MS-100 | VERIFIED_LOCAL | TICKET_SEARCH/PURCHASE_HANDOFF separate verified search from consequential handoff; TicketEngineTests and precedence parser test | 27ad853 |
| MS-101 | VERIFIED_LOCAL | HOTEL_SEARCH uses bounded truthful HotelSearchEngine; HotelSearchEngineTests and parser matrix | 27ad853 |
| MS-102 | VERIFIED_LOCAL | TRAVEL_PLAN deterministically coordinates Calendar/location/weather/transport/hotel with zero AI; TravelPlanEngineTests and CoordinationAcceptanceTests | 27ad853 |
| MS-103 | VERIFIED_LOCAL | EMERGENCY resolves Ukrainian emergency scenario to legitimate 112/capability handoff; UkraineEmergencyPlannerTests and inflection parser test | 27ad853 |
| MS-104 | VERIFIED_LOCAL | ControlledWebSearchHandoff permits validated HTTPS fallback only when no structured capability is available; ControlledWebSearchHandoffTests | 27ad853 |
| MS-105 | VERIFIED_LOCAL | DEVICE_ACTION recognized then governed by SystemQuickActionPlanner public-API feasibility outcomes; SystemQuickActionPlannerTests | 27ad853 |
| MS-106 | VERIFIED_LOCAL | APP_ACTION resolves exact verified app descriptors/deep links and fails closed on ambiguity/unsupported targets; UniversalDeviceCommandRouterTests | 27ad853 |
| MS-107 | VERIFIED_LOCAL | AUDIO_RECORD routes to real AVAudioRecorder controller with permission/state/file lifecycle; AudioRecorderControllerTests and precedence parser test | 27ad853 |
| MS-108 | VERIFIED_LOCAL | universal SHOW produces typed informational presentation without side effects; parser matrix and AssistantResultStateTests | 27ad853 |
| MS-109 | VERIFIED_LOCAL | universal OPEN preserves exact app name and resolves only registered public destinations silently; UniversalDeviceCommandRouterTests and multilingual parser tests | 27ad853 |
| MS-110 | VERIFIED_LOCAL | CANCEL_ACTION is consequential in InteractionDecisionEngine and maps only exact cancellable objects in UniversalActionGraph; safety/action graph tests | 27ad853 |
| MS-111 | VERIFIED_LOCAL | UNDO_ACTION uses persistent ActionHistory latest-completed state machine and exact domain undo handlers; ActionHistoryTests, CalendarServiceTests and ReminderServiceTests | 27ad853 |
| MS-112 | VERIFIED_LOCAL | MULTI_STEP_COMMAND compiles typed dependency plans and executes independent work concurrently with bounded failure/cancellation; CoordinationAcceptanceTests and RoutineMacroEngineTests | 27ad853 |
| MS-113 | VERIFIED_LOCAL | SETTINGS_ACTION is locally recognized and routed as a typed non-consequential action; remainingCanonicalIntentRecognition and InteractionDecisionEngineTests | 27ad853 |
| MS-114 | VERIFIED_LOCAL | GENERAL_HELP is deterministic, local and compact rather than AI chat; remainingCanonicalIntentRecognition and AssistantResultStateTests | 27ad853 |

## Slice 6 — MS-115–136

| ID | Status | Implementation / behavioral evidence | Commit |
| --- | --- | --- | --- |
| MS-115 | VERIFIED_LOCAL | ConsequentialCommandGate accepts only ValidatedStructuredCommand after deterministic parsing and confirmation; StructuredCommandValidationTests | 15a3114 |
| MS-116 | VERIFIED_LOCAL | StructuredCommandValidator checks intent, ambiguity, target, date/time, location, permission and risk before execution; StructuredCommandValidationTests | 15a3114 |
| MS-117 | VERIFIED_LOCAL | LocalContactResolver queries the on-device Contacts store by name/exact ID using minimum required keys; ContactAliasTests and LocalActionRouterTests | ddbccca |
| MS-118 | VERIFIED_LOCAL | LocalContactResolver returns typed ambiguous candidates rather than selecting one; contact ambiguity behavior and interaction clarification tests | ddbccca |
| MS-119 | VERIFIED_LOCAL | ContactAliasDirectory accepts user-confirmed arbitrary relationship/work aliases with normalized multilingual text; ContactAliasTests | ddbccca |
| MS-120 | VERIFIED_LOCAL | confirmed alias maps persistently to exact CNContact identifier and restores across launch; ContactAliasTests | ddbccca |
| MS-121 | VERIFIED_LOCAL | Contacts remain device-local and resolver fetches only identifier/name/organization/phone fields for the requested predicate; privacy and contact tests | ddbccca |
| MS-122 | VERIFIED_LOCAL | bounded persistent ActionHistory records assistant-created/modified reversible actions and crash-recovers undoing state; ActionHistoryTests | ddbccca |
| MS-123 | VERIFIED_LOCAL | undoLast selects only latest completed action, persists transitions and invokes exact domain undo handler; ActionHistoryTests, CalendarServiceTests, ReminderServiceTests | ddbccca |
| MS-124 | VERIFIED_LOCAL | LinkedPlanMutationCoordinator cancels one exact query/day match after confirmation and returns ambiguous/notFound otherwise; LinkedPlanMutationCoordinatorTests | ddbccca |
| MS-125 | VERIFIED_LOCAL | reschedule mutates and verifies the same external plan ID/start rather than creating a duplicate; LinkedPlanMutationCoordinatorTests | ddbccca |
| MS-126 | VERIFIED_LOCAL | confirmed cancellation removes only linked departure reminder/route watch/proactive rule; reschedule updates those exact linked IDs; LinkedPlanMutationCoordinatorTests | ddbccca |
| MS-127 | VERIFIED_LOCAL | one AccurateLocationEngine owns Core Location acquisition and LocationValidator for location-dependent consumers; LocationValidatorTests and PlaceSearchEngineTests | ddbccca |
| MS-128 | VERIFIED_LOCAL | AccurateLocationEngine uses public CLLocationManager authorization/requestLocation APIs only; location and permission tests | ddbccca |
| MS-129 | VERIFIED_LOCAL | LocationValidator evaluates horizontalAccuracy and reduced-accuracy authorization; qualityUsesRealAccuracyAndReducedAuthorization | ddbccca |
| MS-130 | VERIFIED_LOCAL | sample timestamp drives poor/unavailable downgrade with future-skew rejection; staleAndInvalidSamplesAreDowngraded | ddbccca |
| MS-131 | VERIFIED_LOCAL | validator compares prior coordinates and elapsed time against maximum plausible speed; impossibleJumpIsSuspiciousAndUnsafe | ddbccca |
| MS-132 | VERIFIED_LOCAL | typed LocationQuality defines precise/good/approximate/poor/suspicious/unavailable and behavioral tests exercise every safety class | ddbccca |
| MS-133 | VERIFIED_LOCAL | precise is emitted only from actual device measurement at or below ten metres; manual location is explicitly approximate; LocationValidatorTests | ddbccca |
| MS-134 | VERIFIED_LOCAL | Haversine elapsed-speed filter marks Kyiv-scale impossible jumps suspicious and unsafe; impossibleJumpIsSuspiciousAndUnsafe | ddbccca |
| MS-135 | VERIFIED_LOCAL | suspicious/unavailable locations set isSafeForLocationActions false and place/weather engines reject unsafe use; LocationValidatorTests and WeatherContextTests | ddbccca |
| MS-136 | VERIFIED_LOCAL | AccurateLocationEngine retries poor/suspicious readings with bounded fresh samples then resolves available/unavailable truthfully; location recovery implementation and WeatherContextTests | ddbccca |

## Slice 7 — MS-137–154

| ID | Status | Implementation / behavioral evidence | Commit |
| --- | --- | --- | --- |
| MS-137 | VERIFIED_LOCAL | ManualLocationContextResolver uses the production Apple geocoder boundary, validates the resolved coordinate and preserves a trimmed manual label/source distinct from device location; LocationValidatorTests named manual context test | 64be768 |
| MS-138 | VERIFIED_LOCAL | LocationValidator and AccurateLocationEngine have no network dependency and accept current Core Location GPS samples and explicit manual coordinates offline; manualOverrideIsExplicitAndUsableOffline | 64be768 |
| MS-139 | VERIFIED_LOCAL | AccurateLocationEngine selects hundred-metre accuracy for general use, nearest-ten-metres for nearby search and best only for navigation/emergency; RuntimeExperiencePolicyTests resource limits plus location implementation | 64be768 |
| MS-140 | VERIFIED_LOCAL | PlaceProvider is a Sendable typed search contract consumed by PlaceSearchEngine and production MapKitPlaceProvider; PlaceSearchEngineTests | 5cfcf45 |
| MS-141 | VERIFIED_LOCAL | MapKitPlaceProvider is the legitimate credential-free production adapter and PlaceProvider permits Google/Foursquare/future adapters without hardcoding or falsely claiming unavailable integrations; provider query and engine tests | 5cfcf45 |
| MS-142 | VERIFIED_LOCAL | PlaceSearchEngine fans out across a bounded provider set concurrently and truthfully retains partial results/failures; PlaceSearchEngineTests | 5cfcf45 |
| MS-143 | VERIFIED_LOCAL | PlaceDeduplicator merges exact same-source IDs or cross-source same normalized name/category within 30 metres; PlaceCoreTests | 64be768 |
| MS-144 | VERIFIED_LOCAL | Place carries source, timestamp, verification and bounded optional confidence, with deterministic recent/stale/unknown classification; freshnessConfidenceAndVerifiedTravelTimeAreBehavioralRankingInputs | 64be768 |
| MS-145 | VERIFIED_LOCAL | PlaceCategory enumerates all canonical cafe, retail, health, vehicle, public-service and other POI classes; MapKit category mapping and PlaceCoreTests compile the exhaustive production model | 64be768 |
| MS-146 | VERIFIED_LOCAL | Place production model contains canonical ID/provider ID, name, category, coordinates, address, distance, travel time, phone, official URL, rating/count, hours/open state, price level, source, timestamp and verification | 64be768 |
| MS-147 | VERIFIED_LOCAL | CoffeeScenarioCoordinator executes validated location through real PlaceProvider aggregation, verified walking RouteProvider facts, ranking and exact navigation action; coffeeScenarioRunsValidatedProviderRouteRankingAndExactActionEndToEnd | 5cfcf45 |
| MS-148 | VERIFIED_LOCAL | PlaceRanker deterministically combines text/category relevance, verified travel time or distance, open state, rating volume, verification and confidence; PlaceCoreTests | 64be768 |
| MS-149 | VERIFIED_LOCAL | ROUTE_AWARE_SEARCH is recognized deterministically and RouteAwareSearchEngine evaluates bounded candidate stops between actual origin/destination; LocalCommandEngineTests and RouteNavigationTests | 64be768 |
| MS-150 | VERIFIED_LOCAL | RouteAwareSearchEngine calculates detour from provider route legs against provider baseline rather than straight-line distance; routeAwareSearchUsesActualRouteDurationsForDetour | 64be768 |
| MS-151 | VERIFIED_LOCAL | NavigationHandoff builds validated exact Apple Maps, Google Maps and Waze navigation URLs; parameterized exactHandoff tests all providers | 64be768 |
| MS-152 | VERIFIED_LOCAL | NavigationPreferences persists and restores the selected default provider through LocalStore for silent reuse; defaultMapPersistsAndRestores | 64be768 |
| MS-153 | VERIFIED_LOCAL | clear navigation commands use the deterministic direct-action route and NavigationHandoff produces a launch URL without an extra clarification step; navigation parser/validation and RouteNavigationTests | 64be768 |
| MS-154 | VERIFIED_LOCAL | InitialWalkingGuidanceComposer emits only the concise first nonempty step from a verified walking RouteResult and emits nothing for other modes/missing route facts; RouteNavigationTests | 64be768 |

## Slice 8 — MS-155–182

| ID | Status | Implementation / behavioral evidence | Commit |
| --- | --- | --- | --- |
| MS-155 | VERIFIED_LOCAL | RetailProvider is the typed async commerce source boundary registered through ProviderCapabilityRegistry; CommerceIdentityRegistryTests | c44565e |
| MS-156 | VERIFIED_LOCAL | RetailSearchRequest carries brand/model/type/variant/size/color/quantity, validated price range, pickup/delivery preference and validated coordinate/radius; retailRequestCarriesAndValidatesAllCanonicalSearchConstraints | 94e56d9 |
| MS-157 | VERIFIED_LOCAL | NormalizedOffer exposes exact availability only with source timestamp/verification and CommerceSearchEngine rejects stale offers rather than inventing stock; NormalizedOfferTests and CommerceSearchEngineTests | d3fd2a2 |
| MS-158 | VERIFIED_LOCAL | ProviderCapabilityRegistry plus the Ukrainian retailer source matrix records only researched official API/MCP, partner, affiliate, feed and permitted official-web paths with explicit capability state; CommerceIdentityRegistryTests | 29b2e3d |
| MS-159 | VERIFIED_LOCAL | UkrainianRetailerRegistry models Silpo, ATB, Fora and Fozzy as first-class normalized sources without false live claims; UkrainianRetailerRegistryTests | 29b2e3d |
| MS-160 | VERIFIED_LOCAL | RetailProvider and actor-isolated ProviderCapabilityRegistry permit modular providers without scattering source-specific logic through domain/UI; CommerceIdentityRegistryTests | c44565e |
| MS-161 | VERIFIED_LOCAL | FashionDiscoveryRequest and FashionOfficialSourceRouter provide the production typed fashion discovery path; FashionDiscoveryTests | 6a2bac5 |
| MS-162 | VERIFIED_LOCAL | FashionDiscoveryRequest deterministically parses audience/category/brand/size/color/season/max-price/channel constraints; multilingualFashionFiltersRemainHardConstraints | 6a2bac5 |
| MS-163 | VERIFIED_LOCAL | latest-collection claims require an explicit verified source claim before official routing; latestAndDiscountAreNeverInvented | 6a2bac5 |
| MS-164 | VERIFIED_LOCAL | new-arrival claims share the explicit current source-claim contract and cannot be inferred from copy or route alone; FashionDiscoveryTests | 6a2bac5 |
| MS-165 | VERIFIED_LOCAL | discounts require the verified discount source claim and unverified discount requests fail closed; latestAndDiscountAreNeverInvented | 6a2bac5 |
| MS-166 | VERIFIED_LOCAL | the multilingual Baldinini request resolves hard filters and OfficialFashionSourceRouter silently selects an exact official app route before the exact allowed official page; FashionDiscoveryTests | 6a2bac5 |
| MS-167 | VERIFIED_LOCAL | universal SHOW maps to typed informational presentation with no side effect and supports commerce result rendering; LocalCommandEngineTests and AssistantResultStateTests | 27ad853 |
| MS-168 | VERIFIED_LOCAL | universal OPEN preserves the requested target and resolves only a registered exact app/deep-link/official destination; UniversalDeviceCommandRouterTests and FashionDiscoveryTests | 27ad853 |
| MS-169 | VERIFIED_LOCAL | official source routing orders exact official app before deep link/page and rejects homepage or unapproved hosts; officialAppPrecedesExactOfficialWebPage and homepageAndUnapprovedHostAreRejected | 6a2bac5 |
| MS-170 | VERIFIED_LOCAL | commerce keeps normalized searchable facts locally but hands off consequential catalog/action ownership to the exact official provider destination; FashionDiscoveryTests and AffiliatePurchaseHandoffTests | 0d2020e |
| MS-171 | VERIFIED_LOCAL | GroceryBasketEngine implements truthful normalized basket totals, comparisons and route-aware plans; GroceryBasketEngineTests | 2e9452e |
| MS-172 | VERIFIED_LOCAL | UkrainianRetailerRegistry represents Silpo adapter readiness plus researched-disabled ATB/Fora/Fozzy and permits future adapters through the same registry contract; UkrainianRetailerRegistryTests | 29b2e3d |
| MS-173 | VERIFIED_LOCAL | GroceryListParser parses natural-language grocery items and quantities into typed basket lines; naturalLanguageQuantitiesNormalizeToBaseUnits | 2e9452e |
| MS-174 | READY_FOR_LIVE_VERIFICATION | SilpoMCPClient implements the real fixed official Streamable HTTP MCP transport, runtime OAuth boundary, schema/error handling and local request/response tests; owner/provider OAuth is required solely for an authoritative live product query; LIVE_VERIFICATION_QUEUE MS-174-LIVE-SILPO-CURRENT-SOURCE | b7d8fa8 |
| MS-175 | VERIFIED_LOCAL | GroceryQuotedItem models exact/equivalent/substitute/unavailable/unverified and completeness distinguishes every non-exact result; GroceryBasketEngineTests | 2e9452e |
| MS-176 | VERIFIED_LOCAL | GroceryQuantity normalizes litre/millilitre and kilogram/gram quantities into base units and unit-price arithmetic uses Decimal; naturalLanguageQuantitiesNormalizeToBaseUnits and unitPriceUsesNormalizedPackQuantity | 2e9452e |
| MS-177 | VERIFIED_LOCAL | unavailable or substitute lines make a basket explicitly incomplete and expose their IDs; missingAndSubstituteItemsNeverProduceCompleteClaim | 2e9452e |
| MS-178 | VERIFIED_LOCAL | total reports store, truthful completeness, unavailable/substitute sets and Decimal subtotal without treating missing lines as zero-price available items; GroceryBasketEngineTests | 2e9452e |
| MS-179 | VERIFIED_LOCAL | compare deterministically ranks complete baskets ahead of cheaper incomplete baskets and then exact totals; completeBasketsRankBeforeCheaperIncompleteOnes | 2e9452e |
| MS-180 | VERIFIED_LOCAL | optimizer enumerates only one- or two-store plans and proves complete coverage before emitting a plan; optimizerUsesAtMostTwoStoresForCompleteCoverage | 8b04a53 |
| MS-181 | VERIFIED_LOCAL | route detour duration/distance and Decimal travel cost participate in plan feasibility and estimated total; travelCostPreventsTrivialSavingsFromWinning | 8b04a53 |
| MS-182 | VERIFIED_LOCAL | GroceryBasketEngine consumes route-derived detour constraints, rejects stale/incomplete candidates and selects a truthful route-aware basket plan; GroceryBasketEngineTests | 8b04a53 |

## Slice 9 — MS-183–203

| ID | Status | Implementation / behavioral evidence | Commit |
| --- | --- | --- | --- |
| MS-183 | VERIFIED_LOCAL | RestaurantSearchRequest and RestaurantDiscoveryEngine enforce cuisine, price, rating, distance, open-now, party, time and dietary constraints against fresh sourced offers; filtersEverySupportedRestaurantConstraintUsingEvidence | 41bbacf |
| MS-184 | VERIFIED_LOCAL | ReservationProvider is the typed availability/booking boundary consumed concurrently and provider-neutrally by RestaurantDiscoveryEngine; RestaurantDiscoveryEngineTests | 41bbacf |
| MS-185 | READY_FOR_LIVE_VERIFICATION | OfficialRestaurantHTTPProvider implements authenticated HTTPS availability retrieval, typed parsing, timeout/error mapping and freshness gates; local request/response tests pass; an owner-approved booking API credential is required solely for authoritative live slot verification; LIVE_VERIFICATION_QUEUE MS-185-186 | 9e291be |
| MS-186 | READY_FOR_LIVE_VERIFICATION | booking requires explicit confirmation plus authoritative provider confirmed state/reference; production HTTP mutation and fail-closed response validation pass locally; an approved provider account is required solely for a real booking/readback; LIVE_VERIFICATION_QUEUE MS-185-186 | 9e291be |
| MS-187 | VERIFIED_LOCAL | restaurant fallback deterministically prefers exact official booking page, then validated phone, then Apple Maps navigation without claiming a booking; fallbackUsesExactOfficialPageThenPhoneThenNavigation | 41bbacf |
| MS-188 | VERIFIED_LOCAL | LocalServiceCategory covers tow, taxi, courier, plumber, electrician, locksmith, cleaner, beauty, repair and medical service with typed provider capability filtering; LocalServiceDomainTests | d9e1ff2 |
| MS-189 | VERIFIED_LOCAL | LocalServiceEngine.towPlan validates location, filters verified tow providers and emits call/navigation handoffs plus truthful no-provider fallback; towFlowValidatesLocationAndProducesVerifiedHandoff | d9e1ff2 |
| MS-190 | VERIFIED_LOCAL | RideComparisonEngine applies verified freshness, availability, capability, budget and wait constraints with deterministic ranking; RideComparisonEngineTests | 226be8c |
| MS-191 | VERIFIED_LOCAL | RideProviderRegistry records researched official capability state for Uber, Bolt and Uklon and prevents unavailable provider claims from becoming comparison evidence; RideProviderRegistryTests and M5_RIDE_PROVIDER_CAPABILITY_HANDOFF | a35d297 |
| MS-192 | VERIFIED_LOCAL | RideOffer price is optional evidence and cheapest/budget logic uses it only when fresh, available and currency-compatible; RideComparisonEngineTests | 226be8c |
| MS-193 | VERIFIED_LOCAL | pickup ETA remains optional and fastest/max-wait ranking excludes missing or stale evidence when required; RideComparisonEngineTests | 226be8c |
| MS-194 | VERIFIED_LOCAL | VerifiedServiceAvailability distinguishes available/unavailable/unknown and only explicitly available fresh offers enter comparison; unknownDataIsNeverTreatedAsAvailable | 226be8c |
| MS-195 | VERIFIED_LOCAL | RideOffer carries optional estimatedArrival independently and no engine path synthesizes arrival time; RideComparisonEngineTests | 226be8c |
| MS-196 | VERIFIED_LOCAL | RideClass and typed capabilities model only provider-exposed class/seat/pet/vehicle/luggage facts; RideComparisonEngineTests | 226be8c |
| MS-197 | VERIFIED_LOCAL | ComparisonMode supports CHEAPEST, FASTEST, OPTIMAL, COMFORT, LARGE_VEHICLE, CHILD_SEAT, PET_FRIENDLY and LUGGAGE; mode/ranking behavioral tests | 226be8c |
| MS-198 | VERIFIED_LOCAL | maximumPrice is a hard Decimal/currency constraint and excludes unknown/over-budget offers; budgetIsHardConstraint | 226be8c |
| MS-199 | VERIFIED_LOCAL | maximumWaitSeconds is a hard constraint and rejects unknown or excessive wait; maximumWaitIsHardConstraint | 226be8c |
| MS-200 | VERIFIED_LOCAL | TaxiPreference persists explicit cheapest/max-wait rule and KnownPreferenceResolver turns it into a deterministic request; RuntimeExperiencePolicyTests | ffd98a9 |
| MS-201 | VERIFIED_LOCAL | comparison rejects unknown/stale price, ETA and availability rather than inventing values; RideComparisonEngineTests | 226be8c |
| MS-202 | VERIFIED_LOCAL | UberRideHandoffBuilder creates only an exact official route-prefilled HTTPS handoff with runtime client ID and validated locations; RideProviderRegistryTests | a35d297 |
| MS-203 | VERIFIED_LOCAL | ComparableServiceOffer is the shared provider-neutral comparison foundation and RideComparisonEngine consumes its normalized truth fields without provider-specific ranking branches; RideComparisonEngineTests | 226be8c |

## Slice 10 — MS-204–212

| ID | Status | Implementation / behavioral evidence | Commit |
| --- | --- | --- | --- |
| MS-204 | VERIFIED_LOCAL | TransportEngine now normalizes walking, driving, urban transit, train, intercity bus, air, taxi and multimodal options through one evidence-aware ranking contract; supportsEveryCanonicalModeAndTruthfulPublicTransportDetails | b4310d3 |
| MS-205 | VERIFIED_LOCAL | TransportOption carries sourced departure, arrival, duration, transfer/fare plus validated walking/transit route and stop segments; malformed transit detail fails closed; TransportEngineTests | b4310d3 |
| MS-206 | VERIFIED_LOCAL | TransportEngine keeps fare/action source-neutral and never claims a uniform city ticket mechanism; exact city/provider purchase semantics remain in TicketProvider/TicketEngine handoff; TransportEngineTests and TicketEngineTests | b4310d3 |
| MS-207 | VERIFIED_LOCAL | TicketProvider is an async provider-neutral abstraction with bounded concurrent TicketProviderCoordinator and production OfficialTicketHTTPProvider; provider fanout and HTTP adapter tests | 8f78ab4 |
| MS-208 | READY_FOR_LIVE_VERIFICATION | OfficialTicketHTTPProvider implements authenticated HTTPS schedule search, typed parsing, timeout and fail-closed errors; local request/response tests pass; an approved provider credential is required solely for live authoritative schedule verification; LIVE_VERIFICATION_QUEUE MS-208-211 | 8f78ab4 |
| MS-209 | READY_FOR_LIVE_VERIFICATION | TicketInventoryEvidence distinguishes verified available/unavailable/unknown with source/time and TicketEngine rejects stale/unknown inventory for a verified request or handoff; live provider inventory comparison remains queued; LIVE_VERIFICATION_QUEUE MS-208-211 | 8f78ab4 |
| MS-210 | READY_FOR_LIVE_VERIFICATION | TicketEngine accepts fare only as Decimal with current fareObservedAt evidence and hard currency-aware budget filtering; provider adapter parses authoritative values; current live fare requires approved access; LIVE_VERIFICATION_QUEUE MS-208-211 | 8f78ab4 |
| MS-211 | READY_FOR_LIVE_VERIFICATION | TicketEngine emits only an exact fresh official HTTPS destinationPrepared handoff and never claims purchase; any direct transaction requires a selected provider contract/live test; LIVE_VERIFICATION_QUEUE MS-208-211 | 8f78ab4 |
| MS-212 | VERIFIED_LOCAL | TicketSearchRequest and TicketEngine enforce mode, origin, destination, departure/arrival bounds, duration, Decimal price, verified availability, transfers and provider as typed hard parameters; originDestinationDurationAndProviderAreHardParameters | b4310d3 |

## Slice 11 — MS-213–226

| ID | Status | Implementation / behavioral evidence | Commit |
| --- | --- | --- | --- |
| MS-213 | VERIFIED_LOCAL | ConnectedAccountsHub provides persisted provider-neutral connection metadata over ProviderAuthenticationBoundary and Keychain credentials with connect/status/disconnect behavior; ConnectedAccountsHubTests | e015ba8 |
| MS-214 | VERIFIED_LOCAL | ProviderAuthorizationMethod.oauth and connect enforce official scoped unexpired token credentials through the shared boundary; oauthRequiresValidScopedUnexpiredToken | c38d23d |
| MS-215 | VERIFIED_LOCAL | ProviderOAuthCredential contains token/scopes/expiry only and no third-party password field or password collection path; ProviderAuthenticationBoundaryTests | c38d23d |
| MS-216 | VERIFIED_LOCAL | unsupported/authenticated providers resolve only to unavailable or exact official sign-in handoff; homepage/security bypass destinations are rejected; homepageIsNotAcceptedAsAuthenticationDestination | c38d23d |
| MS-217 | READY_FOR_LIVE_VERIFICATION | authenticated availability can execute only after a valid minimum-scope OAuth credential and production provider adapter; local authorization/error tests pass; a provider-authorized account is required solely for live protected inventory verification; LIVE_VERIFICATION_QUEUE MS-217 | c38d23d |
| MS-218 | VERIFIED_LOCAL | missing legitimate integration yields publicAccess, exact officialSignInRequired or unavailable without credential fabrication; ProviderAuthenticationBoundaryTests | c38d23d |
| MS-219 | VERIFIED_LOCAL | TravelPlanRequest supports exact origin/destination/deadline and TravelPlanEngine enforces arrival deadline against fresh journeys; arrivalDeadlineAndModesAreHardConstraints | ab0447c |
| MS-220 | VERIFIED_LOCAL | TravelPlanEngine compares only allowed sensible car/rail/coach/flight/ferry journeys with real evidence instead of blindly returning every mode; TravelPlanEngineTests | ab0447c |
| MS-221 | VERIFIED_LOCAL | TravelPlan returns departure/arrival/duration/price/availability/transfers, station access TransportOptions, hotel and weather when verified and explicitly lists missing context; missingSupportingContextIsTruthfulPartialCoverage | ab0447c |
| MS-222 | READY_FOR_LIVE_VERIFICATION | HotelProvider, bounded HotelSearchEngine and authenticated OfficialHotelHTTPProvider implement location/stay/guest/room, verified price/availability and exact booking handoff with local HTTP tests; live provider facts require approved credentials; LIVE_VERIFICATION_QUEUE MS-222 | 75e56dc |
| MS-223 | READY_FOR_LIVE_VERIFICATION | AppleWeatherKitProvider is the production WeatherProvider and maps native current/hourly/daily data with location provenance; a signed entitlement/device response is required solely for live verification; LIVE_VERIFICATION_QUEUE MS-223-225 | 957271a |
| MS-224 | READY_FOR_LIVE_VERIFICATION | WeatherSnapshot models current observed weather from WeatherKit and WeatherContextEngine bounds failures/timeouts; live current response remains queued; LIVE_VERIFICATION_QUEUE MS-223-225 | 957271a |
| MS-225 | READY_FOR_LIVE_VERIFICATION | AppleWeatherKitProvider maps bounded hourly and daily forecasts from native WeatherKit without fabricated values; physical entitlement/live response remains queued; LIVE_VERIFICATION_QUEUE MS-223-225 | 957271a |
| MS-226 | VERIFIED_LOCAL | WeatherRequest and WeatherSnapshot preserve current-location/manual/destination/event/travel context and source provenance; preservesManualLocationProvenanceAndContext | 957271a |

## Slice 12 — MS-227–234

| ID | Status | Implementation / behavioral evidence | Commit |
| --- | --- | --- | --- |
| MS-227 | READY_FOR_LIVE_VERIFICATION | EventKitCalendarService implements permission-gated native EventKit CRUD/query with authoritative read-back; CalendarServiceTests verify validation and exact undo; physical signed-device execution is queued | f14e4b6 |
| MS-228 | READY_FOR_LIVE_VERIFICATION | five-language command parsing plus NaturalDateTimeResolver produce a validated CalendarEventDraft path without AI; live EventKit creation/read-back remains queued | c781956 |
| MS-229 | READY_FOR_LIVE_VERIFICATION | EventKitCalendarService.events performs bounded date-window native EventKit query and returns typed snapshots; live account data requires device permission | f14e4b6 |
| MS-230 | READY_FOR_LIVE_VERIFICATION | EventKitCalendarService.update validates range, resolves exact identifier, saves and authoritatively reads back; undo restores the prior snapshot; live mutation queued | f14e4b6 |
| MS-231 | READY_FOR_LIVE_VERIFICATION | EventKitCalendarService.delete requires an exact identifier and verifies absence after native deletion; ambiguous matching is blocked upstream; live deletion queued | f14e4b6 |
| MS-232 | VERIFIED_LOCAL | NaturalDateTimeResolver deterministically resolves today/tomorrow/day-after-tomorrow and explicit clock time across uk/ru/en/de/fr while preserving caller locale and IANA timezone; ambiguity stays unresolved; NaturalDateTimeResolverTests | c781956 |
| MS-233 | VERIFIED_LOCAL | InteractionDecisionEngine executes resolved reversible calendar create/update through directAction and reserves confirmation for ambiguous/consequential delete; InteractionDecisionEngineTests | 006eb8a |
| MS-234 | READY_FOR_LIVE_VERIFICATION | EventKitReminderService implements permission-gated create/query/update/completion/date-timezone/delete/restore through native EventKit; ReminderServiceTests cover validation and exact undo; device execution queued | a031a90 |

## Slice 13 — MS-235–249

| ID | Status | Implementation / behavioral evidence | Commit |
| --- | --- | --- | --- |
| MS-235 | VERIFIED_LOCAL | SmartDepartureEngine requires typed origin/destination/deadline, fresh sourced TransportOption and separate traffic/parking/walking/safety buffers; SmartDepartureEngineTests | 48f8a09 |
| MS-236 | VERIFIED_LOCAL | DepartureRecommendation deterministically returns the exact departure time and compact factual fields without AI/narration; calculatesEveryCanonicalBufferFromVerifiedRoute | 48f8a09 |
| MS-237 | READY_FOR_LIVE_VERIFICATION | meaningfulUpdate suppresses sub-threshold changes and recalculates from fresh route evidence; live future-event MapKit/provider refresh remains queued | 48f8a09 |
| MS-238 | VERIFIED_LOCAL | persistent rule-based ProactiveWatchEngine schedules bounded deduplicable jobs with no AI dependency; ProactiveWatchEngineTests | cfe78c0 |
| MS-239 | READY_FOR_LIVE_VERIFICATION | traffic watch threshold and NotificationPolicy replacement/deduplication are tested locally; authoritative live traffic observation remains queued | cfe78c0 |
| MS-240 | READY_FOR_LIVE_VERIFICATION | weather watch uses the same fresh-evidence meaningful-change contract and category policy; live WeatherKit event impact remains queued | cfe78c0 |
| MS-241 | READY_FOR_LIVE_VERIFICATION | businessHours watch supports sourced state changes and truthful notification routing; approved live place-hours/alternative provider remains queued | cfe78c0 |
| MS-242 | READY_FOR_LIVE_VERIFICATION | explicitly added enabled product rules persist, expire/cancel, threshold state/price changes and deduplicate; live authorized offer/variant feed remains queued | cfe78c0 |
| MS-243 | READY_FOR_LIVE_VERIFICATION | ticket watch has provider-neutral durable scheduling and meaningful availability/state change triggers; live provider permission/feed remains queued | cfe78c0 |
| MS-244 | VERIFIED_LOCAL | CalendarConflictDetector detects overlap and impossible travel only from fresh sourced route duration; missing/stale route never invents a conflict; CalendarConflictDetectorTests | bd0a237 |
| MS-245 | READY_FOR_LIVE_VERIFICATION | ReminderLocationTrigger validates a typed geofence/proximity and EventKitReminderService writes/reads EKStructuredLocation alarms; signed-device trigger remains queued | 155d2ab |
| MS-246 | VERIFIED_LOCAL | NotificationPolicyEngine enforces global/category toggles, expiry, duplicate suppression and same-event replacement; NotificationPolicyTests | 7c47df7 |
| MS-247 | VERIFIED_LOCAL | LocalActionRouter uses EventKit Reminders and system share/open mechanisms instead of assuming private Apple Notes access; LocalActionRouterTests | d518ea9 |
| MS-248 | NOT_APPLICABLE_VERIFIED | no assistant-owned Notes database exists or is required by a proven capability; system-owned Notes/Reminders data is not duplicated for sync; repository search and AppleSystemDomainIntegration contract | d518ea9 |
| MS-249 | VERIFIED_LOCAL | ordinary shoppingList deterministically routes to EventKit Reminders and creates no parallel assistant list store; LocalActionRouterTests | d518ea9 |

## Slice 14 — MS-250–277

| ID | Status | Implementation / behavioral evidence | Commit |
| --- | --- | --- | --- |
| MS-250 | VERIFIED_LOCAL | UkraineEmergencyPlanner is country-bound and fails closed outside UA; UkraineEmergencyPlannerTests | 234a162 |
| MS-251 | VERIFIED_LOCAL | exact tel:112 user-visible system handoff is emitted for UA without dispatch claim | 234a162 |
| MS-252 | VERIFIED_LOCAL | LocalCommandEngine recognizes 112/ambulance/fire/police emergency language and assigns emergency risk; parser tests | 234a162 |
| MS-253 | READY_FOR_LIVE_VERIFICATION | InteractionDecisionEngine requires confirmation and planner only prepares a tel handoff; no automated test places a call; physical dialer test queued | 234a162 |
| MS-254 | VERIFIED_LOCAL | EmergencyHandoffPlan always keeps claimsDispatch false and state readyForUserCall, never completed | 234a162 |
| MS-255 | READY_FOR_LIVE_VERIFICATION | EmergencyLocationPresenter accepts only fresh validated coordinates/accuracy/address and rejects stale state; physical CoreLocation display queued | 7f24613 |
| MS-256 | READY_FOR_LIVE_VERIFICATION | presenter creates explicit share text and Apple Maps URL with claimsAutomaticTransmission false; physical share sheet queued | 7f24613 |
| MS-257 | VERIFIED_LOCAL | UniversalDeviceCommandRouter centrally selects local, verified app or external capability routes and returns truthful unsupported state; router tests | 6627cff |
| MS-258 | VERIFIED_LOCAL | five-language parser produces typed start/pause/resume/stop recorder actions which drive AudioRecorderController state machine; parser/controller tests | d79542a |
| MS-259 | READY_FOR_LIVE_VERIFICATION | SystemCameraCapture uses public user-visible UIImagePickerController camera and simulator refuses availability; physical capture queued | 762c336 |
| MS-260 | READY_FOR_LIVE_VERIFICATION | LocalContactResolver resolves exact authorized contacts and call path is confirmation-gated tel handoff; physical dialer remains queued | 6627cff |
| MS-261 | READY_FOR_LIVE_VERIFICATION | MessageUI composer and verified messenger handoffs preserve user-controlled send; physical composer/apps remain queued | 19248bb |
| MS-262 | READY_FOR_LIVE_VERIFICATION | EventKitCalendarService provides native permitted CRUD/query/read-back; signed-device EventKit action remains queued | f14e4b6 |
| MS-263 | READY_FOR_LIVE_VERIFICATION | EventKitReminderService provides native permitted CRUD/query/completion/location alarms; signed-device action queued | 155d2ab |
| MS-264 | READY_FOR_LIVE_VERIFICATION | RouteEngine uses MapKit routes and exact public map handoff with sourced duration; physical navigation launch queued | 6627cff |
| MS-265 | READY_FOR_LIVE_VERIFICATION | MediaIntegrationEngine uses MusicKit authorization/catalog/managed playback and truthful unavailable states; entitlement/device queued | 1be2c61 |
| MS-266 | VERIFIED_LOCAL | AppCapabilityRegistry validates and indexes typed third-party app capability records; registry tests | 91a9f4d |
| MS-267 | VERIFIED_LOCAL | AppCapabilityRecord carries identifier, capabilities, mechanisms, actions, auth, limitations, fallback, evidence status and official documentation timestamp | 91a9f4d |
| MS-268 | READY_FOR_LIVE_VERIFICATION | LaunchMarketAppMatrix covers relevant messaging/maps/transport/retail/delivery/taxi/media targets with explicit evidence states; installed-device verification queued | 762c336 |
| MS-269 | READY_FOR_LIVE_VERIFICATION | registry rejects missing official HTTPS documentation/date and unsupported capability claims; current installed versions remain live-queued | 91a9f4d |
| MS-270 | VERIFIED_LOCAL | openOnly records may expose only openApp and router returns open/unsupported rather than invented deeper action; registry tests | 91a9f4d |
| MS-271 | VERIFIED_LOCAL | FindMyFallbackPlanner exposes no location read capability and documents the public API restriction; tests | 538a51b |
| MS-272 | VERIFIED_LOCAL | child-location request resolves only to compliant Find My open/instruction without fabricated location | 538a51b |
| MS-273 | VERIFIED_LOCAL | no private Find My API/bypass exists; fallback planner tests assert zero direct-location claim | 538a51b |
| MS-274 | READY_FOR_LIVE_VERIFICATION | AppleAudioRecordingBackend uses AVAudioSession/AVAudioRecorder and protected app storage; physical microphone path queued | cc58971 |
| MS-275 | READY_FOR_LIVE_VERIFICATION | controller supports start/pause/resume/stop/save/play/rename/delete/share with behavioral state-machine evidence; physical audio/share queued | d79542a |
| MS-276 | READY_FOR_LIVE_VERIFICATION | permission gate and visible RecordingStatusPill prevent secret recording; interruptions pause; physical permission/UI review queued | c34533b |
| MS-277 | VERIFIED_LOCAL | UniversalDeviceCommandRouter plus AppCapabilityRegistry choose deepest validated mechanism without duplicating domain adapters; integration tests | 6627cff |

## Slice 15 — MS-278–304

| ID | Status | Implementation / behavioral evidence | Commit |
| --- | --- | --- | --- |
| MS-278 | VERIFIED_LOCAL | AppCapabilityRegistry orders official direct API first and rejects records without declared mechanisms; integrationHierarchyIsCanonical | e7e5c43 |
| MS-279 | VERIFIED_LOCAL | AppCapabilityRegistry ranks official SDK after direct API; integrationHierarchyIsCanonical | e7e5c43 |
| MS-280 | VERIFIED_LOCAL | typed oauthPartnerAPI follows SDK and retains explicit authentication semantics; integrationHierarchyIsCanonical | e7e5c43 |
| MS-281 | VERIFIED_LOCAL | typed appIntent mechanism precedes shortcuts and links; integrationHierarchyIsCanonical | e7e5c43 |
| MS-282 | VERIFIED_LOCAL | official shortcut is a distinct ranked mechanism; integrationHierarchyIsCanonical | e7e5c43 |
| MS-283 | VERIFIED_LOCAL | universal/deep-link mechanisms are typed and ranked after native intent/shortcut paths; integrationHierarchyIsCanonical | e7e5c43 |
| MS-284 | VERIFIED_LOCAL | structuredFeed is explicit after native links and before web fallback; integrationHierarchyIsCanonical | e7e5c43 |
| MS-285 | VERIFIED_LOCAL | officialWeb requires verified HTTPS destination evidence and ranks after structured data; registry tests | e7e5c43 |
| MS-286 | VERIFIED_LOCAL | phone is a distinct lower-depth user-controlled handoff; IntegrationFallbackPolicyTests | eb698bd |
| MS-287 | VERIFIED_LOCAL | navigation/instruction/open-only are terminal truthful paths, never fabricated direct integrations; registry/router tests | e7e5c43 |
| MS-288 | VERIFIED_LOCAL | IntegrationFallbackPolicy selects the deepest available step; weaker override requires explicit equivalentUserOutcome evidence; testVerifiedEquivalentOverrideRequiresExplicitReason | eb698bd |
| MS-289 | VERIFIED_LOCAL | IntegrationFallbackReason covers unavailable, unsupported, restricted, credential, approval, prohibited and inaccessible conditions and is preserved; testFallbackReasonIsPreservedForTruthfulPresentation | eb698bd |
| MS-290 | VERIFIED_LOCAL | AppCapabilityRecord and provider matrices preserve target, mechanism, actions, auth, limitations, fallback, evidence status and date; registry tests | 91a9f4d |
| MS-291 | VERIFIED_LOCAL | ProviderImplementationStatus has exact fullyImplemented state and fail-closed eligibility; canonicalStatusesFailClosedExceptImplementationAndTestEvidence | 56b0e42 |
| MS-292 | VERIFIED_LOCAL | ProviderImplementationStatus has exact fullyTested state and fail-closed eligibility; canonicalStatusesFailClosedExceptImplementationAndTestEvidence | 56b0e42 |
| MS-293 | VERIFIED_LOCAL | deviceTestRequired is explicit and ineligible for an unqualified production-depth claim; status tests | 56b0e42 |
| MS-294 | VERIFIED_LOCAL | credentialRequired is explicit and ineligible without the external credential; status tests | 56b0e42 |
| MS-295 | VERIFIED_LOCAL | partnerApprovalRequired is explicit and ineligible without approval; status tests | 56b0e42 |
| MS-296 | VERIFIED_LOCAL | fallbackActive is explicit and eligible only as declared truthful fallback; status tests | 56b0e42 |
| MS-297 | VERIFIED_LOCAL | temporarilyBroken is explicit and fails closed; status tests | 56b0e42 |
| MS-298 | VERIFIED_LOCAL | unsupported is explicit and fails closed; status tests | 56b0e42 |
| MS-299 | VERIFIED_LOCAL | typed fallback reasons feed structured selection and no API/HTTP payload becomes a user-facing contract; policy/composer tests | eb698bd |
| MS-300 | VERIFIED_LOCAL | product chain is direct API → structured feed → official web → phone → navigation; testCanonicalDomainChains | eb698bd |
| MS-301 | VERIFIED_LOCAL | restaurant chain is direct booking API → official web → phone → navigation; testCanonicalDomainChains | eb698bd |
| MS-302 | VERIFIED_LOCAL | ticket chain is direct API → authenticated provider → deep link → official app; testCanonicalDomainChains | eb698bd |
| MS-303 | VERIFIED_LOCAL | service chain is direct API → official web → phone; testCanonicalDomainChains | eb698bd |
| MS-304 | VERIFIED_LOCAL | app-action chain is direct API → App Intent → Shortcut → deep link → official app; testCanonicalDomainChains | eb698bd |

## Slice 16 — MS-305–318

| ID | Status | Implementation / behavioral evidence | Commit |
| --- | --- | --- | --- |
| MS-305 | READY_FOR_LIVE_VERIFICATION | CloudKitSyncTransport uses CKContainer.default privateCloudDatabase with bounded pagination, typed codec, account gate, durable tombstones and iCloud entitlement; 9 local sync/lifecycle tests pass; owner CloudKit container and two signed devices are required solely for live sync; LIVE_VERIFICATION_QUEUE MS-305...313 | 242dfda |
| MS-306 | READY_FOR_LIVE_VERIFICATION | SyncRecordKind.preference is permitted by AssistantOwnedSyncScope and round-trips through the production CloudKit codec; live cross-device propagation remains queued | 242dfda |
| MS-307 | READY_FOR_LIVE_VERIFICATION | confirmed assistant-owned contactAlias is a typed permitted sync kind with opaque CloudKit record ID; live two-device propagation remains queued | 242dfda |
| MS-308 | NOT_APPLICABLE_VERIFIED | no assistant-owned Notes feature exists; scope rejects assistantNote unless a future explicit feature is enabled and system Notes are never duplicated; scopeSynchronizesOwnedDomainsAndExcludesDisabledOptionalStores | 242dfda |
| MS-309 | NOT_APPLICABLE_VERIFIED | ordinary shopping lists use EventKit Reminders and no assistant-owned shopping-list store exists; scope rejects the optional kind by default; scope test and LocalActionRouterTests | 242dfda |
| MS-310 | READY_FOR_LIVE_VERIFICATION | savedPlace is a typed permitted sync kind with persistent local record and CloudKit mapping; live two-device propagation remains queued | 242dfda |
| MS-311 | READY_FOR_LIVE_VERIFICATION | proactiveRule is a typed permitted sync kind and sync never executes/replays its action; live two-device propagation remains queued | 242dfda |
| MS-312 | NOT_APPLICABLE_VERIFIED | SyncRecordKind contains no Calendar/Reminder system record; EventKit remains source of truth and its native iCloud sync is not duplicated; sync scope test | 242dfda |
| MS-313 | READY_FOR_LIVE_VERIFICATION | CloudKit private database fetch plus AssistantOwnedDataStore provides restoration input after reinstall while local failure remains nonblocking; signed uninstall/reinstall verification remains queued | 242dfda |
| MS-314 | VERIFIED_LOCAL | SyncReconciler deterministically uses modified time, deletion-wins tie and device-ID final tie-break with one stable record and conflict count; SyncReconcilerTests | 242dfda |
| MS-315 | VERIFIED_LOCAL | AssistantOwnedDataStore.records exposes only its durable typed assistant-owned records; userCanViewEditDeleteClearAndExportDurableOwnedRecords | 242dfda |
| MS-316 | VERIFIED_LOCAL | AssistantOwnedDataStore.upsert replaces the exact stable ID and persists the edit atomically; userCanViewEditDeleteClearAndExportDurableOwnedRecords | 242dfda |
| MS-317 | VERIFIED_LOCAL | exact delete and clear persist tombstones so cloud records cannot silently reappear; userCanViewEditDeleteClearAndExportDurableOwnedRecords | 242dfda |
| MS-318 | VERIFIED_LOCAL | AssistantOwnedDataExport emits portable versioned sorted JSON from the durable store; export behavioral tests | 242dfda |

## Slice 17 — MS-319–334

| ID | Status | Implementation / behavioral evidence | Commit |
| --- | --- | --- | --- |
| MS-319 | VERIFIED_LOCAL | AssistantHomeView is a compact voice-first action surface with one central microphone, status, native result and secondary text input rather than a transcript; AssistantResultStateTests | 58447af |
| MS-320 | VERIFIED_LOCAL | listening state drives a large waveform microphone symbol, concise localized status and accessible stop/start label; AccessibilityAudioPermissionTests | 58447af |
| MS-321 | VERIFIED_LOCAL | AssistantResultState.processing and beginProcessing expose a concise progress state only for perceptible asynchronous work; perceptibleProcessingActionFailureAndExpandedResultsAreTyped | 55c824e |
| MS-322 | VERIFIED_LOCAL | recognized requests render a native CompactResultCard and compact acknowledgements auto-dismiss; successfulCommandProducesCompactResult | 55c824e |
| MS-323 | VERIFIED_LOCAL | actionRequired carries exactly one typed prompt with bounded choices and renders without unrelated controls; typed presentation-state test | 55c824e |
| MS-324 | VERIFIED_LOCAL | failure carries only human-facing message and optional recovery action; CompactResultCard has no raw error/API field; typed presentation-state test | 55c824e |
| MS-325 | VERIFIED_LOCAL | compact acknowledgement timer dismisses while a new result cancels the prior timer; compactConfirmationDismissesAndNewSubmissionCancelsOldTimer | 58447af |
| MS-326 | VERIFIED_LOCAL | expanded is a separate explicit result state while ordinary results remain compact; perceptibleProcessingActionFailureAndExpandedResultsAreTyped | 55c824e |
| MS-327 | READY_FOR_LIVE_VERIFICATION | StartAssistantIntent/AppShortcutsProvider and typed Action Button capability ordering are complete locally; signed device assignment remains owner-controlled; LIVE_VERIFICATION_QUEUE MS-327...330 | 58447af |
| MS-328 | READY_FOR_LIVE_VERIFICATION | QuickLaunchRequestStore consumes the persisted launch once and permitted voice routes directly to listening without narration/tap; physical Action Button latency/path remains queued | 58447af |
| MS-329 | READY_FOR_LIVE_VERIFICATION | policy omits unavailable Action Button and preserves Back Tap/App Shortcut/Home Screen/AssistiveTouch alternatives; physical non-Action-Button device remains queued | 58447af |
| MS-330 | READY_FOR_LIVE_VERIFICATION | official App Intent/App Shortcut plus typed supported alternatives and permission/text fallbacks are implemented and tested; physical system configuration remains queued | 58447af |
| MS-331 | NOT_APPLICABLE_VERIFIED | V1 explicitly excludes Apple Watch and the Xcode project has only app, Share Extension and test targets; project target audit | b837945 |
| MS-332 | NOT_APPLICABLE_VERIFIED | no watchOS product/target/SDK dependency exists in project.pbxproj; project target audit | b837945 |
| MS-333 | NOT_APPLICABLE_VERIFIED | no WatchConnectivity import or runtime path exists; repository integration audit | b837945 |
| MS-334 | VERIFIED_LOCAL | command parsing, action graph, capability registry and service actors are platform-neutral typed cores separable from SwiftUI, preserving future client extensibility without adding watch scope; architecture tests | 6627cff |

## Slice 18 — MS-335–360

| ID | Status | Implementation / behavioral evidence | Commit |
| --- | --- | --- | --- |
| MS-335 | VERIFIED_LOCAL | separate Swift backend target contains tenant-scoped partner onboarding, profiles, operations, agreements, ledger, settlement and feed runtime without coupling consumer UI; backend regression | c63dc57 |
| MS-336 | VERIFIED_LOCAL | PartnerTenantAuthorization and onboarding application contracts provide server-side business identity/access boundary and registration lifecycle; tenant/onboarding tests | c63dc57 |
| MS-337 | VERIFIED_LOCAL | PartnerProfileService implements unclaimed profile registration and explicit claimant transition without automatic verification; profile tests | 1689274 |
| MS-338 | VERIFIED_LOCAL | evidence-gated PartnerOnboardingService and PartnerProfileService implement review/approval verification workflows; onboarding/profile tests | 1689274 |
| MS-339 | VERIFIED_LOCAL | BusinessProfileVerificationState exactly supports UNCLAIMED, PENDING, VERIFIED, REJECTED and SUSPENDED; state-transition tests | 1689274 |
| MS-340 | VERIFIED_LOCAL | PartnerProfileService.update permits profile changes only in VERIFIED state and appends actor/reason audit evidence; profile tests | 1689274 |
| MS-341 | VERIFIED_LOCAL | BusinessOpeningHours stores weekly schedule plus sourceReference/observedAt and rejects future/missing evidence on update; profile tests | 1689274 |
| MS-342 | VERIFIED_LOCAL | BusinessContactDetails supports official phone/HTTPS site/address behind verified-partner update gate; insecure URL test | 1689274 |
| MS-343 | VERIFIED_LOCAL | BusinessOperationsStore applies idempotent normalized partner catalog feed records keyed by partner/provider/external ID with field evidence; BusinessOperationsTests | f88596e |
| MS-344 | VERIFIED_LOCAL | typed variants carry exact Decimal stock and truthful available/unavailable/unknown state; price/stock/deletion/stale feed tests | f88596e |
| MS-345 | VERIFIED_LOCAL | provider-neutral catalog/service connector capabilities cover service data, price and availability without requiring identical connector depth; capability mismatch/partial failure tests | f88596e |
| MS-346 | VERIFIED_LOCAL | normalized commerce offers and catalog items preserve verified price/action/freshness while invalid or stale partner events fail closed; commerce/business operations tests | f88596e |
| MS-347 | VERIFIED_LOCAL | SponsoredCampaign has bounded dates, exact Money budget/spend, language disclosure and enabled state; SponsoredResultSeparationTests | 168f2df |
| MS-348 | VERIFIED_LOCAL | tenant authorization and partner dashboard projections expose only allowed partner analytics without cross-tenant customer/finance access; PartnerTenantAuthorizationTests | c63dc57 |
| MS-349 | VERIFIED_LOCAL | versioned CommercialAgreement plus exact commission ledger/reconciliation/settlement references form the billing boundary without building a payment processor; backend finance tests | 32a0fd2 |
| MS-350 | VERIFIED_LOCAL | SponsoredResultSeparator returns physically separate organic and sponsored arrays; SponsoredResultSeparationTests | 168f2df |
| MS-351 | VERIFIED_LOCAL | sponsored placement requires a nonempty active-language disclosure or is omitted; sponsored tests | 168f2df |
| MS-352 | VERIFIED_LOCAL | organic ranker receives no campaign economics and retains partner/non-partner offers regardless of sponsorship; higherCommissionNeverChangesOrganicOrder | 168f2df |
| MS-353 | VERIFIED_LOCAL | only campaigns tied to an existing eligible offer can render; request constraints remain enforced by the upstream normalized offer pipeline; sponsored/commerce tests | 168f2df |
| MS-354 | VERIFIED_LOCAL | contract-driven monetization enum covers sponsored, subscription and supported result-based models without hardcoded prices; commercial agreement tests | 32a0fd2 |
| MS-355 | VERIFIED_LOCAL | qualifying event and commission model are versioned contract data; click is never assumed payable and conversion lifecycle gates commission; ledger/agreement tests | 32a0fd2 |
| MS-356 | VERIFIED_LOCAL | verification/onboarding/freshness gates apply independently of commercial state; paying partner cannot bypass eligibility or truth controls; onboarding/feed tests | 8fb8acd |
| MS-357 | VERIFIED_LOCAL | PartnerFeedRecord source timestamps and evaluator distinguish VERIFIED_LIVE, PARTNER_PROVIDED_RECENT, STALE and UNKNOWN; feed tests | 8fb8acd |
| MS-358 | VERIFIED_LOCAL | PartnerProfileService.report persists categorized evidence as a review signal without automatic guilt/state change; reportDoesNotAutomaticallyConvictAndSuspensionRequiresAuditedActorReason | 1689274 |
| MS-359 | VERIFIED_LOCAL | onboarding/profile suspension stops active state and MonetizableHandoffGate rejects suspended partners; offboarding/profile tests | 1689274 |
| MS-360 | VERIFIED_LOCAL | critical onboarding/profile transitions and data changes append ordered actor/reason/time audit events; onboarding/profile tests | 1689274 |

## Slice 19 — MS-361–374

| ID | Status | Implementation / behavioral evidence | Commit |
| --- | --- | --- | --- |
| MS-361 | VERIFIED_LOCAL | CostQuotaManager is the central actor gate for non-AI provider API policies and reuses PartnerCostQuotaLedger exact-money enforcement; costQuotaManagerTracksOperationalSignals | 069b18a |
| MS-362 | VERIFIED_LOCAL | ProviderCostUsage exposes provider request/allowed/denied counts, quota decisions and Decimal estimated cost without payload or user identifiers; operational-signals test | 069b18a |
| MS-363 | VERIFIED_LOCAL | typed rateLimited outcomes are idempotently counted per provider operation; operational-signals test | 069b18a |
| MS-364 | VERIFIED_LOCAL | ProviderCostUsage derives deterministic Decimal failureRate from deduplicated outcomes; operational-signals test | 069b18a |
| MS-365 | VERIFIED_LOCAL | cacheHit reservations bypass billable ledger consumption while recording cacheEffectiveness and remaining idempotent; operational-signals test | 069b18a |
| MS-366 | VERIFIED_LOCAL | exact call/cost caps, operation deduplication, cache bypass and remotely ordered provider policy form bounded bill controls; quota and remote-config tests | 069b18a |
| MS-367 | VERIFIED_LOCAL | quota denial is a typed execution gate only and cannot manufacture or modify provider facts; verified-result components retain source/freshness truth contracts; full regression | 069b18a |
| MS-368 | VERIFIED_LOCAL | PartnerRuntimePolicyStore persists versioned, expiring, auditable remote configuration with rollback and backward-compatible decoding; runtime-policy tests | 069b18a |
| MS-369 | VERIFIED_LOCAL | RemoteProviderRule.enabled filters providers without binary changes and fails closed when policy is absent/expired; remote-config test | 069b18a |
| MS-370 | VERIFIED_LOCAL | provider priority is remotely configured and deterministically ordered with provider-ID tie break; remote-config test | 069b18a |
| MS-371 | VERIFIED_LOCAL | provider timeout is remotely configurable only inside validated 100...30000 ms safety bounds; unsafeRemoteTimeoutFailsClosed | 069b18a |
| MS-372 | VERIFIED_LOCAL | provider and feature rules support normalized country allowlists and fail-closed regional rollout; remote-config test | 069b18a |
| MS-373 | VERIFIED_LOCAL | emergencyDisabled removes a provider even when its normal enabled flag is true; remote-config test | 069b18a |
| MS-374 | VERIFIED_LOCAL | typed feature rules target country, category, language and minimum semantic app version with versioned persistence; feature-targeting test | 069b18a |

## Slice 20 — MS-375–380

| ID | Status | Implementation / behavioral evidence | Commit |
| --- | --- | --- | --- |
| MS-375 | VERIFIED_LOCAL | RegionalServiceProfile UA binds Ukrainian retailers, rides, tickets, emergency services, UAH and metric units as service capabilities rather than localization alone; ukraineIsAFullServiceMarketNotOnlyALocale | 1a48751 |
| MS-376 | VERIFIED_LOCAL | country-keyed RegionalServiceRegistry includes typed UA, DE and US profiles and returns unknown for unsupported regions; countrySelectionChangesProvidersEmergencyCurrencyAndUnits | 1a48751 |
| MS-377 | VERIFIED_LOCAL | regional profiles expose retailer provider IDs while reusing UkrainianRetailerRegistry as the source and allow different country sets; regional tests | 1a48751 |
| MS-378 | VERIFIED_LOCAL | regional profiles select distinct ride and ticket provider IDs per country without embedding routing in UI; regional tests | 1a48751 |
| MS-379 | VERIFIED_LOCAL | typed country profiles select emergency service numbers/semantics and preserve user-initiated-call-only safety; regional and UkraineEmergencyPlanner tests | 1a48751 |
| MS-380 | VERIFIED_LOCAL | profiles select ISO currency and metric/US-customary units while existing SafeMoneyComparison forbids implicit cross-currency comparison; regional and locale-safety tests | 1a48751 |

## Slice 21 — MS-381–422

| ID | Status | Implementation / behavioral evidence | Commit |
| --- | --- | --- | --- |
| MS-381 | VERIFIED_LOCAL | privacy manifest/data map and data-minimized telemetry limit collection to enabled functions; privacy and telemetry tests | 7a6cd05 |
| MS-382 | VERIFIED_LOCAL | ContextualPermissionPolicy requests nothing at launch and gates microphone/notification/location by feature trigger; permission tests | c34533b |
| MS-383 | VERIFIED_LOCAL | voice/recorder/location enter stable denied states without retry/crash and typed input remains usable; denied tests | 7a6cd05 |
| MS-384 | VERIFIED_LOCAL | denied voice state exposes one concise UIApplication Settings link only while useful; denied recovery test | 7a6cd05 |
| MS-385 | VERIFIED_LOCAL | provider credentials use scoped this-device-only Keychain while server secrets are runtime injected; auth/security tests | c38d23d |
| MS-386 | VERIFIED_LOCAL | production clients require runtime credentials and secret-pattern scan found no app production secret; security audit | 1a5ecf7 |
| MS-387 | VERIFIED_LOCAL | repository secret-pattern verification plus hosted standard scan report no committed production secret; M10 audit | 1a5ecf7 |
| MS-388 | VERIFIED_LOCAL | optional AI config persists only a Keychain/server reference, never credential text; configuration/auth tests | c38d23d |
| MS-389 | VERIFIED_LOCAL | telemetry has no raw command/URL/payload/user-ID field and rejects free-text dimensions; telemetry privacy test | 7a6cd05 |
| MS-390 | VERIFIED_LOCAL | PrivacySafeProductMetrics aggregates bounded feature IDs/counts without content; aggregate test | 7a6cd05 |
| MS-391 | VERIFIED_LOCAL | performance/coordination/product record command/provider/critical-path completion durations; performance tests | 7a6cd05 |
| MS-392 | VERIFIED_LOCAL | connectorFailure and connectorFallback counters provide aggregate reliability/fallback frequency; aggregate test | 7a6cd05 |
| MS-393 | VERIFIED_LOCAL | crashSignal ingests only infrastructure occurrence without stack/private payload; telemetry test | 7a6cd05 |
| MS-394 | VERIFIED_LOCAL | cold/warm launch typed durations and release budgets measure responsiveness; performance tests | 7a6cd05 |
| MS-395 | VERIFIED_LOCAL | voiceToCommand duration aggregates without transcript; telemetry test | 7a6cd05 |
| MS-396 | VERIFIED_LOCAL | commandToAction duration aggregates without command/action payload; telemetry test | 7a6cd05 |
| MS-397 | VERIFIED_LOCAL | memoryPressure is counted and resource policy reduces concurrency/cache and purges work; resource tests | 7a6cd05 |
| MS-398 | VERIFIED_LOCAL | AssistantResultFailure exposes only human message/recovery while provider errors stay typed internally; presentation tests | 55c824e |
| MS-399 | VERIFIED_LOCAL | bounded request-keyed LRU cache reuses stable normalized results; cache tests | 94e56d9 |
| MS-400 | VERIFIED_LOCAL | cache TTL/source evidence reject stale live-sensitive offers as current; stale-offer tests | 94e56d9 |
| MS-401 | VERIFIED_LOCAL | inventory retains observed time, confidence and known/unknown availability; commerce/feed freshness tests | 94e56d9 |
| MS-402 | VERIFIED_LOCAL | ride engine rejects quote/ETA outside its short freshness window; ride tests | 94e56d9 |
| MS-403 | VERIFIED_LOCAL | ticket engine requires current sourced inventory and prevents stale purchase; ticket tests | 8f78ab4 |
| MS-404 | VERIFIED_LOCAL | reservation engine requires fresh provider availability and never equates handoff with booking; restaurant tests | 7a6cd05 |
| MS-405 | VERIFIED_LOCAL | transport/departure require fresh real-time route evidence and reject stale traffic; transport tests | 7a6cd05 |
| MS-406 | VERIFIED_LOCAL | place freshness derives from source time so open-now is never permanently cached; place tests | 7a6cd05 |
| MS-407 | VERIFIED_LOCAL | REAL_DEVICE_TEST_MATRIX tracks each device-only capability, reason and queue reference; matrix audit | 6ec7080 |
| MS-408 | VERIFIED_LOCAL | matrix/policy keep simulator success separate from physical VERIFIED_LIVE evidence; queue audit | 6ec7080 |
| MS-409 | READY_FOR_LIVE_VERIFICATION | microphone production/local path complete; physical audio test queued MS-409...422 | 01378bd |
| MS-410 | READY_FOR_LIVE_VERIFICATION | Speech framework/mixed-language path locally tested; physical speech queued | 01378bd |
| MS-411 | READY_FOR_LIVE_VERIFICATION | location/suspicious recovery locally complete; moving physical GPS queued | 01378bd |
| MS-412 | READY_FOR_LIVE_VERIFICATION | App Intent quick launch locally complete; supported-device Action Button queued | 01378bd |
| MS-413 | READY_FOR_LIVE_VERIFICATION | Contacts permission/resolution locally complete; physical Contacts queued | 01378bd |
| MS-414 | READY_FOR_LIVE_VERIFICATION | Calendar CRUD/permission locally complete; physical EventKit queued | 01378bd |
| MS-415 | READY_FOR_LIVE_VERIFICATION | Reminders CRUD/permission locally complete; physical EventKit queued | 01378bd |
| MS-416 | READY_FOR_LIVE_VERIFICATION | phone handoff locally validated without completion claim; physical cancel/handoff queued | 01378bd |
| MS-417 | READY_FOR_LIVE_VERIFICATION | message compose/handoff safety locally tested; physical composition queued | 01378bd |
| MS-418 | READY_FOR_LIVE_VERIFICATION | notification contracts locally verified; signed-device delivery queued | 01378bd |
| MS-419 | READY_FOR_LIVE_VERIFICATION | schemes/Universal Links locally tested; installed-app execution queued | 01378bd |
| MS-420 | READY_FOR_LIVE_VERIFICATION | missing-app fallback is truthful locally; physical absence queued | 01378bd |
| MS-421 | READY_FOR_LIVE_VERIFICATION | offline/timeout/partial failure locally tested; physical network transitions queued | 01378bd |
| MS-422 | READY_FOR_LIVE_VERIFICATION | permission-state paths locally tested; physical combinations queued | 01378bd |
| MS-423 | VERIFIED_LOCAL | TestFlight/device preparation is captured in REAL_DEVICE_TEST_MATRIX, OWNER_TEST_QUEUE and RELEASE_CHECKLIST without claiming distribution; governance tests | 6ec7080 |
| MS-424 | VERIFIED_LOCAL | device-diversity matrix covers supported iPhone sizes, OS versions and capability combinations for later physical execution; matrix audit | 6ec7080 |
| MS-425 | VERIFIED_LOCAL | executable GoldenUserJourney corpus includes substantial Ukrainian commands across 21 journey families; corpus acceptance tests | aabe915 |
| MS-426 | VERIFIED_LOCAL | executable GoldenUserJourney corpus includes substantial Russian commands across 21 journey families; corpus acceptance tests | aabe915 |
| MS-427 | VERIFIED_LOCAL | executable GoldenUserJourney corpus includes substantial English commands across 21 journey families; corpus acceptance tests | aabe915 |
| MS-428 | VERIFIED_LOCAL | executable GoldenUserJourney corpus includes substantial German commands across 21 journey families; corpus acceptance tests | aabe915 |
| MS-429 | VERIFIED_LOCAL | executable GoldenUserJourney corpus includes substantial French commands across 21 journey families; corpus acceptance tests | aabe915 |
| MS-430 | VERIFIED_LOCAL | mixed Ukrainian/Russian and mixed-language brand commands are parsed by deterministic routing; language/corpus tests | aabe915 |
| MS-431 | VERIFIED_LOCAL | corpus and structured parser exercise names, addresses, brands and product models without fixed retailer routing; parser tests | aabe915 |
| MS-432 | VERIFIED_LOCAL | colloquial and imperfect command variants remain executable corpus cases; corpus acceptance tests | aabe915 |
| MS-433 | VERIFIED_LOCAL | concrete provider adapters and bounded fanout tests verify normal successful normalized responses | 928f150 |
| MS-434 | VERIFIED_LOCAL | provider fanout/adapters distinguish an empty verified result from connector failure; empty-response tests | 928f150 |
| MS-435 | VERIFIED_LOCAL | malformed provider payloads fail schema/decoding validation without fabricated results; adapter tests | 928f150 |
| MS-436 | VERIFIED_LOCAL | provider timeout is bounded, cancelled and surfaced as typed partial failure; fanout timeout tests | 928f150 |
| MS-437 | VERIFIED_LOCAL | rate-limit responses map to typed unavailable/retry-aware failure without blocking alternatives; adapter tests | 928f150 |
| MS-438 | VERIFIED_LOCAL | provider outage remains isolated and available verified alternatives are returned; partial-failure tests | 928f150 |
| MS-439 | VERIFIED_LOCAL | authorized and credential-required/unauthorized states are explicit at adapter boundaries; authentication tests | c38d23d |
| MS-440 | VERIFIED_LOCAL | fallback activates only on typed provider failure and returns concise truthful unavailable/partial state; fanout tests | 928f150 |
| MS-441 | VERIFIED_LOCAL | unavailable credentials retain complete runtime injection boundary, explicit CREDENTIAL_REQUIRED status and persistent live queue while independent work continues; governance tests | c38d23d |
| MS-442 | VERIFIED_LOCAL | partner-approval dependencies preserve implemented adapter/fallback contracts and exact live action in persistent queue; provider matrix audit | 6ec7080 |
| MS-443 | VERIFIED_LOCAL | authentication contracts prohibit CAPTCHA/2FA bypass and expose legitimate user/provider handoff only; security/auth tests | c38d23d |
| MS-444 | VERIFIED_LOCAL | provider-specific request/response logic is isolated behind typed adapter protocols and normalized domains; adapter tests | 928f150 |
| MS-445 | VERIFIED_LOCAL | versioned backend route and webhook contracts preserve ordinary client compatibility; ADR-0005 and API contract tests | 8e9f92c |
| MS-446 | VERIFIED_LOCAL | LocalStore executes versioned transactional migrations with rollback-safe validation and migration regression tests | f866914 |
| MS-447 | VERIFIED_LOCAL | entitlements, privacy manifest, permission use and release gates encode App Store-compliant public integration paths; release audit | e0dd6a3 |
| MS-448 | VERIFIED_LOCAL | platform-sensitive system integrations are mapped to current public Apple framework boundaries in Apple-system-domain audit | 762c336 |
| MS-449 | VERIFIED_LOCAL | capability registry selects the closest legitimate public mechanism or truthful handoff/unavailable result when direct execution is unavailable; routing tests | 762c336 |
| MS-450 | VERIFIED_LOCAL | repository platform audit and production integrations use public framework APIs only; prohibited-path scan | 762c336 |
| MS-451 | VERIFIED_LOCAL | Apple system-domain integration audit prohibits jailbreak-style mechanisms and exposes public capability or truthful fallback only; audit tests | 762c336 |
| MS-452 | VERIFIED_LOCAL | cross-app actions use App Intents, public URL schemes, share/compose controllers or user handoff, never screen scraping/automation; routing tests | 762c336 |
| MS-453 | VERIFIED_LOCAL | APP_STORE_RELEASE_METADATA provides owner-selectable truthful name candidates without claiming availability; artifact audit test | 401ee00 |
| MS-454 | VERIFIED_LOCAL | release metadata contains a capability-bounded description draft that distinguishes deterministic, optional-AI and provider-dependent behavior; artifact audit test | 401ee00 |
| MS-455 | VERIFIED_LOCAL | release metadata privacy inventory maps local data, contextual permissions, telemetry, credentials and commercial disclosure to current production paths; artifact audit test | 401ee00 |
| MS-456 | VERIFIED_LOCAL | production configurations contain capability-specific permission descriptions and release metadata defines rejection rules for vague/unused permission copy; configuration/audit tests | 401ee00 |
| MS-457 | VERIFIED_LOCAL | screenshot plan covers canonical local flows, truthful unavailable states, themes and accessibility while prohibiting fabricated live facts; artifact audit test | 401ee00 |
| MS-458 | VERIFIED_LOCAL | support/privacy HTTPS URL ownership, content and approval requirements are explicit without submitting placeholders; artifact audit test | 401ee00 |
| MS-459 | VERIFIED_LOCAL | App Review notes draft explains permissions, public APIs, deterministic/AI behavior, consequential safety and truthful handoffs; artifact audit test | 401ee00 |
| MS-460 | VERIFIED_LOCAL | RELEASE_CHECKLIST gates configurations, privacy, CI, device matrix, signing, metadata, commerce disclosure and factual claims | e0dd6a3 |
| MS-461 | VERIFIED_LOCAL | release governance leaves signing/TestFlight/App Store as owner actions while all local engineering continues independently; release checklist audit | 401ee00 |
| MS-462 | VERIFIED_LOCAL | project/configuration/release artifacts are prepared for later legitimate TestFlight signing without claiming distribution; production engineering audit | 401ee00 |
| MS-463 | VERIFIED_LOCAL | review-account strategy requires dedicated least-privilege staging accounts, secure review-channel delivery, expiry/revocation and no fake success; artifact audit test | 401ee00 |
| MS-464 | VERIFIED_LOCAL | Development xcconfig and target configuration are explicit and buildable; configuration build evidence | b0d0fc2 |
| MS-465 | VERIFIED_LOCAL | Staging xcconfig and isolated target configuration are explicit and buildable; M2 staging build evidence | b0d0fc2 |
| MS-466 | VERIFIED_LOCAL | Production xcconfig and production/share identifiers are explicit without embedded credentials; configuration audit | b0d0fc2 |
| MS-467 | VERIFIED_LOCAL | device credentials use Keychain and backend secrets use runtime environment/secure storage boundaries, with repository secret scan | c38d23d |
| MS-468 | VERIFIED_LOCAL | primary orb, input, results and actions expose meaningful VoiceOver labels/combined semantics; localization accessibility tests | c34533b |
| MS-469 | VERIFIED_LOCAL | UI uses semantic text styles and accessibility-size layouts without a fixed Dynamic Type ceiling; localization accessibility tests | c34533b |
| MS-470 | VERIFIED_LOCAL | primary microphone/action controls provide at least 44-point hit targets and meaningful accessible names; accessibility tests | c34533b |
| MS-471 | VERIFIED_LOCAL | subscription presentation uses factual StoreKit-derived product/entitlement states and no coercive upgrade path; entitlement tests | 1045668 |
| MS-472 | VERIFIED_LOCAL | sponsored results are structurally separate and require localized disclosure before rendering; sponsored separation tests | 168f2df |
| MS-473 | VERIFIED_LOCAL | ContextualPermissionPolicy requests no permission at launch and only the exact capability-triggered permission; permission tests | c34533b |
| MS-474 | VERIFIED_LOCAL | account deletion and subscription management expose direct legitimate system/provider flows without obscuring cancellation; account/entitlement tests | 1045668 |
| MS-475 | VERIFIED_LOCAL | UI/result models use verified availability/freshness and contain no synthetic scarcity countdown or urgency state; commerce presentation tests | 94e56d9 |
| MS-476 | VERIFIED_LOCAL | production domains are covered by behavior-focused Swift Testing/XCTest suites and backend tests; full regression gate | fab773a |
| MS-477 | VERIFIED_LOCAL | LocalCommandEngine tests validate intent, entity, constraint, date/language and exact canonical command routing | fab773a |
| MS-478 | VERIFIED_LOCAL | concrete HTTP/provider adapter suites validate request construction, decoding, authentication and truthful failure mapping | 928f150 |
| MS-479 | VERIFIED_LOCAL | iOS integration-boundary and backend route/webhook suites exercise normalized provider/server contracts | 928f150 |
| MS-480 | VERIFIED_LOCAL | explicit suites cover timeout, cancellation, malformed/auth/rate/outage, stale and partial-failure paths | 928f150 |
| MS-481 | VERIFIED_LOCAL | critical home/result/permission/quick-launch interaction policies and SwiftUI-facing states have executable workflow tests | 58447af |
| MS-482 | VERIFIED_LOCAL | parser throughput, provider concurrency/critical path, cache and product latency metrics have bounded performance tests | 7a6cd05 |
| MS-483 | VERIFIED_LOCAL | canonical scenario and domain tests assert typed outcomes, constraints, safety and persistence rather than symbol existence or count alone | fab773a |
| MS-484 | VERIFIED_LOCAL | chaos fanout test uses a provider that never resumes and verifies bounded timeout/cancellation | 928f150 |
| MS-485 | VERIFIED_LOCAL | late provider response is cancelled and cannot leak into the completed aggregate | 928f150 |
| MS-486 | VERIFIED_LOCAL | simultaneous backend/provider outage returns typed failure while preserving verified local partial results | 928f150 |
| MS-487 | VERIFIED_LOCAL | mid-request network loss follows the same bounded cancellation/partial-result contract without hanging | 928f150 |
| MS-488 | VERIFIED_LOCAL | LocationValidator rejects suspicious jumps and accepts later accurate recovery evidence; location tests | d7a0dfc |
| MS-489 | VERIFIED_LOCAL | multi-provider simultaneous failure is isolated and does not suppress available verified alternatives | 928f150 |
| MS-490 | VERIFIED_LOCAL | new command cancels obsolete command work and stale completion cannot publish a result | 928f150 |
| MS-491 | VERIFIED_LOCAL | bounded optional-AI failures/timeouts produce immediate deterministic fallback with no recursive attempt; fallback tests | ca92a6f |
| MS-492 | VERIFIED_LOCAL | missing target app resolves through typed web/App Store/system fallback without claiming app execution | eb698bd |
| MS-493 | VERIFIED_LOCAL | microphone/location/contacts/calendar/reminders/notifications denial paths remain stable, truthful and typed-input capable; permission tests | c34533b |
| MS-494 | VERIFIED_LOCAL | capability, provider, persistence, policy and presentation code remains separated into scoped production components; engineering audit | fab773a |
| MS-495 | VERIFIED_LOCAL | unrelated domains are owned by separate engines/actors and AssistantViewModel delegates rather than implementing provider/domain logic | fab773a |
| MS-496 | VERIFIED_LOCAL | shared bounded fanout, authentication, freshness and fallback abstractions prevent copied provider control flow; adapter tests | 928f150 |
| MS-497 | VERIFIED_LOCAL | user-facing core strings use five-language LocalizedStrings/policy mappings and localization layout tests detect missing labels | c34533b |
| MS-498 | VERIFIED_LOCAL | mutable runtime state is instance-scoped or actor-isolated; no unbounded mutable singleton owns command/provider state; concurrency tests | fab773a |
| MS-499 | VERIFIED_LOCAL | exact «Хочу кави» routes to place search and follows concise result policy; canonical scenario and place tests | fab773a |
| MS-500 | VERIFIED_LOCAL | exact pharmacy-along-route command routes to route-aware search backed by validated active-route context; canonical/context tests | fab773a |
| MS-501 | VERIFIED_LOCAL | exact tomorrow-dentist command routes to reversible calendar creation with EventKit boundary; canonical/calendar tests | fab773a |
| MS-502 | VERIFIED_LOCAL | exact dentist reschedule command has calendar-update priority over service discovery; canonical/calendar tests | fab773a |
| MS-503 | VERIFIED_LOCAL | exact dentist cancellation routes to calendar deletion rather than generic service/cancel intent; canonical/calendar tests | fab773a |
| MS-504 | VERIFIED_LOCAL | exact undo phrase routes to typed reversible undo and action history protects unrelated actions; canonical/history tests | fab773a |
| MS-505 | VERIFIED_LOCAL | exact call-Mum command routes to contact resolution and consequential call handoff; canonical/device-router tests | fab773a |
| MS-506 | VERIFIED_LOCAL | exact Oleg message command routes to compose flow without claiming delivery; canonical/messaging tests | fab773a |
| MS-507 | VERIFIED_LOCAL | exact navigate-home command routes to validated saved-place/navigation action; canonical/navigation tests | fab773a |
| MS-508 | VERIFIED_LOCAL | exact Baldinini collection command routes to fashion discovery with brand extraction and truthful offer results; canonical/fashion tests | fab773a |
| MS-509 | VERIFIED_LOCAL | exact Baldinini size command preserves brand and size as hard product constraints; canonical/parser/commerce tests | fab773a |
| MS-510 | VERIFIED_LOCAL | exact four-store basket command routes to grocery comparison using verified comparable totals; canonical/grocery tests | fab773a |
| MS-511 | VERIFIED_LOCAL | exact maximum-two-store split command routes to grocery optimizer whose exhaustive search enforces the store cap; canonical/grocery tests | fab773a |
| MS-512 | VERIFIED_LOCAL | exact cheapest-taxi command routes to deterministic taxi comparison with verified price/ETA only; canonical/ride tests | fab773a |
| MS-513 | VERIFIED_LOCAL | exact maximum-wait taxi command routes to taxi search and retains typed hard wait constraint for provider comparison; canonical/ride tests | 8ecf360 |
| MS-514 | VERIFIED_LOCAL | exact tow request routes to typed towTruck local-service category and truthful contact/action result; canonical/service tests | fab773a |
| MS-515 | VERIFIED_LOCAL | exact Lviv arrival-deadline request routes to travel planning with hard deadline handling; canonical/travel tests | fab773a |
| MS-516 | VERIFIED_LOCAL | exact 112 command is typed emergency risk and automated tests validate confirmation/handoff without placing a call | fab773a |
| MS-517 | VERIFIED_LOCAL | exact recorder command routes to start action while permission and recorder state remain production-controlled; canonical/audio tests | fab773a |
| MS-518 | VERIFIED_LOCAL | exact open-second command retains ordinal and resolves only fresh bounded prior results; canonical/context tests | fab773a |
| MS-519 | VERIFIED_LOCAL | exact show-route command routes to native route presentation/action rather than generic show | fab773a |
| MS-520 | VERIFIED_LOCAL | dentist+Sensodyne+departure compound command routes to typed multi-step coordination; canonical/coordination tests | fab773a |
| MS-521 | VERIFIED_LOCAL | bounded CurrentContext resolves fresh ordinal/open, cheaper, navigation, call, reschedule, route-aware and pending-task confirmation follow-ups; context tests | b289278 |
| MS-522 | VERIFIED_LOCAL | CurrentContext caps recent results, expires session state and resets all contextual data rather than retaining an unlimited transcript; context tests | 8e7a96c |
| MS-523 | VERIFIED_LOCAL | context stores typed entities/routes/tasks/service state and explicit key-value preferences with provenance instead of conversational prose; context tests | 8e7a96c |
| MS-524 | VERIFIED_LOCAL | durable presentation/account preferences are written only through explicit settings/policy APIs; inferred command behavior is not persisted; configuration tests | ffd98a9 |
| MS-525 | VERIFIED_LOCAL | context and telemetry models have no inferred demographic/sensitive-attribute fields and external payload is field-allowlisted; privacy/context tests | 8e7a96c |
| MS-526 | VERIFIED_LOCAL | AccountPolicy and allowance ledger implement configurable registered-Free entitlements and reset rules without duplicated feature pricing logic; policy tests | 6a8e0e4 |
| MS-527 | VERIFIED_LOCAL | verified StoreKit entitlement state gates Premium capabilities and configurable product identifiers; entitlement tests | 1045668 |
| MS-528 | NOT_APPLICABLE_VERIFIED | production account/entitlement taxonomy intentionally contains no Family tier and canonical owner approval has not enabled it; policy tests | 6a8e0e4 |
| MS-529 | VERIFIED_LOCAL | sponsored/business commercial models, campaigns and ledgers remain separate from commission-independent consumer organic ranking; separation tests | 168f2df |
| MS-530 | VERIFIED_LOCAL | subscription price/period comes from verified StoreKit product metadata and product policy/configuration, never a final hardcoded price; entitlement tests | 1045668 |
| MS-531 | VERIFIED_LOCAL | deterministic fast paths and multi-module coordination assert zero AI invocations; bounded fallback is optional and owner-cost metadata remains observable | 27ad853 |
| MS-532 | VERIFIED_LOCAL | CostQuotaManager exposes exact Decimal non-AI provider cost, currency, requests, failures, rate limits and cache hits; runtime-policy tests | 069b18a |
| MS-533 | VERIFIED_LOCAL | runtime-key HMAC bearer authentication validates signature, audience, expiry and scoped claims before creating a backend principal; authentication tests | 3bac3e3 |
| MS-534 | VERIFIED_LOCAL | tenant data access enforces role, permission and exact partner scope server-side with audited denials; isolation tests | 81d4161 |
| MS-535 | VERIFIED_LOCAL | principal-scoped ingress rate limiter bounds requests per window while provider quotas and webhook limits add layered abuse control; limiter tests | 3bac3e3 |
| MS-536 | VERIFIED_LOCAL | partner fraud controls detect fake/duplicate/self-referral/manipulation signals, require review and never auto-convict; fraud tests | 61523e2 |
| MS-537 | VERIFIED_LOCAL | in-app account deletion coordinator and provider deletion boundary expose explicit deletion flow with partial-failure reporting; lifecycle tests | c38d23d |
| MS-538 | VERIFIED_LOCAL | backend cleanup removes account jobs, APNs tokens and provider connections while retention policy handles lawful bounded residuals; cleanup/retention tests | c38d23d |
| MS-539 | VERIFIED_LOCAL | cold/warm launch metrics, evidence-based budgets and release checklist gate launch responsiveness review; performance tests | 7a6cd05 |
| MS-540 | VERIFIED_LOCAL | voice-to-command latency is measured without transcript content and physical audio timing remains explicitly queued; performance tests | 7a6cd05 |
| MS-541 | VERIFIED_LOCAL | bounded fanout tests exercise timeout, cancellation, late response, outage and truthful fallback; chaos tests | 928f150 |
| MS-542 | VERIFIED_LOCAL | resource policy bounds concurrency/cache, reacts to memory pressure and records battery-sensitive operational review gates; resource tests | ffd98a9 |
| MS-543 | VERIFIED_LOCAL | never-returning provider, cancellation and replacement-command tests prove no permanent spinner/UI wait; chaos/result-state tests | 928f150 |
| MS-544 | VERIFIED_LOCAL | full regression and failure-path suites are release gates; reproducible critical failure prevents a green release checklist | 928f150 |
| MS-545 | VERIFIED_LOCAL | Golden journey tap/question metrics and direct-action policy identify removable friction while preserving safety confirmation | aabe915 |
| MS-546 | VERIFIED_LOCAL | source timestamp/freshness/knowledge models and cross-domain tests reject unverified live facts as current | 94e56d9 |
| MS-547 | VERIFIED_LOCAL | Development iPhone simulator application, Share Extension and tests build successfully from the committed Xcode project | 5898cd5 |
| MS-548 | VERIFIED_LOCAL | simulator launch/test host completes without crash or blocking startup permission requests; application lifecycle tests | 5898cd5 |
| MS-549 | VERIFIED_LOCAL | Ukrainian, Russian, English, German and French parser, voice corpus and UI localization breadth is executable | aabe915 |
| MS-550 | VERIFIED_LOCAL | 100 golden journeys plus exact MS-499–520 scenario matrix exercise core command flows and typed outcomes | fab773a |
| MS-551 | VERIFIED_LOCAL | production Apple domains use public framework/App Intent/URL/handoff mechanisms and prohibited API audit is green | 762c336 |
| MS-552 | VERIFIED_LOCAL | contextual permission policy, denied states, Settings recovery and typed fallback are behavior-tested | 7a6cd05 |
| MS-553 | VERIFIED_LOCAL | backend/network/provider failures time out, isolate partial results and never freeze the command surface | 928f150 |
| MS-554 | VERIFIED_LOCAL | integration depth auditor and capability matrix require a concrete adapter/path or evidence-backed unsupported fallback per major integration | 6ec7080 |
| MS-555 | VERIFIED_LOCAL | INTEGRATION_STATUS records accurate local/live/blocker status and is checked against capability evidence governance | 6ec7080 |
| MS-556 | VERIFIED_LOCAL | evidence governance rejects mock-only/fake production routes and generic completion without E3 behavioral evidence | 27da423 |
| MS-557 | VERIFIED_LOCAL | IntegrationFallbackPolicy selects the deepest legitimate direct, official handoff, web or unavailable result without fake success | eb698bd |
| MS-558 | VERIFIED_LOCAL | explicit tests cover slow/failed providers, network loss, late cancellation, obsolete work and responsive partial UI | 928f150 |
| MS-559 | VERIFIED_LOCAL | InteractionDecisionEngine and voice-output policy execute unambiguous commands without narration or unnecessary confirmation | ffd98a9 |
| MS-560 | VERIFIED_LOCAL | price/stock/availability/ticket/booking/taxi/location facts require verified source and valid freshness across normalized domains | 94e56d9 |
| MS-561 | VERIFIED_LOCAL | automated iOS and backend regression gates execute behavior-focused suites and pass at this checkpoint | 5898cd5 |
| MS-562 | VERIFIED_LOCAL | REAL_DEVICE_TEST_MATRIX and persistent live queue enumerate every physical-only capability, action and expected result without simulator promotion | 6ec7080 |
| MS-563 | VERIFIED_LOCAL | provider matrix/live queue record exact credential, approval, account, device and owner dependencies instead of hiding them | 6ec7080 |
| MS-564 | VERIFIED_LOCAL | Xcode configurations, release metadata, privacy/permission artifacts, TestFlight matrix, review notes and blocker queue are locally prepared and audited | 401ee00 |
| MS-565 | VERIFIED_LOCAL | release state/checklist explicitly says signing, TestFlight and App Store owner actions are incomplete; no publication claim exists | 401ee00 |

| MS-566 | VERIFIED_LOCAL | iOS deployment target, app target and explicit no-watchOS project scope keep V1 iPhone-only; Xcode project build | 7a6cd05 |
| MS-567 | VERIFIED_LOCAL | AssistantHomeView and deterministic direct-action/result policy provide a lighter single request→result→action surface; UI workflow tests | 7a6cd05 |
| MS-568 | VERIFIED_LOCAL | primary Home is voice/text-first with only tasks/favorites secondary navigation, not a category maze; localization/accessibility UI tests | 7a6cd05 |
| MS-569 | VERIFIED_LOCAL | AssistantHomeView contains orb/microphone, compact state/result, typed input, settings/quick-launch and minimal tabs; UI workflow tests | 7a6cd05 |
| MS-570 | VERIFIED_LOCAL | QuickLaunchPolicy exposes only available public system mechanisms and StartAssistantIntent opens the app; policy tests cover unavailable Action Button and permission/text fallback, while physical behavior remains queued | 58447af |
| MS-571 | VERIFIED_LOCAL | proactive work uses bounded server jobs/notifications and app scene lifecycle stops transient listening; proactive and lifecycle tests | d6c79b7 |
| MS-572 | VERIFIED_LOCAL | backend ProactiveWatchEngine and DurableProactiveJobQueue own recurring external checks without continuous iPhone execution; backend tests | d6c79b7 |
| MS-573 | VERIFIED_LOCAL | provider capability/evidence governance plus generic retrieval access validation rejects prohibited/blocked/CAPTCHA paths and preserves legitimate fallback; integration and generic discovery tests | 2037125 |
| MS-574 | VERIFIED_LOCAL | official-source/fallback routers require exact HTTPS path and reject homepages/unapproved hosts; fashion/local-service/fallback tests | eb698bd |
| MS-575 | VERIFIED_LOCAL | LocalServiceHandoffPlanner selects resolved callable provider phone before navigation when deeper verified action is absent; local-service tests | eb698bd |
| MS-576 | VERIFIED_LOCAL | IntegrationFallbackPolicy retains exact official web/phone/navigation or truthful unavailable functionality when direct API is absent; fallback tests | eb698bd |
| MS-577 | VERIFIED_LOCAL | IntegrationDepthAuditor and provider matrices require researched deeper legitimate paths before fallback and reject generic unsupported claims; governance tests | eb698bd |
| MS-578 | VERIFIED_LOCAL | M4_UA_RETAILER_SOURCE_MATRIX and provider capability matrix record official Ukrainian integration avenues, source URLs, limitations and review state; artifact audits | eb698bd |
| MS-579 | VERIFIED_LOCAL | Calendar, reminders, contacts, notes, recorder and local search implementations do not require backend and preserve useful local operation under provider/backend failure; failure tests | 928f150 |
| MS-580 | VERIFIED_LOCAL | normalized truth/freshness models render unavailable/unknown rather than live traffic, stock, quote, ticket, booking or business claims when offline; truth/failure tests | 94e56d9 |
| MS-581 | VERIFIED_LOCAL | repository scope/status and security audit contain only UniversalAssistant project assets and no trading-VPS deployment/configuration path; repository audit | 27da423 |
| MS-582 | VERIFIED_LOCAL | Xcode project, Simulator builds and local development run in designated Mac repository with Git remote persistence; build and repository-state evidence | 5898cd5 |
| MS-583 | VERIFIED_LOCAL | existing UniversalAssistant repository uses configured origin and commits/pushes canonical state without a duplicate repository; Git verification | 5898cd5 |
| MS-584 | VERIFIED_LOCAL | change inventory and security/release audits remain repository-scoped with no unrelated system-wide mutation; audit evidence | 27da423 |
| MS-585 | VERIFIED_LOCAL | execution state, heartbeat, attempt ledger and autonomous continuation contracts preserve resumable progress without idle approval waits; governance tests | 27da423 |
| MS-586 | VERIFIED_LOCAL | owner/system permissions remain explicit external dependencies; no TCC/password bypass exists and independent local work continues through live queue | 27da423 |
| MS-587 | VERIFIED_LOCAL | build/test/repository workflows use project/user-space tools and make no root/admin assumption; CI and environment audit | 5898cd5 |
| MS-588 | VERIFIED_LOCAL | startup/state audit captures Xcode/project/SDK/destination/Git/repository/build readiness and release signing dependencies; environment evidence | 5898cd5 |
| MS-589 | VERIFIED_LOCAL | Live Verification Queue records exact external dependencies/actions while production boundaries, fallbacks and independent roadmap continue; queue governance tests | 27da423 |
| MS-590 | VERIFIED_LOCAL | EXECUTION_STATE, PROJECT_STATUS, PROGRESS_HEARTBEAT and atomic Git checkpoints provide recoverable progress; state validation | 27da423 |
| MS-591 | VERIFIED_LOCAL | Apple/system/provider capability artifacts cite and enforce current official public mechanisms, with researched/unsupported states instead of stale assumptions; integration audit | 762c336 |
| MS-592 | VERIFIED_LOCAL | StartAssistantIntent/AppShortcuts expose public Siri/Shortcuts/Action Button entry while delegating execution to app coordinator; quick-launch tests | 58447af |
| MS-593 | VERIFIED_LOCAL | capability registry and deterministic coordinator reuse iOS/system entry points while UniversalAssistant owns cross-domain orchestration; coordination tests | 27ad853 |
| MS-594 | VERIFIED_LOCAL | LocalCommandEngine automatically selects capability from natural voice/text commands; Home has no required domain-menu path; parser/UI tests | fab773a |
| MS-595 | VERIFIED_LOCAL | AssistantHomeView always exposes editable typed command field and submit path independent of voice availability; accessibility/permission UI tests | c34533b |
| MS-596 | VERIFIED_LOCAL | VoiceInputController publishes live Speech-framework bestTranscription and Home reflects listening state without persisting a chat transcript; voice tests | c34533b |
| MS-597 | VERIFIED_LOCAL | stopping listening places the recognized transcript in the editable input so a user can minimally correct an entity/time/name without repeating the command; AssistantViewModel workflow tests | c34533b |
| MS-598 | VERIFIED_LOCAL | CurrentContext resolves yes/no, ordinal/open, cheaper, closer/navigation/call/reschedule/route-aware replies from bounded fresh preceding context; StrongCurrentContextTests | b289278 |
| MS-599 | VERIFIED_LOCAL | purchase handoff never claims purchase and direct financial/consequential action requires typed explicit confirmation/provider flow; commerce safety tests | 27ad853 |
| MS-600 | VERIFIED_LOCAL | booking/order/appointment engines validate consequential confirmation and authoritative provider response without redundant informational confirmation; appointment/food/commerce tests | 27ad853 |

| MS-601 | VERIFIED_LOCAL | UkraineEmergencyPlanner test mode returns typed dialer/location/route plans and UI evidence without executing a real call; emergency and canonical scenario tests | fab773a |
| MS-602 | VERIFIED_LOCAL | bounded AI receives only allowlisted structured unresolved context/verified facts; privacy filter and AI fallback tests reject broad personal datasets | ca92a6f |
| MS-603 | VERIFIED_LOCAL | capability/provider routing prefers specialized structured sources before generic discovery, which preserves explicit source kind/provenance; unknown-intent precedence/conflict tests | 2037125 |
| MS-604 | VERIFIED_LOCAL | retail extraction keeps branch/variant stock unknown unless structured source proves it and never treats page presence as inventory; generic retail tests | 9757b3a |
| MS-605 | VERIFIED_LOCAL | restaurant and appointment availability requires fresh authoritative provider slots; webpage/phone/handoff never becomes reservation proof; booking tests | 41bbacf |
| MS-606 | VERIFIED_LOCAL | official-source routers require exact non-homepage context, validated scheme/host/path and reject generic/unapproved destinations; deep-link/fashion tests | 6a2bac5 |
| MS-607 | VERIFIED_LOCAL | UniversalDeviceCommandRouter and IntegrationFallbackPolicy return exact official web/system/App Store alternative or truthful unavailable state when target app is absent; routing tests | eb698bd |
| MS-608 | VERIFIED_LOCAL | AppCapabilityRegistry models region/version/auth/mechanism constraints and unsupported execution falls back without assuming scheme availability; registry tests | 762c336 |
| MS-609 | VERIFIED_LOCAL | DeterministicExecutionPlanner creates typed dependency plans for common compound commands with zero AI; coordination acceptance tests | 27ad853 |
| MS-610 | VERIFIED_LOCAL | DeterministicPlanExecutor preserves completed safe steps, reports failed/unavailable steps and returns partial verified composition under bounded fanout; coordination tests | 27ad853 |
| MS-611 | VERIFIED_LOCAL | action ledger, execution step IDs and provider idempotency prevent retry duplication of calendar/reminder/booking/order work; coordination and lifecycle tests | 27ad853 |
| MS-612 | VERIFIED_LOCAL | booking/order/webhook/backend mutations use typed idempotency keys/event IDs where supported and reject duplicate consequential events; M9 and appointment tests | 27ad853 |
| MS-613 | VERIFIED_LOCAL | generic result composition caps the initial shortlist at three and emits typed “Показати ще” only when additional results exist; genericComparisonIsCappedAtThreeWithShowMore | ca50a5b |
| MS-614 | VERIFIED_LOCAL | bounded CurrentContext resolves other/cheaper/closer/ordinal-open refinements against fresh preceding results without restarting; context tests | b289278 |
| MS-615 | VERIFIED_LOCAL | grocery, ride, travel, place and product rankers enforce explicit cheapest/fastest/nearest/open/size/wait constraints before soft ranking; domain tests | fab773a |
| MS-616 | VERIFIED_LOCAL | native result/card models expose concise title/facts/source/action while technical provider IDs/API/confidence remain outside normal UI; presentation tests | 58447af |
| MS-617 | VERIFIED_LOCAL | AssistantResultState supports explicit expanded/details/action-required presentations while default success remains compact; result-state tests | 58447af |
| MS-618 | VERIFIED_LOCAL | SHOW/OPEN routing selects exact official visual/current source for fashion/product/place/travel domains and never reproduces unverified current content; official-source tests | 6a2bac5 |
| MS-619 | VERIFIED_LOCAL | retail freshness/provenance derives current/new collection facts from source timestamps/labels rather than popularity and rejects stale evidence; retail tests | 9757b3a |
| MS-620 | VERIFIED_LOCAL | GroceryBasketEngine treats explicit brand as a hard comparable-product constraint and does not silently substitute brands; grocery tests | 8b04a53 |
| MS-621 | VERIFIED_LOCAL | grocery normalization uses quantity/unit/category attributes for deterministic comparable generic products across stores; grocery comparison tests | 8b04a53 |
| MS-622 | VERIFIED_LOCAL | promotion/offer validity and observed timestamps are freshness-gated; expired grocery/commerce prices are excluded rather than treated current; commerce tests | 8b04a53 |
| MS-623 | VERIFIED_LOCAL | normalized loyalty core separates public and verified user-specific prices and preserves unknown discounts when no account/card evidence exists; loyalty tests | 00a3609 |
| MS-624 | VERIFIED_LOCAL | RideComparisonEngine compares normalized matching ride classes and preserves class labels instead of equating unlike offers; ride tests | 226be8c |
| MS-625 | VERIFIED_LOCAL | ride/user-specific promotions remain distinct verified account/provider adjustments and are not inferred as public quote value; ride truth tests | 226be8c |
| MS-626 | VERIFIED_LOCAL | ride optimal mode uses explicit configurable exact price/pickup-time weighting with reproducible ranking; RideComparisonEngineTests | 226be8c |
| MS-627 | VERIFIED_LOCAL | explicit maximum wait/budget constraints filter ride offers before default optimal ranking; RideComparisonEngineTests | 226be8c |
| MS-628 | VERIFIED_LOCAL | Transport/Travel engines enforce arrival deadline as a hard constraint before price/ranking and reject late cheaper options; transport tests | 48f8a09 |
| MS-629 | VERIFIED_LOCAL | SmartDepartureEngine recomputes material route/weather/transport changes and links updated recommendation to notification/reminder state; departure tests | 48f8a09 |
| MS-630 | VERIFIED_LOCAL | proactive categories/rules are explicit persisted user controls with deterministic disable/suppression behavior; proactive policy tests | d6c79b7 |
| MS-631 | VERIFIED_LOCAL | ProactiveWatchEngine parses natural stop/cancel phrases and removes the exact persisted rule/observation without settings navigation; naturalCancellationRemovesRuleAndObservation | d6c79b7 |
| MS-632 | VERIFIED_LOCAL | calendar/action ledger uses recent logical identity/idempotency to prevent duplicate assistant-created events on retry/repeated phrase; calendar tests | ddbccca |
| MS-633 | VERIFIED_LOCAL | linked plan mutation preserves event, reminder, route watch and shopping-stop identifiers so reschedule/cancel updates the coherent plan; linkage tests | ddbccca |
| MS-634 | VERIFIED_LOCAL | LocalContactResolver uses exact/alias resolution and returns ambiguity for multiple people rather than guessing; contact tests | 26e9264 |
| MS-635 | VERIFIED_LOCAL | phone actions use public tel handoff with required user/system control and never claim silent completed calling; system-router tests | 68be1a5 |
| MS-636 | VERIFIED_LOCAL | message actions use public composition/handoff and authoritative user completion, never silent unrestricted sending; messaging tests | 68be1a5 |
| MS-637 | VERIFIED_LOCAL | camera integration uses authorized in-app capture/public picker and explicitly rejects unsupported Camera-app automation; camera tests | 762c336 |
| MS-638 | VERIFIED_LOCAL | SystemQuickActionPlanner exposes only public Settings links/typed instructions and fails closed for arbitrary setting mutation; quick-action tests | 68be1a5 |
| MS-639 | VERIFIED_LOCAL | scene/background policy stops transient listening and uses legitimate background tasks/notifications/server scheduling, never continuous execution; lifecycle tests | d6c79b7 |
| MS-640 | VERIFIED_LOCAL | recurring external watches execute through backend durable jobs/ProactiveWatchEngine rather than continuous iPhone polling; backend proactive tests | d6c79b7 |
| MS-641 | VERIFIED_LOCAL | provider access validation and evidence governance reject prohibited scraping, CAPTCHA/login bypass and retain deepest legitimate fallback; integration tests | 2037125 |
| MS-642 | VERIFIED_LOCAL | typed fallback policy retains exact official web/phone/navigation/reduced automation when direct API is absent; fallback tests | eb698bd |
| MS-643 | VERIFIED_LOCAL | integration-depth audit checks API/SDK/OAuth/App Intent/deep link/feed/web/phone/navigation evidence before accepting a shallow path; governance tests | eb698bd |
| MS-644 | VERIFIED_LOCAL | Ukrainian retailer/provider matrices record checked official avenues, result, limitation, source URL and review date/status; artifact tests | eb698bd |
| MS-645 | VERIFIED_LOCAL | offline paths preserve local functions and label cached/static/live facts truthfully, with live traffic/stock/quotes/tickets/availability excluded; offline/failure tests | 94e56d9 |
| MS-646 | VERIFIED_LOCAL | consumer AssistantHomeView contains no partner administration; tenant-scoped business operations remain backend/dashboard contracts; isolation/UI tests | 81d4161 |
| MS-647 | VERIFIED_LOCAL | SponsoredOrganicSeparation keeps best organic result available independently of campaign/commission and renders sponsored separately; ranking tests | 168f2df |
| MS-648 | VERIFIED_LOCAL | sponsored retrieval is secondary/isolated and cannot delay or replace the deterministic organic result critical path; separation/performance tests | 168f2df |
| MS-649 | VERIFIED_LOCAL | CostQuotaManager checks are bounded/actor-local and simple local/system commands bypass remote cost quota dependency; runtime/performance tests | 069b18a |

| MS-650 | VERIFIED_LOCAL | ProviderHealthMonitor/observability records bounded latency, failure and availability signals used by routing/fanout to isolate unhealthy providers; health/fanout tests | 928f150 |
| MS-651 | VERIFIED_LOCAL | provider/job policies implement failure thresholds, bounded backoff and circuit-open degradation so repeated failures do not hammer dependencies; failure-policy tests | 928f150 |
| MS-652 | VERIFIED_LOCAL | provider and durable-job retries are bounded with capped backoff/jitter and timeout, while useful partial results return without a long stall; chaos/job tests | d6c79b7 |
| MS-653 | VERIFIED_LOCAL | consequential booking/order/purchase retries require idempotency/status evidence; unsafe unknown completion fails closed rather than blindly resubmitting; lifecycle tests | 27ad853 |
| MS-654 | VERIFIED_LOCAL | privacy-safe performance/provider/notification observability captures typed failure metadata and correlation IDs without requiring users to export technical logs; observability tests | 7a6cd05 |
| MS-655 | VERIFIED_LOCAL | telemetry/logging allowlists redact tokens, secrets, content and unnecessary precise location; repository and privacy tests | c38d23d |
| MS-656 | VERIFIED_LOCAL | DataRetentionPolicy and account lifecycle define bounded category retention, deletion and lawful residual handling with persistent audit evidence; retention tests | c38d23d |
| MS-657 | VERIFIED_LOCAL | local store remains primary and CloudKit sync is optional; unavailable cloud yields local operation plus queued reconciliation; sync tests | 242dfda |
| MS-658 | VERIFIED_LOCAL | CloudKit transport/reconciler execute asynchronously outside the main interaction path with bounded batches and failure isolation; sync tests | 242dfda |
| MS-659 | VERIFIED_LOCAL | SyncReconciler uses stable record IDs, versions and tombstones to merge conflicts without replaying actions or duplicating records; conflict tests | 242dfda |
| MS-660 | VERIFIED_LOCAL | Home/interaction policy preserves voice/text direct action, compact results and minimal confirmations; golden UX and friction tests | 58447af |
| MS-661 | VERIFIED_LOCAL | application, Share Extension and test targets compile/link successfully in Development simulator; 466-test full Xcode run | ca50a5b |
| MS-662 | VERIFIED_LOCAL | app lifecycle and chaos/result-state suites prove launch, cancellation, provider loss and replacement cannot leave a permanent spinner or known critical crash; full regression | 928f150 |
| MS-663 | VERIFIED_LOCAL | InteractionDecisionEngine implements DO, DON’T NARRATE and compact acknowledgement only after appropriate completed action; interaction tests | ffd98a9 |
| MS-664 | VERIFIED_LOCAL | Ukrainian, Russian, English, German and French command corpus/localized UI surfaces are complete and behavior-tested; localization/corpus tests | aabe915 |
| MS-665 | VERIFIED_LOCAL | cross-domain fact models require source timestamp/freshness and reject unverified live price, stock, availability, booking, ticket, quote/ETA and location claims; truth tests | 94e56d9 |
| MS-666 | VERIFIED_LOCAL | INTEGRATION_STATUS and capability matrix record implemented path, exact fallback or external dependency for every major integration; governance tests | 6ec7080 |
| MS-667 | VERIFIED_LOCAL | IntegrationDepthAuditor verifies the deepest locally legitimate fallback and records why higher paths are unavailable; fallback/audit tests | 6ec7080 |
| MS-668 | VERIFIED_LOCAL | explicit suites cover slow/failing provider, cancellation, network/backend loss, poor GPS, missing app, denied permission and AI failure with graceful outcomes; full regression | 928f150 |
| MS-669 | VERIFIED_LOCAL | REAL_DEVICE_TEST_MATRIX lists physical-only behaviors with exact setup/action/expected result and prevents simulator evidence from becoming VERIFIED_LIVE; matrix tests | 6ec7080 |
| MS-670 | VERIFIED_LOCAL | privacy manifest, contextual permission policy, Keychain/runtime secrets, redacted logging, data map and deletion/auth boundaries satisfy local security evidence gates; security/privacy tests | c38d23d |
| MS-671 | VERIFIED_LOCAL | tenant-isolated business backend, verified onboarding, organic/sponsored separation, remote config and exact cost/quota policy are implemented without consumer fast-path dependency; M9 tests | 069b18a |
| MS-672 | VERIFIED_LOCAL | release configurations, metadata/privacy/permission/screenshot/review/TestFlight readiness artifacts and release checklist are locally prepared and audited | 401ee00 |
| MS-673 | VERIFIED_LOCAL | release state and live queue explicitly keep signing, TestFlight and App Store submission/review incomplete until owner/Apple execution; release audit | 401ee00 |
| MS-674 | VERIFIED_LOCAL | Xcode project contains no watchOS target/product and canonical project scope keeps Apple Watch excluded from V1; project build audit | 5898cd5 |

| MS-676 | VERIFIED_LOCAL | canonical inventory preserves every numbered requirement with explicit allowed status/evidence fields; strict importer rejects missing IDs/evidence | 27da423 |
| MS-677 | VERIFIED_LOCAL | golden-journey friction metrics and interaction policy remove narration, redundant confirmation and unnecessary taps while preserving safety; UX tests | aabe915 |
| MS-678 | VERIFIED_LOCAL | provider fanout/chaos tests cover timeout, cancellation, network/backend loss and prove external failure cannot permanently block UI/local work | 928f150 |
| MS-679 | VERIFIED_LOCAL | IntegrationDepthAuditor and provider matrices verify higher-priority avenues before accepting each fallback-active provider; audit tests | 6ec7080 |
| MS-680 | VERIFIED_LOCAL | ARCHITECTURE documents API ingress, adapters, auth, database/cache, durable jobs, notifications, config, partner portal, observability and operations topology | 8e9f92c |
| MS-681 | VERIFIED_LOCAL | backend responsibilities are separated into scoped actors/services/files for auth, partners, ledger, jobs, APNs, config and observability; architecture tests | 8e9f92c |
| MS-682 | VERIFIED_LOCAL | request processing remains stateless while durable account/job/ledger/partner state uses designated stores/queues with restart tests | 8e9f92c |
| MS-683 | VERIFIED_LOCAL | ServerMain exposes stable health/readiness contract and backend tests verify healthy response/schema | 8e9f92c |
| MS-684 | VERIFIED_LOCAL | operational/provider health models distinguish database/cache/queue/provider degradation for selective failure isolation; health tests | 069b18a |
| MS-685 | VERIFIED_LOCAL | ProactiveWatchEngine schedules recurring product/price/ticket/travel checks through durable server jobs | d6c79b7 |
| MS-686 | VERIFIED_LOCAL | DurableJobQueue persists queued work across actor/process reconstruction and has restart behavioral tests | d6c79b7 |
| MS-687 | VERIFIED_LOCAL | durable jobs carry logical idempotency keys and completed-state deduplication so retries do not duplicate actions/notifications | d6c79b7 |
| MS-688 | VERIFIED_LOCAL | DurableJobQueue applies capped attempts and deterministic bounded backoff/jitter policy; retry tests | d6c79b7 |
| MS-689 | VERIFIED_LOCAL | repeatedly failing durable work transitions to persisted dead-letter state and stops retrying forever; job tests | d6c79b7 |
| MS-690 | VERIFIED_LOCAL | logically identical queued/completed jobs and notifications deduplicate by stable identity/collapse key; queue/notification tests | d6c79b7 |
| MS-691 | VERIFIED_LOCAL | proactive rules/jobs carry expiry and obsolete work is cancelled rather than executed after validity; expiration tests | d6c79b7 |
| MS-692 | VERIFIED_LOCAL | proactive jobs persist source rule/event/product/ticket linkage supporting exact cancellation/reschedule updates; linkage tests | d6c79b7 |
| MS-693 | VERIFIED_LOCAL | APNSDelivery implements explicit server-originated APNs payload/request architecture with secure credential boundary and truthful response mapping; APNs tests | f3553f6 |
| MS-694 | VERIFIED_LOCAL | APNSDeviceTokenRegistry handles register/refresh/invalidate/logout/removal and multiple devices durably and idempotently; token tests | 02866ec |
| MS-695 | VERIFIED_LOCAL | NotificationPolicy checks global and category preferences before enqueue/delivery; preference tests | f3553f6 |
| MS-696 | VERIFIED_LOCAL | notification event/collapse identity suppresses duplicate meaningful-change alerts; notification tests | f3553f6 |
| MS-697 | VERIFIED_LOCAL | APNs/local notification payloads enforce expiration TTL and reject stale delivery; expiration tests | f3553f6 |
| MS-698 | VERIFIED_LOCAL | APNs payload carries collapse/thread identifiers so newer state replaces obsolete alerts; payload tests | f3553f6 |
| MS-699 | VERIFIED_LOCAL | NotificationObservability persists bounded redacted enqueue/send/provider-response metadata without message content/secrets; observability tests | f3553f6 |
| MS-700 | VERIFIED_LOCAL | notification payload/action routing preserves exact source/action context identifier instead of generic-home-only launch; APNs routing tests | f3553f6 |
| MS-701 | VERIFIED_LOCAL | local Calendar/Reminder scheduling uses EventKit/local notification mechanisms without unnecessary server dependency; reminder tests | ddbccca |
| MS-702 | VERIFIED_LOCAL | AccountPolicy explicitly selects optional local-first V1 account with account required only for sync/server/entitlement capabilities | 6a8e0e4 |
| MS-703 | VERIFIED_LOCAL | app launches and executes local device capabilities before/without account creation; account policy and local-domain tests | 6a8e0e4 |
| MS-704 | READY_FOR_LIVE_VERIFICATION | AppleAccountSession implements nonce-bound authorization, persistence, credential-state/revocation handling and local tests; production Apple capability/device/server verification is queued | 6c1c9a1 |
| MS-705 | VERIFIED_LOCAL | AccountDataLifecycle deterministically merges local anonymous data into signed-in ownership using stable IDs/tombstones without duplication/loss; merge tests | 242dfda |
| MS-706 | VERIFIED_LOCAL | logout removes server jobs/tokens/provider sessions according to policy while preserving or deleting local/cloud data predictably; lifecycle tests | 242dfda |

| MS-707 | VERIFIED_LOCAL | Sign in with Apple delegates recovery/account ownership to Apple credential state and contains no invented password/reset flow; session tests | 6c1c9a1 |
| MS-708 | VERIFIED_LOCAL | account/device token and CloudKit models support multiple iPhones with shared preferences plus device-specific tokens/capabilities; multi-device tests | 242dfda |
| MS-709 | VERIFIED_LOCAL | LocalStore documents and implements actor-isolated versioned JSON persistence appropriate to current local typed state | f866914 |
| MS-710 | VERIFIED_LOCAL | preferences, aliases, context and pending local state read/write through LocalStore without mandatory network round trips; persistence tests | f866914 |
| MS-711 | VERIFIED_LOCAL | LocalStore runs versioned transactional migrations and representative legacy fixtures verify upgrade/rollback safety | f866914 |
| MS-712 | VERIFIED_LOCAL | corrupt/read-failed local records are quarantined/recovered with typed error and safe defaults without silent broad data loss; corruption tests | f866914 |
| MS-713 | VERIFIED_LOCAL | safe pending offline operations persist durable identity/state and reconcile idempotently when connectivity returns; persistence/sync tests | f866914 |
| MS-714 | VERIFIED_LOCAL | consequential purchase/booking/order operations are never blindly queued offline and require current provider validation/confirmation; safety tests | 27ad853 |
| MS-715 | VERIFIED_LOCAL | OFFLINE_CAPABILITY_MATRIX classifies each major capability FULL_OFFLINE/PARTIAL_OFFLINE/ONLINE_REQUIRED with exact degraded behavior; artifact tests | 6ec7080 |
| MS-716 | VERIFIED_LOCAL | typed result states distinguish unavailable live facts from functioning local capabilities instead of global broken state; offline/UI tests | 94e56d9 |
| MS-717 | VERIFIED_LOCAL | PROVIDER_CAPABILITY_MATRIX records search/details/price/stock/ETA/availability/auth/book/purchase/deep-link/App Intent/region/source capabilities | 6ec7080 |
| MS-718 | VERIFIED_LOCAL | provider matrix and IntegrationDepthAuditor prohibit generic “integrated” status and require exact implemented capability depth | 6ec7080 |
| MS-719 | VERIFIED_LOCAL | capability registry resolves provider mechanism by explicit capability, region, version and auth state rather than global provider label; registry tests | 762c336 |
| MS-720 | VERIFIED_LOCAL | API_CONTRACT defines versioned typed iPhone/backend and internal service request/response/error/idempotency contracts; contract tests | 8e9f92c |
| MS-721 | VERIFIED_LOCAL | concrete adapters/webhooks validate Codable/schema/version/status fields and reject malformed payloads without crashes/fake success; adapter tests | 928f150 |
| MS-722 | VERIFIED_LOCAL | API versioning preserves compatible optional evolution and isolates explicit breaking versions; compatibility tests | 8e9f92c |
| MS-723 | VERIFIED_LOCAL | API compatibility matrix maps supported iOS configurations to backend API/features and release gates | 7917983 |
| MS-724 | VERIFIED_LOCAL | AppVersionSupportPolicy provides configurable supported/degraded/update-required states with rollback-safe remote policy; policy tests | 7917983 |
| MS-725 | VERIFIED_LOCAL | Xcode configuration and architecture explicitly select iOS 18 minimum from required APIs/maintenance scope | 5898cd5 |
| MS-726 | VERIFIED_LOCAL | device/real-test matrices record framework and hardware limitations without claiming unavailable Action Button/device coverage | 6ec7080 |
| MS-727 | VERIFIED_LOCAL | SubscriptionEntitlement uses StoreKit 2 product/transaction architecture and never trusts hardcoded local purchase success | 1045668 |
| MS-728 | VERIFIED_LOCAL | typed entitlement policy separates Free/Premium/business capabilities from UI visibility; Family remains NOT_APPLICABLE until owner enables it | 1045668 |
| MS-729 | READY_FOR_LIVE_VERIFICATION | legitimate StoreKit purchase path uses verified Product display price/period/terms and transaction verification; App Store product/sandbox execution queued | 1045668 |
| MS-730 | READY_FOR_LIVE_VERIFICATION | StoreKit sync/restore production path and local tests are complete; real sandbox purchase restoration is queued | 1045668 |
| MS-731 | READY_FOR_LIVE_VERIFICATION | subscription state model handles renewal/expiration/grace/billing-retry/revocation/refund/product changes; real App Store lifecycle execution queued | 1045668 |
| MS-732 | READY_FOR_LIVE_VERIFICATION | server entitlement contract requires verified signed App Store transaction/notification rather than client boolean; deployed Apple server verification queued | 1045668 |
| MS-733 | VERIFIED_LOCAL | downgrade policy preserves user-owned notes/lists/aliases/data and changes capability access without destructive deletion; entitlement tests | 1045668 |
| MS-734 | VERIFIED_LOCAL | expiration disables only gated capabilities while core launch/local state remain valid and uncorrupted; entitlement tests | 1045668 |
| MS-735 | VERIFIED_LOCAL | paywall presentation is invoked only for a genuinely gated requested capability and never interrupts unrelated local/system commands; entitlement/UI tests | 1045668 |
| MS-736 | VERIFIED_LOCAL | subscription UI uses factual StoreKit metadata, transparent management/restore and no urgency/dark-pattern state; presentation tests | 1045668 |

| MS-851 | VERIFIED_LOCAL | LocaliPhoneSearchEngine provides the dedicated typed iPhone command/local-search layer over permitted repositories; engine tests | 5898cd5 |
| MS-852 | VERIFIED_LOCAL | LocalCommandEngine/UniversalDeviceCommandRouter use the same voice/text entry for device and external capability routing; router tests | 762c336 |
| MS-853 | VERIFIED_LOCAL | quick launch enters listening directly and interaction policy executes unambiguous device commands without narration; quick-launch/UI tests | 58447af |
| MS-854 | VERIFIED_LOCAL | AppCapabilityRegistry and IntegrationDepthAuditor require deepest public Apple/App Intent/link/SDK/provider mechanism per system action; audit tests | 762c336 |
| MS-855 | VERIFIED_LOCAL | capability evidence governance rejects placeholder/shallow completion when a locally feasible production path lacks E3 behavior evidence | 27da423 |
| MS-856 | VERIFIED_LOCAL | device router selects exact supported context/action before generic launch and only then falls back truthfully; routing tests | 762c336 |
| MS-857 | VERIFIED_LOCAL | unsupported capability state requires documented checked mechanisms and exact limitation/fallback evidence; governance tests | 6ec7080 |
| MS-858 | VERIFIED_LOCAL | PROVIDER_CAPABILITY_MATRIX/INTEGRATION_STATUS record mechanism, support, limitation and deepest implemented behavior per device/app capability | 6ec7080 |
| MS-859 | READY_FOR_LIVE_VERIFICATION | public system-app launch routes are locally implemented/tested; representative signed-device execution remains in MS-859-869 live queue | 762c336 |
| MS-860 | READY_FOR_LIVE_VERIFICATION | third-party official scheme/link launch routing is locally complete; installed-app signed-device execution remains queued | 762c336 |
| MS-861 | VERIFIED_LOCAL | AppCapabilityRegistry normalizes localized names, aliases and pronunciation variants to deterministic exact candidates; registry tests | 762c336 |
| MS-862 | VERIFIED_LOCAL | ambiguous equal app-name candidates produce one typed clarification while a unique candidate opens directly; router tests | 762c336 |
| MS-863 | VERIFIED_LOCAL | InteractionDecisionEngine returns silent execution for unambiguous open-app command and no “found/opening” narration; interaction tests | ffd98a9 |
| MS-864 | READY_FOR_LIVE_VERIFICATION | device router prefers typed exact chat/route/product/search/media context over launch; installed-app deep-action execution remains queued | 762c336 |
| MS-865 | READY_FOR_LIVE_VERIFICATION | App Intent capability discovery/registry contract is implemented; actual representative third-party exposed intents remain queued by app/device/version | 762c336 |
| MS-866 | READY_FOR_LIVE_VERIFICATION | App Shortcut capability routing/fallback is implemented; actual installed-app shortcut discovery/execution remains queued | 762c336 |
| MS-867 | READY_FOR_LIVE_VERIFICATION | documented URL-scheme registry and validation are implemented; physical installed-app resolution remains queued | 762c336 |
| MS-868 | READY_FOR_LIVE_VERIFICATION | exact Universal Link validation/routing is implemented before generic launch; physical app/browser resolution remains queued | 762c336 |
| MS-869 | READY_FOR_LIVE_VERIFICATION | official SDK/API/OAuth capability records select deeper device-service actions where supported; account/app live execution remains queued | 762c336 |
| MS-870 | VERIFIED_LOCAL | Apple system-domain audit and routers prohibit private APIs, accessibility abuse, screen automation and jailbreak-style control | 762c336 |
| MS-871 | VERIFIED_LOCAL | LocaliPhoneSearchEngine routes natural requests concurrently to deepest permitted local sources and exposes exact object actions | 5898cd5 |
| MS-872 | VERIFIED_LOCAL | authorized Contacts/EventKit/Photos/app-owned store/Spotlight/files repositories are typed local source adapters with explicit permissions | 5898cd5 |
| MS-873 | VERIFIED_LOCAL | LocalContactResolver performs natural exact/alias contact search and returns permitted contact action target; contact tests | 26e9264 |
| MS-874 | VERIFIED_LOCAL | EventKit calendar repository supports title/person/date/time constrained local event search; calendar tests | ddbccca |
| MS-875 | VERIFIED_LOCAL | ReminderService searches permitted reminders/lists and exposes exact typed reminder records; reminder tests | ddbccca |
| MS-876 | VERIFIED_LOCAL | assistant-owned notes repository participates in fast local search without backend/AI; local-search tests | 5898cd5 |
| MS-877 | VERIFIED_LOCAL | permitted reminders/shopping lists and assistant-owned lists are searchable/openable through local repositories; local-search tests | 5898cd5 |
| MS-878 | VERIFIED_LOCAL | structured bounded action history supports yesterday/last/open-last retrieval without retaining raw sensitive transcript; history/context tests | b289278 |


| MS-879 | VERIFIED_LOCAL | PhotoKitLibrarySearch uses the public Photos authorization API and queries only real accessible PHAsset images; authorization/search tests | d814576 |
| MS-880 | VERIFIED_LOCAL | PhotoSearchCriteria and PhotoKit fetch predicate enforce real half-open creation-date ranges; metadata criteria tests | d814576 |
| MS-881 | VERIFIED_LOCAL | PhotoKit search applies CLLocation coordinate/radius filtering against real asset location metadata; criteria and source tests | d814576 |
| MS-882 | VERIFIED_LOCAL | exact album title resolves permitted collection membership and filters assets by real identifiers; PhotoKit source tests | d814576 |
| MS-883 | VERIFIED_LOCAL | results preserve only legitimately exposed creation date, coordinate, album and local identifier metadata; source tests | d814576 |
| MS-884 | VERIFIED_LOCAL | bounded on-device Vision classification searches only currently permitted PhotoKit assets and fails closed for denied/unreadable inputs; semantic behavior tests | 8557f2d |
| MS-885 | VERIFIED_LOCAL | authorization maps full and limited distinctly and both gate only the assets PhotoKit exposes; authorization/semantic tests | 8557f2d |
| MS-886 | VERIFIED_LOCAL | missing, unreadable, unclassified or nonmatching assets return no result rather than inferred/fabricated success; semantic denial/failure tests | 8557f2d |
| MS-887 | VERIFIED_LOCAL | photo results retain exact PhotoKit local identifiers for the legitimate system open/detail path; source identity tests | d814576 |
| MS-888 | VERIFIED_LOCAL | AuthorizedDocumentPicker is the public Files/provider entry and returns only user-selected URLs; file-source tests | d814576 |
| MS-889 | VERIFIED_LOCAL | file source has no global filesystem traversal and searches only explicit authorized references; isolation test | d814576 |
| MS-890 | VERIFIED_LOCAL | AuthorizedFileSearchSource balances security-scoped access, verifies existence and performs bounded filename search; behavioral tests | d814576 |
| MS-891 | VERIFIED_LOCAL | a permitted file result carries the exact selected URL as its open reference; exact-open test | d814576 |
| MS-892 | VERIFIED_LOCAL | CoreSpotlightAssistantIndexer indexes/removes only assistant-owned typed local results under scoped domain identifiers | d814576 |
| MS-893 | VERIFIED_LOCAL | Spotlight adapter never queries or claims access to other apps private indexes; architecture and source audit | d814576 |
| MS-894 | VERIFIED_LOCAL | settings/system actions route only through documented public capability records and truthful unsupported fallback; router tests | 762c336 |
| MS-895 | VERIFIED_LOCAL | device search commands resolve through the typed LocaliPhoneSearchEngine/device routing layer; router/search tests | 68862b5 |
| MS-896 | VERIFIED_LOCAL | independent permitted local sources execute concurrently and merge into one report; concurrency test | 68862b5 |
| MS-897 | VERIFIED_LOCAL | deterministic ranking uses relevance, exact match, source preference, recency and stable tie breaks; ranking test | 68862b5 |
| MS-898 | VERIFIED_LOCAL | result list is bounded and clearResult opens only a sole or sufficiently separated match; shortlist tests | 68862b5 |
| MS-899 | VERIFIED_LOCAL | structured recent-result context supports typed second/this/open/show followups without raw transcript storage; context tests | b289278 |
| MS-900 | VERIFIED_LOCAL | personal search is on-device over authorized repositories and privacy-safe local references; privacy/search tests | 68862b5 |
| MS-901 | VERIFIED_LOCAL | local device search coordinator has no AI dependency and operates with permitted local sources alone; no-AI tests | 68862b5 |
| MS-902 | VERIFIED_LOCAL | source fanout is concurrent, index/search output bounded and no network wait is introduced on local path; concurrency/performance tests | 68862b5 |
| MS-903 | VERIFIED_LOCAL | PrivacySafeLocalSearchIndex stores typed local references for permitted assistant sources only; index tests | 68862b5 |
| MS-904 | VERIFIED_LOCAL | local index supports incremental upsert and scoped source removal rather than mandatory full rebuild; incremental tests | 68862b5 |
| MS-905 | VERIFIED_LOCAL | permission loss removes the affected source references and prevents stale indexed results; permission-change test | 68862b5 |
| MS-906 | VERIFIED_LOCAL | local source/index execution contains no network dependency and remains available offline; engine tests | 68862b5 |
| MS-907 | VERIFIED_LOCAL | installed-app launch uses public local URL/App Intent/shortcut routing without backend dependency; router tests | 762c336 |
| MS-908 | VERIFIED_LOCAL | unsupported device actions produce exact capability limitation/fallback rather than technical dumps or fake success; router tests | 762c336 |
| MS-909 | VERIFIED_LOCAL | Apple domain audit explicitly records public-API boundaries and prohibits private Siri/system-control claims; governance tests | 762c336 |
| MS-910 | VERIFIED_LOCAL | universal voice/text device routing maximizes public iOS capabilities while preserving explicit platform limits; routing tests | 762c336 |
| MS-911 | VERIFIED_LOCAL | REAL_DEVICE_TEST_MATRIX contains Photos, Files, Spotlight, local latency and representative app-action scenarios with exact identifiers | 6ec7080 |
| MS-912 | VERIFIED_LOCAL | automated suites cover local concurrency/ranking/permissions/indexing plus Photos/files production boundaries and failure behavior | 8557f2d |
| MS-913 | READY_FOR_LIVE_VERIFICATION | local PhotoKit/Vision implementation and tests are complete; exact full/limited/denied physical Photos execution is queued as MS-913-LIVE-PHOTOS | 8557f2d |
| MS-914 | READY_FOR_LIVE_VERIFICATION | local system picker/security-scoped implementation and tests are complete; physical provider execution is queued as MS-914-LIVE-FILES | d814576 |
| MS-915 | READY_FOR_LIVE_VERIFICATION | public app-action routing and automated tests are complete; representative installed-app execution is queued as MS-915-LIVE-APP-ACTIONS | 762c336 |
| MS-916 | READY_FOR_LIVE_VERIFICATION | bounded concurrent local search is locally tested; physical release-like latency measurement is queued as MS-916-LIVE-LOCAL-SEARCH-LATENCY | 68862b5 |
| MS-917 | READY_FOR_LIVE_VERIFICATION | typed region/version capability routing and matrices are local; physical combinations are queued as MS-917-LIVE-REGION-VERSION-CAPABILITY | 6ec7080 |
| MS-918 | VERIFIED_LOCAL | iPhone universal command/search scope is integrated into the production device router, capability registry and M12 evidence | 68862b5 |


| MS-921 | VERIFIED_LOCAL | ConnectedAccountsHub provides one typed provider-neutral account surface over the existing authentication/Keychain boundary; hub tests | e015ba8 |
| MS-922 | VERIFIED_LOCAL | provider descriptors expose discoverable service category, capabilities, connection requirements and non-secret status; hub tests | e015ba8 |
| MS-923 | VERIFIED_LOCAL | connection records and provider contracts retain exact capability depth instead of reducing all accounts to a generic connected flag; depth tests | e015ba8 |
| MS-924 | VERIFIED_LOCAL | requested scopes must equal the provider minimum and credentials containing unrequested scopes are rejected; scope test | e015ba8 |
| MS-925 | VERIFIED_LOCAL | disconnect invokes supported provider revocation before isolated Keychain/local metadata deletion; disconnect test | e015ba8 |
| MS-926 | VERIFIED_LOCAL | health distinguishes connected, expiring/reauthorization, signed-out, unavailable and isolated provider errors across restart; health tests | e015ba8 |
| MS-927 | READY_FOR_LIVE_VERIFICATION | official Gmail REST production client, OAuth boundary and tests are complete; authorized provider execution remains in MS-927-934-LIVE-GMAIL | e7ac66d |
| MS-928 | READY_FOR_LIVE_VERIFICATION | bounded Gmail query search with exact provider IDs and schema validation is local; real controlled-account search is queued | e7ac66d |
| MS-929 | READY_FOR_LIVE_VERIFICATION | raw RFC 2822 retrieval and parsing path is local; actual controlled-message retrieval/read-back is queued | e7ac66d |
| MS-930 | READY_FOR_LIVE_VERIFICATION | attachment ID retrieval and base64url decoding are local; actual controlled attachment execution is queued | e7ac66d |
| MS-931 | READY_FOR_LIVE_VERIFICATION | official Gmail draft creation contract and response validation are local; real draft create/read-back is queued | e7ac66d |
| MS-932 | READY_FOR_LIVE_VERIFICATION | confirmed Gmail reply path makes no request before safety approval; actual send/read-back is queued | e7ac66d |
| MS-933 | READY_FOR_LIVE_VERIFICATION | confirmed typed label/archive/trash mutations and failure mapping are local; actual provider state mutation is queued | e7ac66d |
| MS-934 | READY_FOR_LIVE_VERIFICATION | all locally possible Gmail implementation/tests are complete; the explicitly required authorized real-execution matrix is queued | e7ac66d |
| MS-935 | VERIFIED_LOCAL | EmailProvider is provider-neutral and Connected Accounts can add other official providers without duplicating email logic; abstraction tests | e7ac66d |
| MS-936 | VERIFIED_LOCAL | Apple Mail capability audit truthfully limits third-party access to compose/handoff and never claims general inbox/history API access | e7ac66d |
| MS-937 | READY_FOR_LIVE_VERIFICATION | universal email query/result routing is locally implemented with provenance; controlled connected-account end-to-end search is queued | e7ac66d |
| MS-938 | READY_FOR_LIVE_VERIFICATION | exact Gmail message/thread/attachment identifiers feed typed follow-up actions locally; real email-to-action journey is queued | e7ac66d |
| MS-939 | READY_FOR_LIVE_VERIFICATION | ticket-email query and attachment path is locally behavior-tested; controlled real ticket retrieval remains queued | e7ac66d |
| MS-940 | READY_FOR_LIVE_VERIFICATION | invoice-email date/query/attachment path is locally behavior-tested; controlled real invoice retrieval remains queued | e7ac66d |
| MS-941 | VERIFIED_LOCAL | public Messages/iMessage and major messenger capability investigation is recorded in typed production evidence and provider matrix | 19248bb |
| MS-942 | VERIFIED_LOCAL | messaging architecture explicitly exposes no SMS/iMessage inbox/history access and never fabricates received messages; tests | 19248bb |
| MS-943 | READY_FOR_LIVE_VERIFICATION | MessageUI compose is the deepest public system action with user-controlled send; physical composer observation is queued | 19248bb |
| MS-944 | READY_FOR_LIVE_VERIFICATION | validated encoded WhatsApp click-to-chat handoff is locally tested; installed-app physical resolution is queued | 19248bb |
| MS-945 | READY_FOR_LIVE_VERIFICATION | validated exact Telegram username-context handoff is locally tested; installed-app physical resolution is queued | 19248bb |
| MS-946 | READY_FOR_LIVE_VERIFICATION | validated Viber public share handoff is locally tested; installed-app physical resolution is queued | 19248bb |
| MS-947 | READY_FOR_LIVE_VERIFICATION | Signal correctly falls back to system share without history/send claim; physical installed/absent behavior is queued | 19248bb |
| MS-948 | VERIFIED_LOCAL | provider capability matrix distinguishes find/open/compose/send/call/history/App Intent/deep-link/API per messenger and marks no fake send | 19248bb |


| MS-949 | VERIFIED_LOCAL | AppleSystemDomainAudit enumerates every canonical Apple domain with deepest public behavior and explicit limitation; coverage tests | 762c336 |
| MS-950 | VERIFIED_LOCAL | all locally legitimate EventKit, Contacts, MapKit, PhotoKit, Files, Spotlight, camera, messaging and media paths are implemented/reused; audit tests | 762c336 |
| MS-951 | VERIFIED_LOCAL | Clock capability investigation records no general public timer/alarm creation API for this target and checks exposed mechanisms | 762c336 |
| MS-952 | VERIFIED_LOCAL | clock requests return truthful unavailable state and never fabricate timer/alarm completion; system-domain tests | 762c336 |
| MS-953 | READY_FOR_LIVE_VERIFICATION | MusicKit catalog/playback production adapter and local tests are complete; account/entitlement/device execution is queued under MS-953-955 | 762c336 |
| MS-954 | READY_FOR_LIVE_VERIFICATION | bounded regional Apple podcast API adapter and exact HTTPS episode handoff are local; live catalog response is queued under MS-953-955 | 762c336 |
| MS-955 | READY_FOR_LIVE_VERIFICATION | public system camera capture and fail-closed unavailable behavior are local; physical capture/cancel is queued under MS-953-955 | 762c336 |
| MS-956 | VERIFIED_LOCAL | authorized Files source participates in universal personal search with exact URL/provenance; personal-search behavioral tests | 59e1cee |
| MS-957 | VERIFIED_LOCAL | authorized Photos source participates with real asset identity and permission boundaries; personal-search behavioral tests | 59e1cee |
| MS-958 | VERIFIED_LOCAL | Contacts source is selected for plausible person/contact queries and retains exact source ID; personal-search behavioral tests | 59e1cee |
| MS-959 | VERIFIED_LOCAL | Calendar source is selected for event/record queries and retains exact event provenance; personal-search behavioral tests | 59e1cee |
| MS-960 | VERIFIED_LOCAL | Reminders source is selected for reminder/list queries and retains exact object identity; personal-search behavioral tests | 59e1cee |
| MS-961 | VERIFIED_LOCAL | assistant-owned notes source participates locally without AI/backend dependency; personal-search behavioral tests | 59e1cee |
| MS-962 | VERIFIED_LOCAL | permitted shopping/system list sources participate without claiming private stores; personal-search behavioral tests | 59e1cee |
| MS-963 | VERIFIED_LOCAL | authorized connected email source is normalized into personal-search results with provider provenance; personal-search behavioral tests | 59e1cee |
| MS-964 | VERIFIED_LOCAL | provider-neutral connected-service source contract admits only supplied authorized services; personal-search behavioral tests | 59e1cee |
| MS-965 | VERIFIED_LOCAL | UniversalPersonalSearchEngine coordinates typed local and remote personal sources; personal-search behavioral tests | 59e1cee |
| MS-966 | VERIFIED_LOCAL | PersonalSearchSourceRouter infers only plausible sources and avoids unnecessary sensitive fanout; personal-search behavioral tests | 59e1cee |
| MS-967 | VERIFIED_LOCAL | dentist-record journey routes plausible repositories concurrently and excludes irrelevant sources; personal-search behavioral tests | 59e1cee |
| MS-968 | VERIFIED_LOCAL | document journey searches Files plus connected email and preserves per-result provenance; personal-search behavioral tests | 59e1cee |
| MS-969 | VERIFIED_LOCAL | photo journey preserves date/location constraints through the authorized Photos path; personal-search behavioral tests | 59e1cee |
| MS-970 | VERIFIED_LOCAL | one sufficiently clear result yields its exact typed open action/reference; personal-search behavioral tests | 59e1cee |
| MS-971 | VERIFIED_LOCAL | ambiguous results are deterministically ranked and capped at three without auto-open; personal-search behavioral tests | 59e1cee |
| MS-972 | VERIFIED_LOCAL | local sources execute on-device first and no external AI is required; personal-search behavioral tests | 59e1cee |
| MS-973 | VERIFIED_LOCAL | remote sources receive only the minimal query and bounded limit for a plausible category; personal-search behavioral tests | 59e1cee |
| MS-974 | VERIFIED_LOCAL | each result retains source kind, real source-object ID, open reference and freshness; personal-search behavioral tests | 59e1cee |
| MS-975 | VERIFIED_LOCAL | remote freshness is typed live/cached/unknown and never silently promoted; personal-search behavioral tests | 59e1cee |
| MS-976 | VERIFIED_LOCAL | one source failure returns truthful partial coverage plus verified results from other sources; personal-search behavioral tests | 59e1cee |
| MS-977 | VERIFIED_LOCAL | official CarPlay eligibility/category/managed-entitlement audit is persisted with authoritative source and fail-closed policy tests | cafba35 |
| MS-978 | READY_FOR_LIVE_VERIFICATION | all pre-entitlement policy gates are local; category-specific scene cannot legitimately be selected until owner category and Apple entitlement in MS-978-979 queue | cafba35 |
| MS-979 | READY_FOR_LIVE_VERIFICATION | driver-safe exact-category template policy is local; physical approved CarPlay UX execution remains in MS-978-979 queue | cafba35 |
| MS-980 | NOT_APPLICABLE_VERIFIED | HealthKit is explicitly excluded by default and no entitlement/data path exists absent a concrete owner-approved requirement; policy tests | cafba35 |
| MS-981 | VERIFIED_LOCAL | PlatformEligibilityPolicy independently fails closed for unapproved health, finance, identity and CarPlay sensitive domains; tests | cafba35 |
| MS-982 | VERIFIED_LOCAL | IntegrationVerificationPolicy requires the canonical real-execution evidence level for each external adapter/provider/device capability; executable governance tests/artifact audit | 6ec7080 |
| MS-983 | VERIFIED_LOCAL | E3 mock/internal evidence cannot promote an external capability to live verified; executable governance tests/artifact audit | 6ec7080 |
| MS-984 | VERIFIED_LOCAL | an adapter/type alone is rejected without production behavior plus required evidence; executable governance tests/artifact audit | 6ec7080 |
| MS-985 | VERIFIED_LOCAL | maximum-depth audit rejects a deep-link-only claim when a deeper official mechanism is applicable and feasible; executable governance tests/artifact audit | 6ec7080 |
| MS-986 | VERIFIED_LOCAL | provider capabilities requiring authorization remain live-unverified until actual authorized execution evidence exists; executable governance tests/artifact audit | 6ec7080 |
| MS-987 | VERIFIED_LOCAL | read/search live status requires actual controlled provider/account result evidence, while local readiness remains separate; executable governance tests/artifact audit | 6ec7080 |
| MS-988 | VERIFIED_LOCAL | write live status requires actual confirmed external mutation evidence and never fake success; executable governance tests/artifact audit | 6ec7080 |
| MS-989 | VERIFIED_LOCAL | delete/cancel live status requires actual supported mutation/read-back evidence where canonical; executable governance tests/artifact audit | 6ec7080 |
| MS-990 | VERIFIED_LOCAL | round-trip live status requires real create/write then retrieval/state verification where appropriate; executable governance tests/artifact audit | 6ec7080 |
| MS-991 | VERIFIED_LOCAL | physical Apple behavior requires E5 signed-device evidence rather than simulator inference; executable governance tests/artifact audit | 6ec7080 |
| MS-992 | VERIFIED_LOCAL | device-only capabilities cannot be marked live verified before the required device test; executable governance tests/artifact audit | 6ec7080 |
| MS-993 | VERIFIED_LOCAL | queued external blockers require exact dependency, owner, local evidence, action and expected result; executable governance tests/artifact audit | 6ec7080 |
| MS-994 | VERIFIED_LOCAL | external dependency never lowers local implementation/test/security/error-handling duty; executable governance tests/artifact audit | 6ec7080 |
| MS-995 | VERIFIED_LOCAL | persistent live queue preserves the exact resume action after a dependency becomes available; executable governance tests/artifact audit | 6ec7080 |
| MS-996 | VERIFIED_LOCAL | live verification records require provider/device/account execution evidence tied to the requirement; executable governance tests/artifact audit | 6ec7080 |
| MS-997 | VERIFIED_LOCAL | evidence allowlist rejects passwords, tokens, secrets and unnecessary personal content; executable governance tests/artifact audit | 6ec7080 |
| MS-998 | VERIFIED_LOCAL | failure-path contracts/tests require real errors to remain typed failures rather than synthetic success; executable governance tests/artifact audit | 6ec7080 |
| MS-999 | VERIFIED_LOCAL | REAL_DEVICE_TEST_MATRIX and live queue enumerate connected accounts, messengers, Apple domains, personal search and CarPlay checks; executable governance tests/artifact audit | 6ec7080 |


| MS-1005 | READY_FOR_LIVE_VERIFICATION | embedded ShareExtension target and App Group envelope path compile and link; production/routing behavioral tests; physical execution is in the exact Share/Scanner live queue | b837945 |
| MS-1006 | READY_FOR_LIVE_VERIFICATION | share loader accepts bounded URL/webpage/text/vCard/image/document typed inputs; production/routing behavioral tests; physical execution is in the exact Share/Scanner live queue | b837945 |
| MS-1007 | READY_FOR_LIVE_VERIFICATION | shared envelope feeds the existing typed action router instead of a parallel engine; production/routing behavioral tests; physical execution is in the exact Share/Scanner live queue | b837945 |
| MS-1008 | READY_FOR_LIVE_VERIFICATION | extension performs bounded one-item ingestion and defers heavy work to the host; production/routing behavioral tests; physical execution is in the exact Share/Scanner live queue | b837945 |
| MS-1009 | READY_FOR_LIVE_VERIFICATION | structured item kind/payload/source/time context survives exact one-time host consumption; production/routing behavioral tests; physical execution is in the exact Share/Scanner live queue | b837945 |
| MS-1010 | VERIFIED_LOCAL | public clipboard capability audit selects explicit UIPasteboard user invocation only; production/routing behavioral tests | b837945 |
| MS-1011 | VERIFIED_LOCAL | SystemUserInitiatedClipboardReader supports explicit URL/text command reads and typed unavailable error; production/routing behavioral tests | b837945 |
| MS-1012 | VERIFIED_LOCAL | no launch/background polling exists and tests invoke clipboard only through the explicit method; production/routing behavioral tests | b837945 |
| MS-1013 | READY_FOR_LIVE_VERIFICATION | Safari audit selects the useful Share Extension path and avoids a duplicative web extension; production/routing behavioral tests; physical execution is in the exact Share/Scanner live queue | b837945 |
| MS-1014 | READY_FOR_LIVE_VERIFICATION | shared Safari URL/page context reaches the existing host action path; production/routing behavioral tests; physical execution is in the exact Share/Scanner live queue | b837945 |
| MS-1015 | READY_FOR_LIVE_VERIFICATION | VisionKit DataScanner production controller supports QR/EAN/UPC/Code128; production/routing behavioral tests; physical execution is in the exact Share/Scanner live queue | b837945 |
| MS-1016 | READY_FOR_LIVE_VERIFICATION | validated QR URL/vCard/ticket semantics map only to compatible typed actions; production/routing behavioral tests; physical execution is in the exact Share/Scanner live queue | b837945 |
| MS-1017 | READY_FOR_LIVE_VERIFICATION | barcode path validates GTIN before product-evidence discovery; production/routing behavioral tests; physical execution is in the exact Share/Scanner live queue | b837945 |
| MS-1018 | READY_FOR_LIVE_VERIFICATION | invalid/unknown barcode never becomes an invented product identity; production/routing behavioral tests; physical execution is in the exact Share/Scanner live queue | b837945 |
| MS-1019 | READY_FOR_LIVE_VERIFICATION | VNDocumentCameraViewController production coordinator captures user-scanned pages; production/routing behavioral tests; physical execution is in the exact Share/Scanner live queue | b837945 |
| MS-1020 | READY_FOR_LIVE_VERIFICATION | captured document pages feed local Vision OCR and typed save/document output; production/routing behavioral tests; physical execution is in the exact Share/Scanner live queue | b837945 |
| MS-1021 | READY_FOR_LIVE_VERIFICATION | only validated extracted dates/merchant/amount/action fields feed subsequent actions; production/routing behavioral tests; physical execution is in the exact Share/Scanner live queue | b837945 |
| MS-1022 | READY_FOR_LIVE_VERIFICATION | vCard validation uses Contacts and presents the system user-confirmed new-contact UI; production/routing behavioral tests; physical execution is in the exact Share/Scanner live queue | b837945 |


| MS-1023 | VERIFIED_LOCAL | BillsReceiptsDocumentsEngine models bills/receipts/invoices/warranties/tickets with typed fact confidence; behavioral production-path tests | 20c0a4e |
| MS-1024 | VERIFIED_LOCAL | bill query reuses concurrent authorized Files/Notes/connected-email personal search with provenance; behavioral production-path tests | 20c0a4e |
| MS-1025 | VERIFIED_LOCAL | only a verified due date can produce a typed reminder plan; behavioral production-path tests | 20c0a4e |
| MS-1026 | VERIFIED_LOCAL | bill payment is a confirmed official HTTPS handoff and never payment success; behavioral production-path tests | 20c0a4e |
| MS-1027 | VERIFIED_LOCAL | engine contains no banking credential capture or unauthorized bank automation path; behavioral production-path tests | 20c0a4e |
| MS-1028 | VERIFIED_LOCAL | receipt purchase and warranty reminders require verified linked evidence; behavioral production-path tests | 20c0a4e |
| MS-1029 | VERIFIED_LOCAL | assistant documents retain source object ID and exact personal-search open reference; behavioral production-path tests | 20c0a4e |
| MS-1030 | VERIFIED_LOCAL | ParcelDeliveryEngine validates identifiers and performs modular bounded provider fanout; behavioral production-path tests | d6c79b7 |
| MS-1031 | READY_FOR_LIVE_VERIFICATION | Nova Poshta official request/response adapter and credential factory are production-tested; exact provider execution remains in LIVE_VERIFICATION_QUEUE | d6c79b7 |
| MS-1032 | READY_FOR_LIVE_VERIFICATION | Ukrposhta bearer/query adapter and response/error mapping are production-tested; exact provider execution remains in LIVE_VERIFICATION_QUEUE | d6c79b7 |
| MS-1033 | READY_FOR_LIVE_VERIFICATION | Meest OAuth/bearer adapter, nested response and coordinate validation are production-tested; exact provider execution remains in LIVE_VERIFICATION_QUEUE | d6c79b7 |
| MS-1034 | VERIFIED_LOCAL | ParcelDeliveryProvider remains provider-neutral and isolates provider-specific rules; behavioral production-path tests | d6c79b7 |
| MS-1035 | READY_FOR_LIVE_VERIFICATION | tracking command uses explicit validated carrier identifier and exact attributed results; exact provider execution remains in LIVE_VERIFICATION_QUEUE | d6c79b7 |
| MS-1036 | READY_FOR_LIVE_VERIFICATION | status, ETA and branch facts require provider evidence and unknown remains unknown; exact provider execution remains in LIVE_VERIFICATION_QUEUE | d6c79b7 |
| MS-1037 | READY_FOR_LIVE_VERIFICATION | persistent expiring parcel watches schedule deduplicated jobs and notify only on changed state; exact provider execution remains in LIVE_VERIFICATION_QUEUE | d6c79b7 |
| MS-1038 | VERIFIED_LOCAL | GovernmentLocalServicesEngine audit records official Ukrainian/municipal capabilities and limits; behavioral production-path tests | 79c093a |
| MS-1039 | READY_FOR_LIVE_VERIFICATION | Diia partner-depth path requires approved organization, credentials and explicit user consent; exact provider execution remains in LIVE_VERIFICATION_QUEUE | 79c093a |
| MS-1040 | VERIFIED_LOCAL | private Diia document access is explicitly rejected and never claimed; behavioral production-path tests | 79c093a |
| MS-1041 | VERIFIED_LOCAL | official parking/Kyiv Digital/utility handoffs are typed, confirmed and host-validated; behavioral production-path tests | 79c093a |
| MS-1042 | VERIFIED_LOCAL | government actions require configured authoritative official HTTPS sources; behavioral production-path tests | 79c093a |
| MS-1043 | VERIFIED_LOCAL | FoodDeliveryComparisonEngine performs bounded concurrent normalized provider comparison; behavioral production-path tests | 03d8803 |
| MS-1044 | READY_FOR_LIVE_VERIFICATION | Glovo official capability audit distinguishes partner API from unproven consumer access; exact provider execution remains in LIVE_VERIFICATION_QUEUE | 03d8803 |
| MS-1045 | READY_FOR_LIVE_VERIFICATION | Bolt Food official capability audit preserves partner authorization boundary; exact provider execution remains in LIVE_VERIFICATION_QUEUE | 03d8803 |
| MS-1046 | VERIFIED_LOCAL | FoodDeliveryProvider is modular for other authorized regional providers; behavioral production-path tests | 03d8803 |
| MS-1047 | READY_FOR_LIVE_VERIFICATION | ranking uses verified Decimal delivered total including required fees and verified ETA; exact provider execution remains in LIVE_VERIFICATION_QUEUE | 03d8803 |
| MS-1048 | READY_FOR_LIVE_VERIFICATION | food request applies availability/ETA/price constraints and truthful provider coverage; exact provider execution remains in LIVE_VERIFICATION_QUEUE | 03d8803 |
| MS-1049 | READY_FOR_LIVE_VERIFICATION | ordering requires confirmation/exact provider handoff and never reports fake placement; exact provider execution remains in LIVE_VERIFICATION_QUEUE | 03d8803 |
| MS-1050 | VERIFIED_LOCAL | AppointmentEngine supplies one typed provider-neutral availability/booking foundation; behavioral production-path tests | 075d649 |
| MS-1051 | VERIFIED_LOCAL | typed extensible categories cover lawful medical/salon/vehicle/veterinary/repair services; behavioral production-path tests | 075d649 |
| MS-1052 | READY_FOR_LIVE_VERIFICATION | only fresh provider-attributed explicitly verified slots satisfy availability search; exact provider execution remains in LIVE_VERIFICATION_QUEUE | 075d649 |
| MS-1053 | READY_FOR_LIVE_VERIFICATION | direct booking requires confirmation and authoritative matching provider read-back; exact provider execution remains in LIVE_VERIFICATION_QUEUE | 075d649 |
| MS-1054 | READY_FOR_LIVE_VERIFICATION | only confirmed bookings create linked Calendar drafts and route-evidence departure plans; exact provider execution remains in LIVE_VERIFICATION_QUEUE | 075d649 |
| MS-1055 | READY_FOR_LIVE_VERIFICATION | reschedule/cancel require matching provider IDs/state and return linked-artifact synchronization data; exact provider execution remains in LIVE_VERIFICATION_QUEUE | 075d649 |
| MS-1056 | READY_FOR_LIVE_VERIFICATION | canonical after-15 tire-service journey enforces date/time/price/rating hard constraints; exact provider execution remains in LIVE_VERIFICATION_QUEUE | 075d649 |
| MS-1057 | VERIFIED_LOCAL | RoutineMacroEngine builds safe multi-step automation over existing capabilities; behavioral production-path tests | 5a437d0 |
| MS-1058 | VERIFIED_LOCAL | supported natural creation compiles into typed triggers/conditions/actions/dependencies; behavioral production-path tests | 5a437d0 |
| MS-1059 | VERIFIED_LOCAL | home/store route example compiles to existing navigation and along-route capabilities; behavioral production-path tests | 5a437d0 |
| MS-1060 | VERIFIED_LOCAL | RoutineMacroStore atomically persists structured definitions and RoutineExecutionLedger claims events; behavioral production-path tests | 5a437d0 |
| MS-1061 | VERIFIED_LOCAL | store supports typed edit/delete/enable/disable across restart; behavioral production-path tests | 5a437d0 |
| MS-1062 | VERIFIED_LOCAL | each routine step enforces existing permission and consequential confirmation policy; behavioral production-path tests | 5a437d0 |
| MS-1063 | VERIFIED_LOCAL | cycles/recursion are unencodable or rejected; cancellation/idempotency/partial failure are tested; behavioral production-path tests | 5a437d0 |
| MS-1064 | VERIFIED_LOCAL | CurrentContext is a structured local Codable context rather than a raw transcript; behavioral production-path tests | 8e7a96c |
| MS-1065 | VERIFIED_LOCAL | context includes time/location/route/event/task/entities/selection/services/preferences with provenance; behavioral production-path tests | 8e7a96c |
| MS-1066 | VERIFIED_LOCAL | global and per-object expiration reject stale provider objects; behavioral production-path tests | 8e7a96c |
| MS-1067 | VERIFIED_LOCAL | typed cheaper/navigate/call/reschedule/along-route followups resolve deterministically; behavioral production-path tests | 8e7a96c |
| MS-1068 | VERIFIED_LOCAL | manual reset and deny-by-default externalPayload minimize private context disclosure; behavioral production-path tests | 8e7a96c |
| MS-1069 | VERIFIED_LOCAL | UniversalActionGraph models reusable verified cross-domain entities/actions/results; behavioral production-path tests | 2737995 |
| MS-1070 | VERIFIED_LOCAL | entity taxonomy includes person/place/product/store/email/document/event/reminder/ticket/parcel/appointment/route/provider result; behavioral production-path tests | 2737995 |
| MS-1071 | VERIFIED_LOCAL | typed action taxonomy covers canonical search/open/show/call/message/route/create/remind/compare/book/cancel/reschedule/track/share; behavioral production-path tests | 2737995 |
| MS-1072 | VERIFIED_LOCAL | provider adapters register explicit capabilities and return typed verified results; behavioral production-path tests | 2737995 |
| MS-1073 | VERIFIED_LOCAL | composition validates provenance/freshness/kind/confirmation before producing typed invocation; behavioral production-path tests | 2737995 |
| MS-1074 | VERIFIED_LOCAL | behavioral tests cover canonical email/product/ticket/parcel/appointment graph compositions; behavioral production-path tests | 2737995 |
| MS-1075 | VERIFIED_LOCAL | graph never derives execution arguments from opaque free text or provider magic; behavioral production-path tests | 2737995 |
| MS-1076 | VERIFIED_LOCAL | capability-based registration lets new adapters join compatible flows without scenario rewrites; behavioral production-path tests | 2737995 |


| MS-1077 | VERIFIED_LOCAL | GOLDEN_USER_JOURNEYS and GoldenUserJourneyCatalog define 100 distinct production acceptance records across 20 high-frequency families and five languages; catalog tests | aabe915 |
| MS-1078 | READY_FOR_LIVE_VERIFICATION | 35 local records pass executable paths and 65 provider/device records are explicitly separated; completing all 100 end-to-end records remains queued as MS-1078-LIVE-GOLDEN-JOURNEY-COUNT | aabe915 |
| MS-1079 | VERIFIED_LOCAL | GoldenJourneyExecution records recognized text, intent/entities, source, result/action, measured latency, taps, confirmations, typed status and failure reason; runner tests | 858c4e4 |
| MS-1080 | READY_FOR_LIVE_VERIFICATION | local journeys use production parser/plan plus domain behavioral suites; the 65 safe real provider/device actions remain queued as MS-1080-LIVE-GOLDEN-REAL-ACTIONS | aabe915 |
| MS-1081 | VERIFIED_LOCAL | executable runner measures no-extra-question rate, Time-to-Action and tap/confirmation counts; metric test | aabe915 |
| MS-1082 | VERIFIED_LOCAL | every journey definition records a positive realistic manual app/service-find-action baseline step count; baseline test | aabe915 |
| MS-1083 | VERIFIED_LOCAL | representative definitions record generic-AI-plus-real-action baseline steps only where comparison applies; baseline test | aabe915 |
| MS-1084 | VERIFIED_LOCAL | golden acceptance contract rejects unnecessary-step disadvantage absent compensating verified value and exposes comparable metrics | aabe915 |
| MS-1085 | VERIFIED_LOCAL | safe unambiguous fast-path families target one trigger/phrase with zero extra tap while preserving required confirmation; runner tests | aabe915 |
| MS-1086 | VERIFIED_LOCAL | every execution now yields explicit pass, fail or ready-for-live status; local mismatch is behavior-tested as fail rather than misclassified live-ready | 858c4e4 |
| MS-1087 | VERIFIED_LOCAL | runner emits privacy-conscious completion, clarification/tap, latency, fallback and live/local separation inputs without raw diagnostic persistence | 858c4e4 |


| MS-1098 | VERIFIED_LOCAL | atomic per-slice implementation/test/evidence/commit sequence is persisted in status and Git history; ExecutionStateGovernanceTests and repository artifact audit | e0dd6a3 |
| MS-1099 | VERIFIED_LOCAL | work is split into completed atomic blocks rather than unrelated unfinished big-bang changes; ExecutionStateGovernanceTests and repository artifact audit | e0dd6a3 |
| MS-1100 | VERIFIED_LOCAL | PROJECT_STATUS is the human-readable single current dashboard; ExecutionStateGovernanceTests and repository artifact audit | e0dd6a3 |
| MS-1101 | VERIFIED_LOCAL | dashboard fields are updated at each measurable checkpoint and schema-tested; ExecutionStateGovernanceTests and repository artifact audit | e0dd6a3 |
| MS-1102 | VERIFIED_LOCAL | PROGRESS_HEARTBEAT is machine-readable and decoded by the governance test; ExecutionStateGovernanceTests and repository artifact audit | e0dd6a3 |
| MS-1103 | VERIFIED_LOCAL | heartbeat changes only with measurable block/evidence progress; ExecutionStateGovernanceTests and repository artifact audit | e0dd6a3 |
| MS-1104 | VERIFIED_LOCAL | state records concrete tests, evidence, commits and next work as measurable progress; ExecutionStateGovernanceTests and repository artifact audit | e0dd6a3 |
| MS-1105 | VERIFIED_LOCAL | attempt policy rejects equivalent rewrites/reruns as completion evidence; ExecutionStateGovernanceTests and repository artifact audit | e0dd6a3 |
| MS-1106 | VERIFIED_LOCAL | ATTEMPT_LEDGER persists structured method/error/diagnosis/result records; ExecutionStateGovernanceTests and repository artifact audit | e0dd6a3 |
| MS-1107 | VERIFIED_LOCAL | failed method signatures persist for later resume; ExecutionStateGovernanceTests and repository artifact audit | e0dd6a3 |
| MS-1108 | VERIFIED_LOCAL | unchanged deterministic retry is prohibited by persisted attempt identity; ExecutionStateGovernanceTests and repository artifact audit | e0dd6a3 |
| MS-1109 | VERIFIED_LOCAL | same failure plus same method must stop pending material change; ExecutionStateGovernanceTests and repository artifact audit | e0dd6a3 |
| MS-1110 | VERIFIED_LOCAL | first failure requires recorded diagnosis before another attempt; ExecutionStateGovernanceTests and repository artifact audit | e0dd6a3 |
| MS-1111 | VERIFIED_LOCAL | retry requires substantive material input/configuration/code change; ExecutionStateGovernanceTests and repository artifact audit | e0dd6a3 |
| MS-1112 | VERIFIED_LOCAL | ledger schema records qualifying material changes; ExecutionStateGovernanceTests and repository artifact audit | e0dd6a3 |
| MS-1113 | VERIFIED_LOCAL | cosmetic changes are not accepted as material retry justification; ExecutionStateGovernanceTests and repository artifact audit | e0dd6a3 |
| MS-1114 | VERIFIED_LOCAL | post-failure execution requires prior persisted justification; ExecutionStateGovernanceTests and repository artifact audit | e0dd6a3 |
| MS-1115 | VERIFIED_LOCAL | missing justification prevents retry; ExecutionStateGovernanceTests and repository artifact audit | e0dd6a3 |
| MS-1116 | VERIFIED_LOCAL | subsequent attempt must record a new evidence-backed hypothesis; ExecutionStateGovernanceTests and repository artifact audit | e0dd6a3 |
| MS-1117 | VERIFIED_LOCAL | alternative method identity must actually differ; ExecutionStateGovernanceTests and repository artifact audit | e0dd6a3 |
| MS-1118 | VERIFIED_LOCAL | transient exception is separately classified; ExecutionStateGovernanceTests and repository artifact audit | e0dd6a3 |
| MS-1119 | VERIFIED_LOCAL | transient retry count/backoff must be bounded; ExecutionStateGovernanceTests and repository artifact audit | e0dd6a3 |
| MS-1120 | VERIFIED_LOCAL | credentials/schema/permission errors are deterministic not transient; ExecutionStateGovernanceTests and repository artifact audit | e0dd6a3 |
| MS-1121 | VERIFIED_LOCAL | authoritative limitation evidence terminates impossible paths; ExecutionStateGovernanceTests and repository artifact audit | e0dd6a3 |
| MS-1122 | VERIFIED_LOCAL | external blocker records exact dependency and resume action; ExecutionStateGovernanceTests and repository artifact audit | e0dd6a3 |
| MS-1123 | VERIFIED_LOCAL | external blocker does not stop independent roadmap work; ExecutionStateGovernanceTests and repository artifact audit | e0dd6a3 |
| MS-1124 | VERIFIED_LOCAL | locally solvable failures remain engineering work; ExecutionStateGovernanceTests and repository artifact audit | e0dd6a3 |
| MS-1125 | VERIFIED_LOCAL | watchdog detects lack of measurable progress after policy threshold; ExecutionStateGovernanceTests and repository artifact audit | e0dd6a3 |
| MS-1126 | VERIFIED_LOCAL | LONG_RUNNING healthy work is explicitly exempt from false stall; ExecutionStateGovernanceTests and repository artifact audit | e0dd6a3 |
| MS-1127 | VERIFIED_LOCAL | unchanged documentation reread is not progress; ExecutionStateGovernanceTests and repository artifact audit | e0dd6a3 |
| MS-1128 | VERIFIED_LOCAL | unchanged deterministic build rerun is prohibited; ExecutionStateGovernanceTests and repository artifact audit | e0dd6a3 |
| MS-1129 | VERIFIED_LOCAL | unchanged failing provider/API request is prohibited; ExecutionStateGovernanceTests and repository artifact audit | e0dd6a3 |
| MS-1130 | VERIFIED_LOCAL | unchanged install/config loop is prohibited; ExecutionStateGovernanceTests and repository artifact audit | e0dd6a3 |
| MS-1131 | VERIFIED_LOCAL | policy conserves bounded execution/time resources; ExecutionStateGovernanceTests and repository artifact audit | e0dd6a3 |
| MS-1132 | VERIFIED_LOCAL | DevelopmentStateWatchdog performs lightweight local state freshness/consistency inspection; ExecutionStateGovernanceTests and repository artifact audit | e0dd6a3 |
| MS-1133 | VERIFIED_LOCAL | watchdog is diagnostic and cannot mutate success or restart work; ExecutionStateGovernanceTests and repository artifact audit | e0dd6a3 |
| MS-1134 | VERIFIED_LOCAL | PROJECT_STATUS explicitly contains STALLED state; ExecutionStateGovernanceTests and repository artifact audit | e0dd6a3 |
| MS-1135 | VERIFIED_LOCAL | dashboard separates exact external blockers; ExecutionStateGovernanceTests and repository artifact audit | e0dd6a3 |
| MS-1136 | VERIFIED_LOCAL | dashboard records last measurable real progress; ExecutionStateGovernanceTests and repository artifact audit | e0dd6a3 |
| MS-1137 | VERIFIED_LOCAL | dashboard always records next block; ExecutionStateGovernanceTests and repository artifact audit | e0dd6a3 |
| MS-1138 | VERIFIED_LOCAL | resume state is reconstructed from heartbeat/ledger; ExecutionStateGovernanceTests and repository artifact audit | e0dd6a3 |
| MS-1139 | VERIFIED_LOCAL | failed paths survive sessions in ATTEMPT_LEDGER; ExecutionStateGovernanceTests and repository artifact audit | e0dd6a3 |
| MS-1140 | VERIFIED_LOCAL | typed attempt identity prevents claiming an unchanged method is new; ExecutionStateGovernanceTests and repository artifact audit | e0dd6a3 |
| MS-1141 | VERIFIED_LOCAL | status claims require implementation/test/commit or exact live evidence; ExecutionStateGovernanceTests and repository artifact audit | e0dd6a3 |
