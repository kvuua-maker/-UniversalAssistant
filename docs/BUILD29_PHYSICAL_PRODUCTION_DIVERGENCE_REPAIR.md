# Build 29 physical-production divergence repair

Updated: 2026-09-09

## Full canonical completion gate (2026-09-09)

- The final parallel iOS gate exposed shared semantic gaps: percentage morphology was recognized but not executable; explicit result nouns were not typed as CurrentContext; SHOW/storefront clauses lost the Places dependency; Russian current-weather text collided with substring local-time recognition; German Notes and album media objects were incomplete. The shared structural parser/frame and deterministic engine were repaired without owner-phrase switches.
- Semantic Photos prioritizes classifier work while keeping a bounded background timeout. Weather command diagnostics accept a request-scoped sink while Release retains the shared production sink by default.
- App Intent and Quick Launch receive one `QuickLaunchRequestStore` dependency through `RunAssistantCommandIntent` → `ProductionAssistantComposition` → `AssistantViewModel`. Production defaults remain unchanged; isolated Release-root tests prove concurrent models cannot steal each other's command.
- CLOSED infrastructure/test approaches: parallel `xcodebuild` processes sharing one DerivedData `build.db`; a method selector that executed zero Swift Testing tests; cancellation-suppressing sleep as proof of end-of-speech completion; global QuickLaunch keys across concurrent Release-root models; narrow wall-clock thresholds below measured scheduler resumption delay.
- Final gates: iOS 829/829 in 149 suites; Development compile PASS; Production compile PASS; Backend 114/114; ZERO-OMISSION 2404/2404; AUDIO 147/147; PRIVACY 168/168; JOBS 97/97; LOYALTY 127/127; diagnostics 2/2; evidence reconciliation 1787/1787.
- `BUILD29_RELEASE_REACHABILITY_MATRIX.md` has exactly 96 rows and no `RELEASE_EVIDENCE_GAP`, `NOT_CONNECTED`, `IN_PROGRESS`, or `NOT_STARTED` status. Automated verification is not physical iPhone verification.

Next material operation: commit/push this green source checkpoint, verify repository synchronization and preserved recovery artifacts, then increment only build 29→30 and execute archive/sign/export/upload. Build 31 must not be created.

## Proven divergence

- Build 29 physical evidence overrides automated claims. Direct executor/provider unit tests were a CLOSED proof strategy because they bypassed the TestFlight composition root.
- Material repair direction: Release-configuration tests instantiate `ProductionAssistantComposition.makeModel`, submit natural Home input, traverse `LocalCommandEngine`/`CanonicalSemanticFrame`, the production router and the actual executor graph, and inject only the external Apple/provider side-effect boundary.
- The three intentional recovery/handoff artifacts remain untracked and untouched. Build 30 has not been created.

## Green Release-root checkpoints

- Contacts/calls/messages: Release root and bounded Contacts continuation covered; normal telephone and explicit messenger remain distinct.
- Photo/Files/OCR/share lifecycle: Release root, typed PhotoKit identity and context continuation covered.
- CoreLocation/MapKit: current coordinates/address/locality, Places/nearest, navigation, travel time, route-context waypoint and transit handoff covered by unseen Release-root tests.
- EventKit/AlarmKit, local utilities, Translation, Weather, Battery, Storage and voice memo lifecycle have production-composition evidence recorded in `BUILD29_RELEASE_REACHABILITY_MATRIX.md`.
- Media/providers: `ProductionAssistantComposition` now exposes only testable external seams for Apple Music and Apple Podcasts while retaining production defaults. Unseen Home commands reached Apple Music verified results, Apple Podcasts exact actions, and Spotify's documented system handoff.

## Media/provider verification

- Production Release-root + protected provider suites: 12/12 PASS.
- Development compile: PASS.
- Test-contract correction: expecting `.webHandoff` for Spotify was CLOSED after source tracing proved the shipped contract invokes `systemHandoffOpen` for `.system` handoffs and then returns UI to `.idle`. The test now verifies that real contract; production behavior was not changed to satisfy the erroneous assertion.

## System and FX checkpoint

- Added structural system-control OBJECT roles plus general enable/disable ACTION roles before intent selection; no owner phrase or device-specific success was patched.
- Release-root system/FX suite: 3/3 PASS; protected Apple system/quick-action/device routing suites: 18/18 PASS.
- Material lifecycle repair: `AssistantViewModel.presentFailure` now always leaves the processing state when publishing a terminal failure.
- Rows 63 and 66–72 now have Release evidence or exact public-iOS limitation evidence.

## CurrentContext and compound checkpoint

- The shipped composition now structurally recognizes inflected references to a previous answer before local utility selection; result copy/share consumes typed `CurrentContext`, not reparsed text.
- Removed the broad arithmetic `поділ`/`раздел` substring collision that captured natural Share commands; exact division forms remain supported and the protected chained-arithmetic regression stays green.
- Release-root system/context plus utility verification: 15/15 PASS. Protected CurrentContext, concrete multi-step, clipboard and replay/expiry suites: 31/31 PASS. Development compile: PASS.
- Rows 73–75 now have Release-root evidence. Internal planner identifiers remain non-executable.

## External-provider Release boundary

- Proven Release composition gap: ProductionAssistantComposition always constructed AssistantViewModel without a GenericUnknownRequestCoordinator, and externalProviderRequired jumped directly to generic web. The production composition root now accepts the provider-neutral coordinator while preserving production defaults; AssistantViewModel consults that boundary before an exact deliberate browser handoff.
- General show/query requests now reach the general-information provider path, while structurally open-ended search remains product/catalog discovery. This repairs the provider boundary without turning product selection into ambiguity.
- Reservation/ticket discovery no longer requests confirmation before a concrete provider result; confirmation remains required for an actual verified booking/purchase.
- Unseen Production-root provider verification plus protected semantic, interaction, retail and commerce suites: 64/64 PASS. Development compile: PASS.
- Rows 76–89 are EXTERNAL_PROVIDER_BOUNDARY_VERIFIED. No price, availability, quote, booking or account data is fabricated.

## Platform and owner boundaries

- Rows 90–96 were checked from Production target membership, signed entitlement configuration, shipped app lifecycle, platform/backend ownership and exact owner/Apple boundaries. These are platform subsystems rather than fabricated Home commands.
- StoreKit, Sign in with Apple, CloudKit, CarPlay policy and App Attest Production suites: 25/25 PASS. StoreKit products, production identity verification, live CloudKit devices/container and managed CarPlay access remain exact external boundaries.
- App Attest is connected to the shipped TestFlight diagnostic lifecycle. App Store Connect row is evidenced by the successful authenticated Build 29 upload; optional API-key automation remains an owner boundary.

## Remaining native Release-root checkpoint (2026-09-09)

- `Build29ReleaseRemainingNativeTests`: 4/4 PASS in Production with `ENABLE_TESTABILITY=YES`; actual `ProductionAssistantComposition` proved normalized final voice plus QuickLaunch convergence, timer/alarm AlarmKit routing and label retention, truthful global Clock limitation, Camera/QR/OCR/document-PDF presentations, Notes create and truthful Notes-database limitation, verified app opening and explicit messenger routing.
- Protected semantic/utilities/system/messaging/scanner/clipboard regressions: 76/76 PASS. Development compile: PASS.
- Material semantic repairs: broad SHOW/QUERY no longer suppresses a typed personal family; MEDIA ACTION/OBJECT/APP roles preserve clean content payload; inflected cardinal forms feed the shared deterministic number path. No exact physical utterance became a production switch.
- CLOSED: running Production tests without `ENABLE_TESTABILITY=YES`; expecting executable `.multiStep` lowering behavior from an individual concrete operation; treating Xcode worker interruption or an obsolete test expectation as a source defect.

## Confirmation continuation checkpoint (2026-09-09)

- Action-required confirmation is now executable through the shipped AssistantHomeView and CompactResultCard instead of being a dead renderer state. AssistantViewModel retains the typed StructuredCommand under request-generation ownership; cancel terminates locally, superseded confirmations are ignored, and confirm resumes the original concrete executor.
- Unseen Release-root emergency confirmation lifecycle: 1/1 PASS inside Build29ReleaseRemainingNativeTests; focused AssistantResultStateTests: 9/9 PASS; protected InteractionDecision/result-state/Calendar/emergency suites: 28/28 PASS. Development compile: PASS.
- The first protected run exposed two non-production issues: obsolete Notes→Files test expectation and exhausted temporary disk while finalizing xcresult. CLOSED: changing production Notes behavior or repeating tests without correcting those proven test/infrastructure causes.

## App Intent, limited Contacts, semantic Photos and Share Extension checkpoint (2026-09-09)

- ProductionAssistantComposition now exposes the image-loader and semantic-labeler boundaries while retaining PhotoKitAssetImageLoader and VisionPhotoSemanticLabeler as shipped defaults. This makes the exact Release graph testable without replacing the Apple implementation.
- Unseen Release-root gap suite: 4/4 PASS. Protected Contacts, PhotoKit/Vision, personal-source, Share Inbox and QuickLaunch suites: 37/37 PASS. Strong semantic evidence produced a typed PhotoKit action; weak confidence failed closed with no web.
- Rows 5, 12, 31 and 33 now have Release-root evidence.

## App Intent, limited Contacts, semantic Photos and Share Extension checkpoint (2026-09-09)

- ProductionAssistantComposition now exposes the image-loader and semantic-labeler boundaries while retaining PhotoKitAssetImageLoader and VisionPhotoSemanticLabeler as shipped defaults. This makes the exact Release graph testable without replacing the Apple implementation.
- Unseen Release-root gap suite: 4/4 PASS. Protected Contacts, PhotoKit/Vision, personal-source, Share Inbox and QuickLaunch suites: 37/37 PASS. Strong semantic evidence produced a typed PhotoKit action; weak confidence failed closed with no web.
- Rows 5, 12, 31 and 33 now have Release-root evidence.

## Public document and ContactsUI boundaries checkpoint (2026-09-09)

- Unseen Release-root suite: 2/2 PASS. A scoped Files request reached the system UIDocumentPicker with no web fallback; verified vCard scanner output reached the user-confirmed ContactsUI import presentation.
- Rows 13 and 27 now have exact public Apple handoff/reachability evidence.

## Shopping-list Release boundary checkpoint (2026-09-09)

- Root cause: the Production EventKit executor rejected every natural shopping-list create unless UI had already supplied `selected_list_id`, although `ReminderService` legitimately supports the system default reminders list.
- Material repair: create/query now use the explicit selected list when present and otherwise use the public EventKit default/all-incomplete-reminders boundary. Structural list+shopping roles make this personal intent authoritative before product/web discovery.
- Unseen Production-root shopping-list test PASS; direct EventKit default-list and explicit-list paths PASS; Development compile PASS.
- The wider LocalCommandEngine run exposed two unrelated pre-existing contract gaps (`Resume recording` and `.restaurantSearch` versus canonical `.placeSearch`). They remain explicit unfinished work and are not attributed to this green EventKit repair.

## Email compose Release boundary checkpoint (2026-09-09)

- Added a distinct public `MFMailComposeViewController` presentation for explicit email service requests; SMS/iMessage and third-party messenger paths remain separate.
- Unseen Production-root email request PASS; protected messaging suites 7/7 PASS; Development compile PASS.
- CLOSED test input containing a Calendar-domain noun for proving the isolated email boundary; that run correctly exposed a separate Calendar/message content collision rather than an email-executor failure.

## Notification Release lifecycle checkpoint (2026-09-09)

- Proven gap: production APNs entitlement and backend delivery existed, but the shipped app had no UserNotifications authorization/registration entry point.
- Added explicit settings-triggered authorization and `UIApplication.registerForRemoteNotifications`; no permission request occurs at launch. Denial and errors remain truthful.
- Release-root notification tests 2/2 PASS; contextual permission/voice diagnostics 5/5 PASS; Development compile PASS.
- Material diagnostics repair: a voice transcript ingress now retains its privacy-safe breadcrumbs when Home submission starts, even if a recovered/test session lacks the microphone-start marker.

## Always Location policy checkpoint (2026-09-09)

- The canonical shipped use cases are foreground location, nearby, routing and weather. Info.plist contains only `NSLocationWhenInUseUsageDescription`; source contains no `requestAlwaysAuthorization`, background location mode or background updates.
- Row 45 is an intentional least-privilege Apple policy boundary, not a missing permission. Foreground rows 43–44 already have Release-root evidence.

## PDF Release workflow checkpoint (2026-09-09)

- Row 29 now enters a typed PDF operation through the shipped `ProductionAssistantComposition`, canonical semantic frame, router and executor, then suspends at the legitimate public `UIDocumentPicker` boundary.
- Real selected PDF bytes are processed on-device for merge, split, rotate, compression, highlight and text redaction; outputs are written atomically, retained as typed document context and presented for Open/Share. Redaction fails closed if its target text is absent rather than inventing an edit.
- Unseen Production-root plus processor result: 8/8 PASS. A real two-document merge produced a valid two-page PDF. Development compile PASS.
- CLOSED: treating `OnDevicePDFProcessor` unit coverage or existence of a document picker as proof that natural Home input reaches a concrete PDF operation.

## Exact continuation

Run the full canonical gate set; all 96 reachability rows and the three recorded semantic contracts are reconciled.

## Final semantic-contract checkpoint (2026-09-09)

- Recorder pause/resume/stop is a typed lifecycle ACTION through the shipped Home composition. A token-boundary defect in `LocalUtilityEngine` treated the substring `sum` inside `resume` as arithmetic; English single-word utility signals now require complete lexical tokens.
- Restaurant/food proximity uses the one canonical structured Places route (`placeSearch`) rather than a competing legacy restaurant intent expectation.
- A leading send/share verb plus a verified SERVICE/CHANNEL role becomes `messageCompose`; Calendar-domain nouns inside the message payload no longer steal intent ownership.
- Production-root family suite 6/6 PASS; LocalCommandEngine/email suite 10/10 PASS; broader recorder/messaging regressions 22/22 PASS; Development compile PASS.
- CLOSED: substring matching of short English utility operators, and direct parser/controller tests as proof of shipped recorder lifecycle reachability.
