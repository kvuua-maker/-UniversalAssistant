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

## Exact continuation

Reconcile every remaining RELEASE_EVIDENCE_GAP across rows 1–75, then run the full canonical gate set.
