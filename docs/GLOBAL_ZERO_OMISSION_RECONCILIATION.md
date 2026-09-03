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
