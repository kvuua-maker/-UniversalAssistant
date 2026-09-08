# Build 27 function repair ledger

Authoritative base: `b85822247ec39c577ea9c92460eb3dca8ab6473a` (0.1.0 Build 26).

Physical status is not assigned here. `GREEN` means source implementation is connected to the production path and applicable automated gates pass; owner iPhone retesting remains required.

## Stable execution status

| ID | Status |
|---|---|
| B27-00 | GREEN |
| B27-01 | GREEN |
| B27-02 | GREEN |
| B27-03 | GREEN |
| B27-04 | GREEN |
| B27-05 | GREEN |
| B27-06 | GREEN |
| B27-07 | GREEN |
| B27-08 | GREEN |
| B27-09 | GREEN |
| B27-10 | GREEN |
| B27-11 | GREEN |
| B27-12 | GREEN |
| B27-13 | GREEN |
| B27-14 | GREEN |
| B27-14.01 | GREEN |
| B27-14.02 | GREEN |
| B27-14.03 | GREEN |
| B27-14.04 | GREEN |
| B27-14.05 | GREEN |
| B27-14.06 | GREEN |
| B27-14.07 | GREEN |
| B27-14.08 | GREEN |
| B27-14.09 | GREEN |
| B27-14.10 | GREEN |
| B27-14.11 | GREEN |
| B27-14.12 | GREEN |
| B27-14.13 | GREEN |
| B27-14.14 | GREEN |
| B27-14.15 | GREEN |
| B27-14.16 | GREEN |
| B27-14.17 | GREEN |
| B27-14.18 | GREEN |
| B27-14.19 | EXTERNAL_PROVIDER_DEPENDENCY |
| B27-14.20 | EXTERNAL_PROVIDER_DEPENDENCY |
| B27-15 | GREEN |
| B27-16 | GREEN |
| B27-17 | GREEN |
| B27-18 | GREEN |
| B27-19 | GREEN |
| B27-20 | GREEN |
| B27-21 | GREEN |
| B27-22 | NOT_STARTED |
| B27-23 | GREEN |
| B27-24 | NOT_STARTED |
| B27-25 | IN_PROGRESS |

## CLOSED approaches

| Family | Attempted mechanism | Evidence | Why closed | Materially different mechanism |
|---|---|---|---|---|
| Contacts / Files | Per-provider three-second timeout plus injected source tests | Build 26 still hung on physical Contacts and Files commands | The stripped query lost its source kind, so universal personal search fanned out to Contacts, Photos, and Files before the timeout boundary could provide canonical behavior | Route `.contactLookup` directly to the bounded Contacts resolver and `.fileSearch` directly to the public security-scoped document picker |
| Semantic Photos | Broad accessible-asset matching | Build 26 returned unrelated latest assets and hung | Accessibility is not semantic relevance | Require bounded local analysis and fail closed when relevance is unproven |
| Voice QR/entities | Narrow hints and token substitutions | Build 26 still produced Q-club/verb corruption | Phrase hints did not repair capture/final reconciliation | Repair the public Speech lifecycle and confidence-aware structured entity recovery |
| System actions | Broad `.deviceAction` followed by unavailable/web fallback | Build 26 sent recognized device intents to Google or generic unavailable | Capability kind was not resolved before fallback | Typed public-capability registry with local truthful limitation and documented handoff |
| Multi-step | Injected coordinator tests | Build 26 leaked abstract planner identifiers physically | Test bypassed the full Home production boundary | Preserve concrete lowering and add Home-to-renderer production tests |

## Completed material repair: B27-14.01 / B27-14.02

Physical evidence: Files search and Contacts lookup could remain processing for tens of seconds or indefinitely. The production route stripped the source-bearing words and passed only names such as `PDF` or `Сашко` into `UniversalPersonalSearchEngine`. Source routing then had no Files/Contacts marker and selected every available personal source.

Material repair:
- `.contactLookup` now invokes the existing bounded `ContactResolving` production boundary directly.
- `.fileSearch` now presents the public security-scoped document picker directly; iOS has no public API for silently searching arbitrary Files providers.
- Existing normal-call routing remains `tel:` and explicit WhatsApp remains a separate `https://wa.me/` handoff.

Production-boundary regression: `ProductionPersonalRoutingBoundaryTests` proves Contacts and Files commands do not invoke an injected unrelated Photos source. Affected Contacts lifecycle, call routing, local-source, and Home result tests pass. Physical retest remains required.

## In-progress material repair: B27-14.03

Build 26 evidence closed the UserDefaults-base64-only Share Extension approach: large image payloads could be classified first as file URLs and were not durably represented as image context. Current WIP prioritizes the public image type, writes image bytes atomically into the shared App Group container, stores only a small typed envelope, and keeps host decoding backward-compatible with prior base64 envelopes.

Semantic Photos WIP replaces the physically disproven broad accessible-asset result with confidence-filtered Vision classification, localized category normalization, a five-second production deadline, cancellation, and late-result suppression. Five seconds is bounded below the app request lifecycle while allowing up to twenty local thumbnails; timeout fails closed with no unrelated asset.

### Verification infrastructure note

On 2026-09-07, after compilation, Xcode could not materialize the XCTest runner on either iPhone 17 Pro or iPhone 17 Pro Max (iOS 26.5). Coordinator evidence showed `_IDEInstalliPhoneSimulatorWorker` and `IDELaunchiPhoneSimulatorLauncher` unfinished. A clean boot completed, but direct `xcrun simctl install` also blocked without response. This is recorded as test infrastructure evidence, not as a product PASS or FAIL. The shared CoreSimulator service was not restarted because unrelated simulator workloads were active on the Mac.

### Verification result

After a clean simulator boot and successful direct `simctl install`, the already-built Photos/Share/CurrentContext/OCR suites passed. Contacts/Calls/Home lifecycle regressions also passed on the same test host. The earlier installation stall is CLOSED as an infrastructure incident; no product code was changed to mask it.

Contacts lookup now also stores verified telephone actions in `CurrentContext`, so a selected contact can be acted on without returning to universal personal-source fan-out.

## Completed material repair: B27-14.03

Physical evidence: Build 26 returned unrelated semantic assets, did not retain typed PhotoKit identity, and did not bind selected-photo OCR or Share to a fresh asset.

Material repair:
- Semantic search is bounded to five seconds, confidence-filtered, cancellable, and fails closed.
- Latest and semantic results populate CurrentContext as typed photo entities with exact PhotoKit identifiers and bounded provenance.
- Replace and expiry semantics prevent stale asset reuse.
- Photo presentation loads the exact PHAsset through PhotoKitAssetImageLoader; public actions use UIActivityViewController for Share and local Vision OCR.
- Share Extension images remain atomic App Group file-backed typed envelopes consumed once by the host.

Production evidence: PhotoKit execution creates typed photo actions, AssistantViewModel dispatches the exact asset into PhotoAssetPresentationView, and follow-up resolves only a fresh typed identifier. No ph URL execution path is used.

Verification: Development compile PASS; affected Photos, Share, CurrentContext and OCR run PASS, 24 tests in 4 suites. Owner physical retest remains required.

## Exact continuation point

Checkpoint source HEAD before this ledger update: `398b6c8`.

Completed and verified in this execution:
- B27-14.01 Files Home routing no longer fans out into unrelated personal sources; it opens the public security-scoped document picker.
- B27-14.02 Contacts lookup/calling uses the bounded resolver directly; normal calls remain `tel:`, explicit WhatsApp remains separate, and contact results now populate `CurrentContext` with verified telephone actions.
- B27-14.03 partial: semantic Photos has a bounded five-second production deadline, confidence filtering, localized category matching, cancellation, and stale completion suppression; Share Extension prioritizes image semantics and persists image bytes atomically in the App Group container rather than large UserDefaults blobs; host OCR reads the typed file payload.

PASS evidence:
- affected Contacts/Calls/Home/local-source tests: PASS;
- Photos/Share/CurrentContext/OCR tests: PASS;
- localized semantic photo + deadline test: PASS;
- Development compile: PASS.

Unfinished B27 root groups: B27-10, B27-11, remaining B27-12/B27-13, B27-14.03 through B27-14.20 except the verified portions recorded above, B27-15 through B27-22, B27-24 and B27-25. Build 27 does not exist.

Exact next code-level operation: begin B27-14.04 in the production Home path. Audit the existing CameraIntelligenceCore, ScannerProductionRouter, OCRProductionPipeline, VisionKit document-scanner presentation and SharedContentActionRouter; then connect typed and normalized-voice OCR, QR and document-scan intents to concrete public scanner or Vision execution. Preserve typed QR and OCR physical passes, extend full-receipt OCR result handling, provide safe QR payload continuation, and add scan to OCR to translation production-boundary regressions. Keep B27-14.04 IN_PROGRESS until affected suites and Development compile pass.


## Completed material repair: B27-14.04

Physical evidence: Build 26 typed OCR reached only a single-image path, voice/document scan could fall through, a public VisionKit document coordinator was not presented by Home, and the QR result exposed a generic Execute control without identifying the safe concrete continuation.

Material repair:
- Canonical camera parsing now converges Ukrainian, Russian and English document-scan variants on `cameraCapture` with `capture_mode=text_scan` and `input_source=document_camera`.
- Home presents public `VNDocumentCameraViewController` through `SystemDocumentScannerView`; all scanned pages feed the existing on-device `VNRecognizeTextRequest` pipeline and retain page order.
- Existing camera OCR and security-scoped picked-document OCR remain separate supported entry points.
- QR/barcode results expose concrete safe action labels; URL, telephone and vCard payloads retain confirmation, plain text copies locally, unsupported/payment schemes fail closed, and validated GTIN uses the existing truthful product web handoff rather than fabricated product data.
- OCR result actions remain local Copy, public Share Sheet and Apple Translation continuation.

Production-boundary verification: Development compile PASS. `ProductionScannerTests`, `ProductionOCRTests`, `VoiceTextInputQualityTests`, and `ProductionTranslationTests` PASS: 42 tests in 4 suites. Coverage includes scanner presentation, ASR QR recovery scope, document-scan semantic variants, two-page OCR, Home result ownership, safe QR classifications/actions, GTIN handoff, shared-image OCR and OCR-to-translation continuation. Owner physical retest remains required.

## Exact continuation point after B27-14.04

Checkpoint source HEAD before commit: `35e735f`. B27-14.04 is GREEN. Build 27 does not exist.

Unfinished B27 root groups: B27-10, B27-11, remaining B27-12/B27-13, B27-14.05 through B27-14.20 except the external-provider status already recorded, B27-15 through B27-22, B27-24 and B27-25.

Exact next code-level operation: begin B27-14.05 Calendar. Trace `LocalCommandEngine` calendar action/date/time/title/duration extraction through `ProductionEventKitCommandExecutor`; repair today/tomorrow query and natural create commands independently of word order, preserve the physically passing tomorrow query/create paths, and add Home production-boundary permission/query/create tests before marking GREEN.


## Completed material repair: B27-14.05

Physical evidence: Build 26 could read tomorrow but clarified on today, while natural calendar creation failed despite EventKit access.

Material repair:
- Calendar action, local date/time, title and duration are extracted independently from natural word order before EventKit execution.
- Fixed minute/hour durations produce exact event end dates; temporal and duration clauses no longer leak into the event title.
- Today/tomorrow queries use the requested local calendar-day interval.
- The existing public EventKit full-access request, immediate authorization refresh and pending-command continuation remain the production permission path.

Verification: EventKitCommandExecutorDirectTests, CalendarServiceTests, NaturalDateTimeResolverTests and VoiceTextInputQualityTests PASS: 38 tests in 4 suites. Development compile PASS. Owner physical retest remains required.

## Exact continuation point after B27-14.05

B27-14.05 is GREEN. Build 27 does not exist.

Unfinished B27 root groups: B27-10, B27-11, remaining B27-12/B27-13, B27-14.06 through B27-14.19, B27-15 through B27-22, B27-24 and B27-25. B27-14.20 remains EXTERNAL_PROVIDER_DEPENDENCY pending the configured-provider audit.

Exact next code-level operation: begin B27-14.06 Reminders. Trace LocalCommandEngine reminder create/query/open semantics through ProductionEventKitCommandExecutor; repair tomorrow-at-time creation, today/list/open commands and title extraction while preserving the physically passing relative +10 minute path. Add production-boundary EventKit permission/result regressions, then run affected suites and Development compile.


## Completed material repair: B27-14.06

Physical evidence: the relative +10 minute reminder path worked, while tomorrow-at-time creation fell to web and reminder open/list/today variants were not classified consistently.

Material repair:
- Reminder query/open/list semantic variants converge on reminderQuery before generic open/web handling.
- Date-scoped queries call the public EventKit reminder boundary with the requested local-day interval.
- Natural absolute-time creation preserves the resolved deadline and strips control, temporal and duration wording from the saved title.
- Existing relative reminder execution, EventKit authorization refresh, mutation history and undo are preserved.

Verification: EventKitCommandExecutorDirectTests, CalendarServiceTests, ReminderServiceTests, NaturalDateTimeResolverTests and VoiceTextInputQualityTests PASS: 45 tests in 5 suites. Development compile PASS. Owner physical retest remains required.

CLOSED locally disproven test expectation: preserving polite control wording and punctuation in the saved reminder title. Evidence showed the production extractor correctly retained a comma before the material fix. The new mechanism removes localized polite control phrases before payload formation; the unchanged approach will not be repeated.

## Exact continuation point after B27-14.06

B27-14.06 is GREEN. Build 27 does not exist.

Exact next code-level operation: begin B27-14.07 Timer/Alarm consistency. Preserve the physically firing AlarmKit paths, trace voice/typed alarm time and optional label extraction through LocalCommandEngine and SystemQuickActionExecutor, repair equivalent voice convergence and timer/alarm result naming without changing public AlarmKit scheduling, then add unseen-parameter production regressions and run affected suites plus Development compile.


## Completed material repair: B27-14.07

Physical evidence: AlarmKit timers and one typed alarm physically fired, but equivalent create wording diverged, alarm/timer result identity was inconsistent, and a named timer lost its label.

Material repair:
- General Ukrainian, Russian and English create/set timer and alarm variants converge on deviceAction.
- Optional natural labels survive parsing and are carried in typed SystemQuickAction values into AlarmKit metadata.
- Timer and alarm schedule branches remain distinct and return distinct truthful result strings.
- Existing iOS 26 availability and AlarmManager authorization gates are unchanged.

CLOSED approach: assigning a runtime String to AlarmPresentation.Alert.title. The public SDK requires LocalizedStringResource and compilation rejected the mechanism. It will not be retried unchanged. The materially different supported mechanism stores the dynamic label in AlarmMetadata while retaining a static localized system presentation title.

Verification: SystemQuickActionPlannerTests and VoiceTextInputQualityTests PASS: 22 tests in 2 suites. Development compile PASS. Physical AlarmKit execution remains owner-retest required.

## Exact continuation point after B27-14.07

B27-14.07 is GREEN. Build 27 does not exist.

Exact next code-level operation: begin B27-14.08 SYSTEM/OPEN_APP. Audit QuickLaunchPolicy, LaunchMarketAppMatrix, UniversalDeviceCommandRouter and Home presentation routing against current public mechanisms. Preserve Spotify, Apple Music, Camera and flashlight passes; repair general open-app/system-destination classification and ensure non-public brightness, volume, Low Power, Bluetooth, Wi-Fi and protected Phone/Calculator destinations terminate locally with precise public limitation rather than web. Add production-boundary unseen variants and renderer regressions.


## Completed material repair: B27-14.08

Physical evidence: Spotify, Apple Music and Camera worked but required redundant UA narration/Continue, while Files/Mail/App Store/YouTube and protected system destinations diverged or fell to web.

Material repair:
- Verified system/app handoffs execute immediately at the Home boundary through injected UIApplication.open rather than rendering another UA Continue card. OS confirmation remains authoritative.
- Generic app-word normalization removes localized program/app prefixes before exact verified alias resolution.
- Added verified HTTPS destinations for YouTube and App Store and the Apple-documented mailto handoff for Mail. Files and Camera remain typed public presentations.
- Calculator/Phone-without-number and non-public direct controls remain local unsupported results; they do not become Google searches. Normal numeric calls continue through tel.

Public API audit evidence: Apple UIKit documents UIApplication.open for http/https/tel/facetime/mailto, UIApplication.openSettingsURLString only for this app custom settings, and explicitly says system volume cannot be changed programmatically (MPVolumeView is the public UI). CoreBluetooth manages app communication with peripherals and does not expose a toggle for system Bluetooth. No private undocumented Settings URL was introduced.

Verification: UniversalDeviceCommandRouterTests, CanonicalCapabilityExecutionTests, SystemQuickActionPlannerTests and VoiceTextInputQualityTests PASS: 31 tests in 4 suites. Development compile PASS. Owner physical retest remains required.

## Exact continuation point after B27-14.08

B27-14.08 is GREEN. Build 27 does not exist.

Exact next code-level operation: begin B27-14.09 Battery/Storage. Preserve the physical local storage pass; trace broad battery semantics through LocalCommandEngine and ProductionPublicDeviceExecutor, remove automobile-battery ambiguity for device-status phrasing, verify bounded UIDevice monitoring and truthful integer formatting, and add typed/normalized-voice Home boundary regressions with different values.
\n\n## Completed material repair: B27-14.09\n\nPhysical evidence: broad battery wording could be interpreted as an automobile question and routed to web; explicit iPhone battery produced a local reading that could differ from a status-bar sample taken at another instant. Local free-storage reading physically passed and had to be preserved.\n\nMaterial repair:\n- Ukrainian, Russian and English device-battery semantic variants now converge on the canonical deviceAction before general information/web routing.\n- The production boundary remains the public UIDevice.batteryLevel read and returns its observed integer percentage at execution time; it does not claim synchronization with a separately sampled status-bar value.\n- Free-storage variants remain on the bounded local file-system capacity executor; no network fallback was introduced.\n- Unseen semantic variants are covered at parser/router level, and the injected production executor test proves the Home capability path reaches the local battery action.\n\nVerification: SystemQuickActionPlannerTests and VoiceTextInputQualityTests PASS: 21 tests in 2 suites. Development compile PASS. Owner physical retest remains required.\n\n## Exact continuation point after B27-14.09\n\nB27-14.09 is GREEN. Build 27 does not exist.\n\nExact next code-level operation: begin B27-14.10 Clipboard/Notes. Preserve clipboard write with a colon and Notes Share Sheet creation; repair punctuation-independent clipboard write, clipboard read, URL-from-clipboard and copy-current-result routing/execution/context without allowing generic web fallback. Add unseen typed/normalized-voice production-boundary tests, then run affected suites and Development compile.\n\n\n## Completed material repair: B27-14.10\n\nPhysical evidence: clipboard write worked only with colon punctuation; natural no-colon write, clipboard read, URL-from-clipboard and copy-last-result diverged to web or failed. Notes creation through the system Share Sheet physically worked and remains preserved.\n\nMaterial repair:\n- Clipboard write payload extraction is punctuation-independent and preserves the original user-authored casing/content after the localized command prefix.\n- Read and URL-open commands use the public user-initiated UIPasteboard boundary. Only concrete http/https URLs with a host can become an immediate system handoff; arbitrary clipboard text is never executed as a URL.\n- CurrentContext now stores a typed last answer with provenance and TTL. Copy-last-result consumes only a fresh answer; expired context fails as a missing parameter instead of copying stale data.\n- Canonical and configured in-app general results populate the same answer context before rendering.\n- Apple Notes data remains inaccessible to third-party apps through a public database API; note creation preserves the public user-controlled Share Sheet handoff.\n\nCLOSED locally disproven approach: the initial read vocabulary recognized only the fixed phrase “що в буфері”. Production-boundary evidence showed “Що зараз у буфері?” escaped to the specialized fallback. The unchanged narrow matcher is closed; the materially different interrogative clipboard-read semantic family covers word-order variants.\n\nVerification: NotesClipboardProductionTests, SharedContentActionRouterTests, ProductionContextContinuationTests and VoiceTextInputQualityTests PASS: 28 tests in 4 suites. Development compile PASS. Owner physical retest remains required.\n\n## Exact continuation point after B27-14.10\n\nB27-14.10 is GREEN. Build 27 does not exist.\n\nExact next code-level operation: begin B27-14.11 URL. Trace typed raw URL and explicit official-site commands through LocalCommandEngine, UniversalDeviceCommandRouter and Home handoff. Ensure validated http/https URLs open directly, obvious verified first-party destinations resolve without Google, malformed/unsafe schemes fail locally, and add production-boundary unseen-domain tests without creating a general arbitrary-app URL bypass.\n\n\n## Completed material repair: B27-14.11\n\nPhysical evidence: explicit Apple-site open was unavailable and a typed concrete HTTPS URL was converted into Google search text.\n\nMaterial repair:\n- A complete user-authored http/https URL with a concrete host is recognized before generic intent discovery and handed to UIApplication.open as a system handoff; non-http schemes never enter this route.\n- Explicit official-site requests resolve through the bounded verified first-party destination registry. Apple uses its official HTTPS destination; this does not create an arbitrary custom-scheme bypass.\n- App/site prefix normalization is token-based, Unicode-folded symmetrically for both input and prefix registry, case-insensitive and whitespace-independent.\n- Unsafe javascript input remains unknown/local and cannot be executed as an open URL.\n\nCLOSED approaches:\n- Regex prefix stripping in a Swift raw string: physical focused tests proved it did not remove whitespace prefixes because escaping represented a literal backslash sequence.\n- Token prefix stripping with only the input Unicode-folded: reproduction showed Ukrainian “сайт” folds to “саит”, while the registry remained unfurled. The asymmetric mechanism is closed. The green mechanism applies identical Unicode folding to input, registry prefixes and aliases.\n\nVerification: UniversalDeviceCommandRouterTests, CanonicalCapabilityExecutionTests and VoiceTextInputQualityTests PASS: 25 tests in 3 suites. Development compile PASS. Owner physical retest remains required.\n\n## Exact continuation point after B27-14.11\n\nB27-14.11 is GREEN. Build 27 does not exist.\n\nExact next code-level operation: begin B27-14.12 Places/Navigation/Location. Preserve resolved Apple Maps navigation; repair real-current-location nearest ranking, natural place categories, railway/airport destination resolution, travel-time and current-location/address semantics, and route-context follow-up through public CoreLocation/MapKit boundaries. Add unseen-parameter production E2E with deterministic provider/location fixtures.\n

## B27-14.12 verified partial checkpoint: physical nearest ordering

The production explicit-nearest path previously sorted only optional provider-supplied distanceMeters. MapKit candidates without that enrichment retained provider order, so current-location proximity was not guaranteed. The material repair computes geodesic distance from the resolved validated location whenever the provider omits distance, while preserving provider-supplied verified distance.

Verification: PlaceCoreTests and ProductionRouteAwareSearchTests PASS: 10 tests in 2 suites. Compilation within the focused test build PASS. B27-14.12 remains IN_PROGRESS; owner physical retest remains required.

Exact next code-level operation: continue B27-14.12 in StructuredCommand and ProductionCanonicalCapabilityExecutor by adding general current-location/current-address and travel-time canonical semantics through public CoreLocation and MapKit boundaries. Preserve the green nearest-distance and Apple Maps navigation paths.


## Completed material repair: B27-14.12

Physical evidence: resolved Apple Maps navigation worked, while railway/airport formulations, travel time, current location/address, route follow-up and true nearest ordering diverged. Nearby results could preserve provider order rather than physical distance.

Material repair:
- Explicit nearest ordering computes geodesic distance from the resolved validated current/manual location when a provider omits distanceMeters; verified provider distances remain authoritative.
- Current location uses the existing bounded CurrentLocationResolving CoreLocation boundary and returns observed coordinates locally.
- Current address uses an injectable public CLGeocoder reverseGeocodeLocation boundary and a concise deduplicated postal description.
- Travel-time semantics resolve the current origin and arbitrary destination, call the injected MapKit RouteProvider for driving/walking duration, return a sourced in-app result, and seed the same typed route CurrentContext.
- Typed and normalized voice inputs share the LocalCommandEngine deviceAction path; none of these families can fall through to generic web.

CLOSED approaches:
- Exact phrase-only address matching is closed. Production E2E proved the Ukrainian accusative form “поточну адресу” escaped to contextual show. The green matcher uses address/location stems plus self/current semantics independent of word order and inflection.
- The first test expected 10 minutes although its route fixture returned 360 seconds. That expectation is closed; result assertions now follow the injected route evidence.

Verification: ProductionRouteAwareSearchTests, PlaceCoreTests and VoiceTextInputQualityTests PASS: 24 tests in 3 suites. Development compile PASS. Owner physical retest remains required.

## Exact continuation point after B27-14.12

B27-14.12 is GREEN. Build 27 does not exist.

Exact next code-level operation: begin B27-14.13 Weather. Preserve the physically working Kyiv WeatherKit path; trace arbitrary-location and current-location parsing through the production weather executor, remove city special-casing or missing-location divergence, and add production-boundary tests with unseen locations plus current-location permission outcomes.

## Completed checkpoints B27-14.13 through B27-14.16

B27-14.13 Weather — GREEN. Root cause: ProductionWeatherCommandExecutor reparsed through the city-limited GenericIntentParser and rejected current-location weather. Material repair: canonical StructuredCommand now preserves arbitrary locality or current-location semantics; production uses ManualLocationContextResolver or AppleCurrentLocationResolver, then bounded WeatherContextEngine/AppleWeatherKitProvider. The fixed-city reparse approach is CLOSED. WeatherCommandExecutionTests, WeatherContextTests and VoiceTextInputQualityTests PASS; Development compile PASS.

B27-14.14 Translation — GREEN. Root cause: exact imperative patterns and an incomplete target-language ontology let equivalent voice/morphological variants escape to web. Material repair: morphology-aware translation action family, shared Ukrainian/Russian/English target ontology, canonical source extraction that strips control language, and unchanged Apple Translation plus original-source CurrentContext. Exact-imperative-only matching is CLOSED. ProductionTranslationTests, ProductionContextContinuationTests and VoiceTextInputQualityTests PASS: 26 tests; Development compile PASS.

B27-14.15 Local Utilities — GREEN. Root cause: adjacent ASR numeric groups were parsed as separate numbers, while natural current-time/day-of-month forms were absent. Material repair: utility-local confident grouped-thousands reconciliation, natural Ukrainian/Russian clock/date semantics, preserved deterministic arithmetic/percentage/fixed units, and explicit externalProviderRequired(current_fx_rate) without fabricated FX. LocalUtilityEngineTests and VoiceTextInputQualityTests PASS: 21 tests; Development compile PASS.

B27-14.16 CurrentContext — GREEN. Verified one typed CurrentContextStore for route, selected PhotoKit asset, shared URL/image, original translation source, selected result/action and last answer. Replacement, expiry, explicit continuation and replay protection are covered; independent requests do not implicitly consume stale context. ProductionContextContinuationTests, ProductionRouteAwareSearchTests and NotesClipboardProductionTests PASS: 15 tests. The preceding Development compile remains applicable because this verification introduced no source change.

All four GREEN statuses are source-level only; owner physical retest remains required. Build 27 does not exist.

## Exact continuation point after B27-14.16

Exact HEAD at checkpoint: 8f7fb29ae67c0c4366531176b63de8615af0aeba before this documentation-only follow-up commit.

Exact next code-level operation: begin B27-14.17 Voice Memo. In StructuredCommand and the open-app/device registry, separate OPEN_APP Voice Memos semantics from internal VOICE_MEMO_RECORD. In AudioRecorderController, trace public AVFoundation start-pause-resume-stop, durable file/result publication and recovery after scene/app lifecycle. Add Home production-boundary lifecycle tests, crash/disappearance regression, and Development compile. Do not repeat any CLOSED approach.

## Completed material repair: B27-14.17

Physical evidence: internal voice recording started but later crashed/disappeared; an OPEN_APP Voice Memos request incorrectly started the UniversalAssistant recorder.

Material repair:
- OPEN_APP Voice Memos is classified before recorder patterns and terminates with the truthful public-iOS limitation because no documented third-party launch URL is used. It never starts AudioRecorderController.
- Internal recording retains public AVAudioSession/AVAudioRecorder start, pause, resume and stop behavior. Scene deactivation finalizes active audio and playback safely.
- Finalized nonempty m4a files live under Application Support, receive complete file protection, are recovered by newest modification date after controller/app recreation, and are published as typed document CurrentContext plus a public UIActivityViewController file result.
- Stop morphology and intent classification use one shared action family, so unseen finish variants reach the same production path.

CLOSED approaches: adding stop words only to recorderAction while leaving semantic intent classification unchanged. Production E2E proved the request still became unknown/web. The green mechanism aligns the action ontology at both canonical-intent and command-action stages.

Verification: AudioRecorderControllerTests, VoiceTextInputQualityTests and UniversalDeviceCommandRouterTests PASS: 27 tests in 3 suites. Development compile PASS. Owner physical retest remains required.

## Exact continuation point after B27-14.17

B27-14.17 is GREEN. Build 27 does not exist.

Exact next code-level operation: begin B27-14.18 Camera. Preserve public Camera open; classify take-photo separately, represent the required user shutter action truthfully through the existing camera presentation, and add production-boundary unseen variants proving no fabricated capture or web fallback.

## Completed material repair: B27-14.18

Root cause: the public in-app camera presentation already existed, but the semantic family recognized only narrow create-photo wording. Unseen Ukrainian, Russian, and English capture imperatives could miss `.cameraCapture`.

Material repair: `LocalCommandEngine.priorityIntent` now converges morphology-level capture verbs plus photo/image object families on `.cameraCapture`. Production execution remains the existing public `UIImagePickerController` presentation with a visible user shutter; the app does not claim that a photo was taken before the user acts. Existing Camera-open behavior remains separate and preserved.

Public Apple classification: PUBLIC USER-CONFIRMED IN-APP CAPTURE. `UIImagePickerController` presents the system camera UI; iOS requires the user to operate the shutter. No private Camera.app URL scheme, silent capture, or fabricated success was introduced.

Production-boundary evidence: new unseen Ukrainian/Russian/English capture variants parse to `.cameraCapture` and cross `ProductionCanonicalCapabilityExecutor` to `.presentation(.camera)`. Existing Home test proves the presentation is typed and is not rendered as a completed action.

Verification: `CanonicalCapabilityExecutionTests`, `SystemQuickActionPlannerTests`, and `AppleSystemDomainIntegrationTests` PASS (20 tests / 3 suites). Separate Development simulator compile PASS.

## Exact continuation point after B27-14.18

B27-14.18 is GREEN. Build 27 does not exist.

Exact next code-level operation: begin B27-14.19 Music Recognition. Audit the current source and installed public SDK for the existing ShazamKit boundary. If a configured legitimate recognition mechanism exists, connect the canonical voice/typed family through it with permission/audio-session/lifecycle handling and production-boundary tests. If the required catalog/session dependency is absent, implement a truthful local provider-required result and prevent Google fallback. Do not invent credentials or use undocumented mechanisms.

## Reconciled dependency: B27-14.19

Physical divergence: music-recognition requests were conflated with general media/search behavior and could reach Google advice instead of a music-recognition capability.

CLOSED failed approach: treating recognition wording as ordinary `mediaSearch`/MusicKit lookup. MusicKit catalog search does not identify ambient audio, and physical evidence disproved web advice as a substitute.

Material source repair: added the distinct `.musicRecognition` canonical intent, general Ukrainian/Russian/English recognition-question semantics, and a production executor result that truthfully identifies the missing authorized ShazamKit app capability. Music playback/search remains `.mediaSearch`. The result has no browser action and exposes no internal executor identifier.

Public Apple audit: the installed iOS SDK contains public `ShazamKit`/`SHSession`, but `UniversalAssistant.entitlements`, the project, and the currently verified App Store profile configuration contain no `com.apple.developer.shazamkit` authorization. Adding an executable entitlement without App-ID/profile authorization would create a release signing mismatch. Real ambient recognition therefore remains EXTERNAL_PROVIDER_DEPENDENCY until the owner enables ShazamKit for the App ID and supplies matching profiles.

Verification: the initial ontology omitted composition-family nouns and failed a new unseen phrase; that approach is CLOSED. The materially expanded music-object ontology (`composition`/`композ*`/`музык*`) passes. `CanonicalCapabilityExecutionTests`, `VoiceTextInputQualityTests`, and `DeterministicExecutionPlanTests` PASS (38 tests / 3 suites). Separate Development compile PASS.

## Exact continuation point after B27-14.19

B27-14.19 is EXTERNAL_PROVIDER_DEPENDENCY with the internally resolvable canonical routing and truthful renderer complete. Build 27 does not exist.

Exact next operation: reconcile B27-14.20 and then audit every remaining main B27-00 through B27-25 identifier. Prove configured general/current/product/FX providers or preserve explicit dependencies; complete the repair ledger, capability inventory, unseen-parameter acceptance, production-boundary evidence, public-iOS audit, and all required gates before Build 27.

## Reconciled dependencies: B27-14.20

Repository and Production configuration audit confirms no active general/current-information coordinator, stock feed, FX endpoint, or retail-price credential/transport. Existing contracts and test providers are not live production evidence.

Internally resolvable path is complete: canonical intents and parameters are preserved; deterministic/local/system families have priority; missing current-data classes surface only an explicit provider dependency or exact controlled browser handoff; no answer, rate, price, availability, credential, or provenance is fabricated. Exact evidence remains in `docs/BUILD26_EXTERNAL_PROVIDER_AUDIT.md` and the updated Build-27 capability matrix.

B27-14.20 remains EXTERNAL_PROVIDER_DEPENDENCY. This status does not exempt the remaining source, acceptance, matrix, or gate requirements.

## Full-gate corrective checkpoint

The first complete iOS regression exposed scheduler-dependent deadline and performance failures that focused suites did not reveal. Unchanged retry is CLOSED.

Material corrections:
- Contacts and authorized-Files deadlines now use dedicated `.userInteractive` serial deadline queues rather than the shared global work queue, so timeout ownership is not starved behind synchronous provider work. Completion remains exactly-once and cancellation/late result suppression are preserved.
- Local parser performance measurement now uses thread CPU time instead of wall-clock scheduler delay.
- The parser no longer compiles price/size/wait regular expressions per request, avoids compound parsing when no compound marker exists, and scans the fallback intent table once. Canonical precedence and multi-step semantics are protected by regression tests.

Evidence: the previously failing Contacts and Files deadline/cancellation suites PASS. Performance/voice/deterministic-plan suites PASS: 39 tests / 3 suites; parser CPU guard improved to 1.288 seconds for 1,000 parses. Backend full gate PASS: 114 tests / 28 suites. A fresh complete iOS gate is the exact next operation.


## Source completion gate evidence

B27-00 and B27-03 through B27-21 are reconciled at source level. B27-14.19 and B27-14.20 remain explicitly classified as EXTERNAL_PROVIDER_DEPENDENCY; their canonical intent, parameter, truthful renderer, and no-accidental-web paths are complete. No physical Build-27 status is claimed.

Voice and structured-number evidence: the public Speech task is created before audio capture, bounded contextual vocabulary covers mixed-language entities, partial/final transcript reconciliation feeds the same LocalCommandEngine as typed input, and structured local utilities reconcile only confident adjacent thousands while ambiguous token groups require clarification. The complete iOS regression protects these paths.

Acceptance and production-boundary evidence: the repository contains exactly 71/71 B25 forensic rows, the Build-27 capability inventory enumerates every current CommandIntent and public-iOS/provider classification, and the complete iOS gate passes 722 Swift Testing tests in 128 suites plus 9 XCTest tests. Development and Production compilation both PASS.

Canonical gates: backend PASS 114 tests/28 suites; ZERO-OMISSION 2404/2404; AUDIO 147/147; PRIVACY 168/168; JOBS 97/97; LOYALTY 127/127; live diagnostics 2/2. UI leakage, request ownership, timeout/cancellation, CurrentContext, public-system capability and unseen semantic variants are covered within the complete iOS gate.

CLOSED environment approach: detached nohup xcodebuild did not survive the managed PTY shell and produced neither log nor xcresult. The materially different managed-session execution with active polling produced the durable result at /private/tmp/UA-B27-Full-iOS-20260908-0303.xcresult and PASS.

Exact next operation: commit and push this completed source ledger, verify HEAD == origin/main and tracked tree clean, then execute B27-22 Build-27 release gate. B27-24 and B27-25 remain pending the final release report/completion.
