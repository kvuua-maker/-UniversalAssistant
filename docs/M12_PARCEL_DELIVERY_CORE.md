# M12 Parcel Delivery Core

Requirements MS-1030–1037. Status: VERIFIED_LOCAL; real carrier-account execution is READY_FOR_LIVE_VERIFICATION.

## Production implementation

- `ParcelDeliveryEngine` validates explicit tracking identifiers and concurrently queries modular `ParcelDeliveryProvider` implementations. A provider failure produces an attributed partial result and never fabricated status, ETA or availability.
- `NovaPoshtaParcelProvider` implements the documented JSON request/response boundary for tracking and warehouse lookup. `OfficialParcelHTTPProvider` supplies bounded authenticated HTTP tracking/branch adapters; `ParcelProviderFactory` injects Nova Poshta API keys and Ukrposhta/Meest bearer credentials without repository persistence or logging.
- Every result distinguishes confirmed provider events, provider estimates and unknown values and retains carrier-scoped source evidence. Branch routes use exact verified coordinates.
- Parcel watches expire after 30 days. The backend `ProactiveWatchEngine` persists parcel rules and observations atomically, schedules deduplicable durable jobs after restart, and emits `.parcel` notifications only after a changed provider state.

## Official capability evidence

- Ukrposhta publishes API documentation and agreement/token access at `https://dev.ukrposhta.ua/documentation`; production credentials and a controlled shipment are external dependencies.
- Meest publishes OAuth-protected tracking and points contracts through its official Swagger at `https://mwl.meest.com/mwl/swagger-ui/index.html?configUrl=%2Fmwl%2Fv3%2Fapi-docs%2Fswagger-config` and an official tracking module at `https://international.meest.com/tracking-module/`.
- Additional carriers remain isolated behind `ParcelDeliveryProvider`; no provider-specific rules leak into result composition.

## Requirement-to-test evidence

- MS-1030, MS-1034–1036: `ParcelDeliveryEngineTests.providerFailureReturnsTruthfulPartialResult`, `invalidTrackingNumberNeverCallsProviders`, and adapter response parsing validate modular fan-out and verified-facts-only behavior.
- MS-1031–1033: request recorders assert Nova Poshta JSON method/body, bearer/query composition, nested response parsing, credential rejection, 401 and 429 mapping, and coordinate validation.
- MS-1037: `watchPlannerExpiresAndOnlyRecognizesMatchingChangedProviderEvidence`, exact navigation testing, and backend `parcelWatchPersistsAcrossRestartAndTriggersOnlyOnChangedProviderState` cover expiry, persistence, restart, durable scheduling and changed-state notification.

Verification on 2026-09-02: full iOS regression passed 290 tests across 73 suites; full backend regression passed 79 tests across 22 suites. Commit evidence is the atomic commit that contains this document and the referenced production/test files.
