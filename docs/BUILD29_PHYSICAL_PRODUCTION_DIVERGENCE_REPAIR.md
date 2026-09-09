# Build 29 physical-production divergence repair

Updated: 2026-09-09

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

## Exact continuation

Reconcile the 3 remaining RELEASE_EVIDENCE_GAP rows (25, 29, 45), then reconcile the recorded LocalCommandEngine contract gaps and run the full canonical gate set.
