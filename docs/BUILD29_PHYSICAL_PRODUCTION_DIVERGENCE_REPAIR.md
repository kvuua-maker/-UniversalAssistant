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

## Exact continuation
