# Post-Build-28 Apple-native execution architecture audit

Audit date: 2026-09-08. Source checkpoint: 9b052d2c3c3ee89abadc817fc1959190bff6aa84.
Deployment target: iOS 18.0; AlarmKit is availability-gated. This is an execution
architecture audit, not a signing audit and not physical iPhone verification.

The indivisible source of truth in SPEC_SOURCE_OF_TRUTH.md, the complete current
source, Build 27 capability matrix, Build 28 ledgers/provider audit and physical
evidence were reconciled. Each row compares the current production boundary with
the deepest legitimate current public Apple mechanism.

## Complete canonical execution matrix

| # | Canonical function(s) | Current production implementation | Best current Apple mechanism | Status | Required change / public boundary / risk |
|---:|---|---|---|---|---|
| 1 | Voice recognition | VoiceInputController; SFSpeechRecognizer; AVAudioEngine | Speech streaming; locale recognizer; on-device only when supported | APPLE_NATIVE_CORRECT | Preserve generation ownership; Speech and microphone permission; contextualStrings is only a bounded hint |
| 2 | Structured numbers | StructuredNumberNormalizer | Custom typed grammar; Foundation locale formatting | APPLE_NATIVE_CORRECT | No Apple semantic-number API; preserve clarification on ambiguity |
| 3 | Semantic normalization | CanonicalSemanticFrameAnalyzer | NaturalLanguage may assist token/language evidence but does not replace the UA ontology | APPLE_NATIVE_CORRECT | Preserve structural authority; no keyword-only rollback |
| 4 | Home voice/typed convergence | AssistantViewModel shared pipeline | One shared app pipeline | APPLE_NATIVE_CORRECT | Preserve terminal-state and stale-generation ownership |
| 5 | App Intents | Existing App Intents surfaces | AppIntent with typed entities/parameters | APPLE_NATIVE_IMPROVEMENT | Expand only already-green atomic executors; never bypass permissions |
| 6 | App Shortcuts / quick launch | Existing shortcut metadata | AppShortcutsProvider and supported system surfaces | APPLE_NATIVE_IMPROVEMENT | Supplement the pipeline; cannot intercept arbitrary hardware buttons |
| 7 | Open verified app | VerifiedAppRegistry; UIApplication.open | Documented universal link or app-owned documented URL | APPLE_HANDOFF_REQUIRED | Keep allowlist/canOpenURL; never guess schemes |
| 8 | App content/action | MediaActionExecution | MusicKit or the target app’s documented App Intent/link | APPLE_HANDOFF_REQUIRED | Provider-specific only; unsupported is local limitation |
| 9 | UniversalAssistant settings | CanonicalCapabilityExecutor.settings | UIApplication.openSettingsURLString | APPLE_NATIVE_CORRECT | Opens only UA settings; user/system UI |
| 10 | iPhone/system Settings target | Typed local unavailable | No general public arbitrary Settings-pane API | PUBLIC_API_UNAVAILABLE | Keep truthful local limitation; no private URLs, UA-settings misroute or web |
| 11 | Contact search/resolution | LocalContactResolver; CNContactStore worker | Contacts off-main bounded fetch | APPLE_NATIVE_CORRECT | Preserve requested keys, permission, deadline, cancellation and generation |
| 12 | Contacts limited-access selection | Current result UI | iOS 18 ContactAccessButton/contact access picker | APPLE_NATIVE_IMPROVEMENT | Add picker continuation when limited access hides a requested contact |
| 13 | Contact create/edit | Contacts integration | CNContactViewController or explicit CNSaveRequest | APPLE_HANDOFF_REQUIRED | Prefer user-confirmed ContactsUI; never silent mutation |
| 14 | Normal telephone call | Typed contact/number to tel URL | Documented tel handoff; system confirmation | APPLE_HANDOFF_REQUIRED | Preserve numeric executor and separation from messenger SERVICE |
| 15 | Emergency call | Confirmed tel:112 | tel handoff plus risk confirmation | APPLE_HANDOFF_REQUIRED | Preserve localized confirmation and OS ownership |
| 16 | SMS/iMessage compose | MessagingIntegration | MFMessageComposeViewController after canSendText | APPLE_NATIVE_CORRECT | User edits/sends/cancels; no auto-send or message database |
| 17 | Email compose | Mail integration | MFMailComposeViewController capability check | APPLE_NATIVE_CORRECT | User-confirmed composer |
| 18 | WhatsApp/Telegram/Viber/Signal message/call | Verified service registry | Target app’s documented universal link/App Intent | APPLE_HANDOFF_REQUIRED | Explicit SERVICE only; installed/verified destination and user handoff |
| 19 | Calendar query/create/update/delete | CalendarService; EventKitCommandExecutor | EKEventStore full/write access; EventKitUI for optional manual editing | APPLE_NATIVE_CORRECT | Preserve authorization refresh, stable identity, read-back and delete confirmation |
| 20 | Reminder query/create/complete/delete | EventKitCommandExecutor | EventKit reminders full access | APPLE_NATIVE_CORRECT | Preserve post-grant reset/refresh, terminal lifecycle and destructive confirmation |
| 21 | Shopping list | EventKit-backed reminder list | EventKit Reminders | APPLE_NATIVE_CORRECT | Explicit list selection and permission |
| 22 | Timer create | AlarmKitScheduler | Public AlarmKit when available | APPLE_NATIVE_CORRECT | Preserve physical PASS, permission and usage description |
| 23 | Alarm create | AlarmKitScheduler | Public AlarmKit when available | APPLE_NATIVE_CORRECT | Preserve physical PASS and availability gate |
| 24 | Global Clock alarm/timer query | Local limitation | No unrestricted Clock database API | PUBLIC_API_UNAVAILABLE | Show only public app-owned records; never fabricate |
| 25 | Local/remote notifications | UserNotifications/APNs paths | UserNotifications plus APNs | APPLE_NATIVE_CORRECT | Preserve permission, production entitlement and truthful delivery state |
| 26 | File pick/open | SystemPresentation.documents | UIDocumentPickerViewController with UTType/security scope | APPLE_NATIVE_CORRECT | User UI is mandatory |
| 27 | File search in selected scope | Bounded personal source | Security-scoped user-selected directory/document | APPLE_NATIVE_CORRECT | No unrestricted/global Files claim |
| 28 | Open Files/global provider search | Picker fallback | No silent global provider search or guaranteed Files-app launch API | APPLE_HANDOFF_REQUIRED | Present picker/browser as deepest legitimate UI |
| 29 | PDF read/merge/split/annotate/redact | OnDevicePDFProcessor | PDFKit/CoreGraphics plus picker/share | APPLE_NATIVE_CORRECT | Keep on device; validate pages and export |
| 30 | Latest/ordinal photo | PhotoKit metadata source | PhotoKit sorted fetch | APPLE_NATIVE_CORRECT | Preserve typed PHAsset, limited/full/empty/denied states |
| 31 | Semantic photo search | PhotoKit plus local classifier | PhotoKit assets plus confidence-bearing Vision/Core ML | APPLE_NATIVE_IMPROVEMENT | Never return random recent assets; low confidence means no-result |
| 32 | Photo open/context/share | Typed PhotoKit presentation | PHImageManager and UIActivityViewController/ShareLink | APPLE_NATIVE_CORRECT | Preserve asset identity, expiry and user Share Sheet |
| 33 | Share Extension receive | NSItemProvider plus App Group | Public Share Extension and App Group container | APPLE_NATIVE_CORRECT | Preserve atomic import, dedupe and expiry; physical retest required |
| 34 | OCR on image/photo | AppleScannerIntegration | VNRecognizeTextRequest; VisionKit Live Text for interaction | APPLE_NATIVE_CORRECT | Preserve orientation, supported languages, correction and all observations |
| 35 | Live OCR | Scanner presentation | DataScannerViewController | APPLE_NATIVE_CORRECT | Check isSupported/isAvailable; camera permission |
| 36 | QR/barcode | Scanner typed result/actions | DataScannerViewController or AVFoundation metadata capture | APPLE_NATIVE_CORRECT | Safe typed payload dispatch; never auto-open unsafe content |
| 37 | Document scan | System presentation | VNDocumentCameraViewController | APPLE_NATIVE_CORRECT | User captures pages; typed images returned |
| 38 | Scan to PDF | Document scan plus PDF processor | VNDocumentCamera output to PDFKit/CoreGraphics | APPLE_NATIVE_CORRECT | Typed dependency output and user export |
| 39 | Camera open/capture | Public camera presentation | Visible camera UI or app-owned AVCaptureSession | APPLE_HANDOFF_REQUIRED | Never claim automatic system-camera shutter without user interaction |
| 40 | Clipboard read/write/open URL | UIPasteboard actions | UIPasteboard plus URLComponents and UIApplication.open | APPLE_NATIVE_CORRECT | Respect paste privacy UI; one consistent terminal state; safe schemes |
| 41 | Note create | Text to Share Sheet | UIActivityViewController; no public Notes database API | APPLE_HANDOFF_REQUIRED | User chooses Notes and saves |
| 42 | Note query/direct database | Local limitation | No public Apple Notes database API | PUBLIC_API_UNAVAILABLE | No fabricated access |
| 43 | Current location | AccurateLocationEngine | CLLocationManager | APPLE_NATIVE_CORRECT | When-In-Use is correct for foreground commands |
| 44 | Current address/city | Reverse-geocoding boundary | CoreLocation location plus public reverse geocoder | APPLE_NATIVE_CORRECT | Return requested locality/address component |
| 45 | Always location | Not enabled for foreground canon | Only justified continuous/background CoreLocation use | APPLE_NATIVE_CORRECT | Do not request merely to expose a Settings option; re-audit for a concrete background requirement |
| 46 | Place search | MapKitPlaceProvider | MKLocalSearch/POI request | APPLE_NATIVE_CORRECT | Structured, bounded, location-aware query |
| 47 | Nearest/nearby ranking | Geodesic ranking | CoreLocation plus MapKit radius/relevance | APPLE_NATIVE_CORRECT | Tighten filtering without replacing mechanism |
| 48 | Navigation | RouteEngine; NavigationHandoff | MKDirections plus MKMapItem.openInMaps | APPLE_NATIVE_CORRECT | Typed resolved destination; Maps owns turn-by-turn UI |
| 49 | Travel time | MKDirections route | MKDirections expected travel time | APPLE_NATIVE_CORRECT | Return in-app structured estimate |
| 50 | Route waypoint/on-route search | Typed route CurrentContext | MapKit route geometry plus bounded POI search | APPLE_NATIVE_CORRECT | Fresh route context; chosen waypoint continues to Maps |
| 51 | Public transport route | Route engine | MKDirections transit where available | APPLE_NATIVE_CORRECT | External provider only for unsupported real-time inventory |
| 52 | Weather | WeatherKitProvider | WeatherKit plus CoreLocation/geocoding | APPLE_NATIVE_CORRECT | Preserve entitlement and in-app provenance |
| 53 | Translation/follow-up | Translation executor | Apple Translation framework and system language assets | APPLE_NATIVE_CORRECT | Preserve explicit source/target and original-source context |
| 54 | Voice Memo recording | AudioRecorderController | AVAudioRecorder/AVAudioSession with durable app file | APPLE_NATIVE_CORRECT | Microphone permission; interruption/scene/recovery lifecycle |
| 55 | Open Voice Memos | Verified handoff/unsupported | Only a documented route if Apple exposes one | APPLE_HANDOFF_REQUIRED | Keep separate from UA recorder |
| 56 | Music recognition | Truthful blocked executor | ShazamKit SHSession/catalog capability | OWNER_OR_APPLE_ACTION_REQUIRED | Enable ShazamKit for App ID and regenerate profiles before implementation/claim |
| 57 | Apple Music | MusicKit executor | MusicKit | APPLE_NATIVE_CORRECT | Preserve authorization/subscription and physical PASS |
| 58 | Podcast search | Apple search adapter | Apple Search API plus exact Podcasts URL | APPLE_NATIVE_CORRECT | Bounded result and exact handoff |
| 59 | Third-party media | Verified provider handoff | Provider documented universal link/SDK/API | APPLE_HANDOFF_REQUIRED | Provider-specific, no guessed action |
| 60 | Arithmetic/percentage | LocalUtilityEngine | Deterministic local arithmetic | APPLE_NATIVE_CORRECT | Web unreachable |
| 61 | Fixed unit conversion | Local utility | Foundation Measurement/UnitConverter | APPLE_NATIVE_CORRECT | Deterministic, locale-aware |
| 62 | Local date/day/time | Local utility | Foundation Calendar/DateFormatter/TimeZone | APPLE_NATIVE_CORRECT | Device timezone authoritative |
| 63 | FX conversion | ECB/provider boundary | Apple has no FX API | EXTERNAL_PROVIDER_REQUIRED | Preserve ECB supported pairs/provenance; unsupported pair is provider-required |
| 64 | Battery | UIDevice monitor | UIDevice batteryLevel/state | APPLE_NATIVE_CORRECT | Honest rounding/state |
| 65 | Storage | Volume resource values | Public URL volume-capacity keys | APPLE_NATIVE_CORRECT | Keep local result |
| 66 | Flashlight | AVFoundation torch | AVCaptureDevice torch APIs | APPLE_NATIVE_CORRECT | Serialize hardware configuration |
| 67 | Global brightness | Local limitation | No supported persistent global controller | PUBLIC_API_UNAVAILABLE | Truthful local limitation |
| 68 | System volume | Local limitation | No supported arbitrary system-volume setter | PUBLIC_API_UNAVAILABLE | No private/MPVolumeView manipulation |
| 69 | Low Power Mode toggle | Local limitation | State is observable; no public toggle | PUBLIC_API_UNAVAILABLE | No web substitute |
| 70 | Wi-Fi/Bluetooth toggle/settings | Local limitation | App networking/BLE only; no public system toggle/deep page | PUBLIC_API_UNAVAILABLE | No private URL |
| 71 | Missed calls/Phone database | Local limitation | No public Phone call-history API | PUBLIC_API_UNAVAILABLE | No fabricated result |
| 72 | Find My people/devices | Compliant fallback | No general third-party Find My personal database API | PUBLIC_API_UNAVAILABLE | Documented handoff only if available |
| 73 | CurrentContext | Typed domain context | No Apple framework replaces UA context | APPLE_NATIVE_CORRECT | Preserve provenance, expiry, replace/supersede |
| 74 | Compound dependencies | Typed plan/output contract | No Apple arbitrary cross-domain orchestrator | APPLE_NATIVE_CORRECT | Concrete capabilities and verified outputs only |
| 75 | Result sharing | Activity presentation | UIActivityViewController | APPLE_NATIVE_CORRECT | User-selected destination |
| 76 | General/current information | Provider-neutral coordinator | No Apple general factual/current retrieval API | EXTERNAL_PROVIDER_REQUIRED | Real provider or explicit browser handoff with provenance |
| 77 | News | Provider boundary | No general public Apple News aggregation API | EXTERNAL_PROVIDER_REQUIRED | Licensed source, attribution/caching terms |
| 78 | Stocks | Provider boundary | No Apple market-data API | EXTERNAL_PROVIDER_REQUIRED | Licensed current provider and timestamp |
| 79 | Products/catalog/marketplace/retail/fashion | Commerce engines | No Apple retail catalog/availability/price API | EXTERNAL_PROVIDER_REQUIRED | Preserve constraints; no invented offers |
| 80 | Grocery/food delivery | Commerce boundary | MapKit discovery only; inventory/order external | EXTERNAL_PROVIDER_REQUIRED | Provider contract required |
| 81 | Restaurant reservation | Discovery/provider engine | MapKit discovery; booking external | EXTERNAL_PROVIDER_REQUIRED | Confirmed provider response and user confirmation |
| 82 | Taxi compare/book | Ride registry | Provider APIs/official handoffs | EXTERNAL_PROVIDER_REQUIRED | No invented quote |
| 83 | Hotels | Hotel boundary | MapKit discovery; availability/rates/bookings external | EXTERNAL_PROVIDER_REQUIRED | Provider required |
| 84 | Tickets/journey purchase | Ticket engine | Commercial inventory external | EXTERNAL_PROVIDER_REQUIRED | Verified offer and user confirmation |
| 85 | Parcel tracking | Parcel adapter | Carrier/provider API | EXTERNAL_PROVIDER_REQUIRED | Official status only |
| 86 | Local services/appointments | Service engine | MapKit discovery; availability/booking external | EXTERNAL_PROVIDER_REQUIRED | Split discovery from booking |
| 87 | Government/municipal services | Official handoff registry | Official government/provider integration | EXTERNAL_PROVIDER_REQUIRED | Exact official handoff only |
| 88 | Jobs marketplace | Jobs engine | No Apple jobs API | EXTERNAL_PROVIDER_REQUIRED | OUR JOBS/approved partners first |
| 89 | Loyalty/discounts/attribution/commissions | Partner ledgers | StoreKit does not establish external retail truth | EXTERNAL_PROVIDER_REQUIRED | Signed partner evidence; fail closed |
| 90 | Digital in-app purchase/entitlement | StoreKit state | StoreKit 2 | APPLE_NATIVE_CORRECT | Digital goods only; App Store confirmation |
| 91 | Sign in with Apple | AuthenticationServices | ASAuthorizationAppleIDProvider | APPLE_NATIVE_CORRECT | Preserve credential/revocation state |
| 92 | Cloud sync | CloudKit/iCloud/KVS | CloudKit plus concrete KVS/App Group | APPLE_NATIVE_CORRECT | Preserve scopes, migration and entitlements |
| 93 | Background jobs/proactive watch | BGTask/APNs paths | BGTaskScheduler plus APNs/local notifications | APPLE_NATIVE_CORRECT | Never promise exact background execution time |
| 94 | CarPlay | Policy-gated | Approved CarPlay category/templates and entitlement | OWNER_OR_APPLE_ACTION_REQUIRED | Only if canon maps to an approved category and Apple grants access |
| 95 | App Attest | DeviceCheck path | App Attest | APPLE_NATIVE_CORRECT | Preserve production server challenge verification |
| 96 | App Store Connect automation | Authenticated manual workflow | ASC API JWT or authenticated Transporter/Xcode | OWNER_OR_APPLE_ACTION_REQUIRED | Account key must be supplied securely; never commit p8 |

## Count reconciliation

- APPLE_NATIVE_CORRECT: 54
- APPLE_NATIVE_IMPROVEMENT: 4
- APPLE_NATIVE_REPLACEMENT_REQUIRED: 0
- APPLE_HANDOFF_REQUIRED: 11
- PUBLIC_API_UNAVAILABLE: 9
- EXTERNAL_PROVIDER_REQUIRED: 15
- OWNER_OR_APPLE_ACTION_REQUIRED: 3
- TOTAL_CANONICAL_FUNCTIONS_AUDITED: 96

## Fundamental findings

1. No global rewrite is justified. EventKit, Contacts, AlarmKit, PhotoKit,
   Vision/VisionKit, CoreLocation, MapKit, WeatherKit, Translation,
   AVFoundation, MessageUI, StoreKit, AuthenticationServices, CloudKit and App
   Group are broadly the correct executor boundaries.
2. The first Apple-native improvement is Contacts limited-access UX: preserve
   the bounded resolver and add the iOS 18 ContactAccessButton/contact access
   picker continuation.
3. App Intents/App Shortcuts are supplementary reachability, not a semantic
   router or permission bypass.
4. Semantic Photos needs confidence-bearing local Vision/Core ML evidence while
   PhotoKit remains asset authority.
5. Files, Notes, system Settings and system controls have hard public-API
   boundaries. Picker/system UI or truthful local limitation is correct.
6. ShazamKit remains App-ID/profile-bound. Commerce/current-data functions need
   real external providers, not another Apple framework.

## Ordered implementation plan

1. Contacts limited-access picker continuation without changing bounded
   resolution or telephone/messenger separation.
2. Semantic Photo classification using confidence-bearing local Vision/Core ML
   and fail-closed no-result.
3. App Intents/App Shortcuts only for already-green atomic executors.
4. Resume PB28-06 payload/reachability repairs on audited executors:
   Reminders/Timer/Alarm, Calendar, then remaining collisions.
5. Complete provider boundaries, full inventory reconciliation and gates.

## Official Apple evidence

- [Speech recognizer](https://developer.apple.com/documentation/speech/sfspeechrecognizer)
- [Speech contextual strings](https://developer.apple.com/documentation/speech/sfspeechrecognitionrequest/contextualstrings)
- [Contacts/off-main I/O](https://developer.apple.com/documentation/contacts/cncontactstore)
- [Contacts authorization and limited access](https://developer.apple.com/documentation/contacts/accessing-the-contact-store)
- [EventKit access](https://developer.apple.com/documentation/eventkit/accessing-the-event-store)
- [Message composer](https://developer.apple.com/documentation/messageui/mfmessagecomposeviewcontroller)
- [App-specific Settings](https://developer.apple.com/documentation/uikit/uiapplication/opensettingsurlstring)
- [Document picker](https://developer.apple.com/documentation/uikit/uidocumentpickerviewcontroller)
- [VisionKit](https://developer.apple.com/documentation/visionkit)
- [Data scanner](https://developer.apple.com/documentation/visionkit/datascannerviewcontroller)
- [Document camera](https://developer.apple.com/documentation/visionkit/vndocumentcameraviewcontroller)
- [MapKit local search](https://developer.apple.com/documentation/mapkit/mklocalsearch)
- [MapKit directions/travel time](https://developer.apple.com/documentation/mapkit/mkdirections)
- [Core Location](https://developer.apple.com/documentation/corelocation)
- [WeatherKit](https://developer.apple.com/documentation/weatherkit)
- [Translation](https://developer.apple.com/documentation/translation)
- [ShazamKit](https://developer.apple.com/documentation/shazamkit)
- [PhotoKit](https://developer.apple.com/documentation/photokit)
- [Vision OCR](https://developer.apple.com/documentation/vision/vnrecognizetextrequest)
- [App Intents](https://developer.apple.com/documentation/appintents)
- [StoreKit](https://developer.apple.com/documentation/storekit)
- [AuthenticationServices](https://developer.apple.com/documentation/authenticationservices)
- [CloudKit](https://developer.apple.com/documentation/cloudkit)
- [BackgroundTasks](https://developer.apple.com/documentation/backgroundtasks)
- [UserNotifications](https://developer.apple.com/documentation/usernotifications)
- [App Attest](https://developer.apple.com/documentation/devicecheck/establishing-your-app-s-integrity)
- [App Store Connect API](https://developer.apple.com/documentation/appstoreconnectapi)

## Verification meaning

This audit establishes architecture choices from source and official
documentation. It does not establish physical iPhone success. Changed and
physically failed families still require a new TestFlight physical retest after
implementation and the full completion gate.


## Final 96-function implementation reconciliation

Reconciliation checkpoint: post-PB28-08 automated verification. Every numbered row above remains authoritative and is accounted for exactly once:

- Rows 1–96: 96/96 reconciled; no canonical function omitted.
- APPLE_NATIVE_CORRECT (54): current public executor retained and protected by the full iOS/backend/canonical gates.
- APPLE_NATIVE_IMPROVEMENT (4; rows 5, 6, 12, 31): App Intents, App Shortcuts, iOS 18 limited Contacts continuation and fail-closed confidence-bearing semantic Photos are implemented and AUTOMATED GREEN.
- APPLE_HANDOFF_REQUIRED (11; rows 7, 8, 13–15, 18, 28, 39, 41, 55, 59): documented system/provider UI boundaries are implemented truthfully; no direct-execution claim.
- PUBLIC_API_UNAVAILABLE (9; rows 10, 24, 42, 67–72): terminal local limitations are preserved; no private API, fake success or accidental web fallback.
- EXTERNAL_PROVIDER_REQUIRED (15; rows 63, 76–89): provider-neutral typed boundaries, constraint preservation and truthful missing-provider behavior are implemented; ECB is live only for supported currencies. Commercial credentials/contracts remain external.
- OWNER_OR_APPLE_ACTION_REQUIRED (3; rows 56, 94, 96): ShazamKit App ID/profile enablement, policy-qualified CarPlay entitlement and App Store Connect API credentials remain exact owner/Apple boundaries. No secret or entitlement was fabricated.

Final automated evidence: full iOS 785/785 in 135 suites; backend 114/114; ZERO-OMISSION 2404/2404; AUDIO 147/147; PRIVACY 168/168; JOBS 97/97; LOYALTY 127/127; diagnostics 2/2; 1787 evidence requirements reconciled; Development and Production compiles PASS. An initial parallel iOS run was invalid for shared simulator-state/timing tests and also exposed real semantic regressions. The material source correction scopes fuzzy messenger recovery to CALL/MESSAGE roles, restores the canonical zero-padded clock contract, and accelerates unbound catalog search without stealing Files, Contacts, Podcasts, route-aware or taxi families. The serial full gate is authoritative.

AUTOMATED VERIFIED is not PHYSICAL IPHONE VERIFIED. All changed families still require owner physical retesting in a later TestFlight artifact.
