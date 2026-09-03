# M12 Photos, Files and Core Spotlight Core

Requirements MS-879–894 and applicable MS-905, MS-911–918. MS-879–912 and MS-918 are VERIFIED_LOCAL; only the physical executions MS-913–917 are READY_FOR_LIVE_VERIFICATION.

`PhotoKitLibrarySearch` uses the public read/write authorization state, distinguishes full, limited, not-determined, denied and unavailable access, and fetches only real accessible image assets. It supports hard creation-date ranges, exact album membership, coordinate/radius metadata filters and bounded newest-first results. It does not claim Photos private semantic/person indexes. `PhotoSemanticSearchEngine` instead performs bounded on-device Vision classification only over PhotoKit assets currently exposed by full/limited authorization, treats unreadable/unclassified assets as no match, and preserves the exact real PhotoKit local identifier.

`AuthorizedDocumentPicker` obtains document-provider URLs through the system picker. `AuthorizedFileSearchSource` searches only the supplied authorized set, balances security-scoped access, bounds output and returns the exact URL for system opening. It never scans or claims the global iPhone filesystem. `CoreSpotlightAssistantIndexer` indexes and removes only UniversalAssistant-owned typed result domains and does not query other apps' private Spotlight indexes.

Production configurations include a purpose-specific Photos usage description. Automated behavior verifies explicit-file isolation, exact open URL, authorization removal, typed photo metadata constraints, limited-library semantic matching and fail-closed denied/unreadable behavior. Physical limited/full Photos, provider picker, Spotlight surface and latency observations are recorded precisely in `LIVE_VERIFICATION_QUEUE.json` and `REAL_DEVICE_TEST_MATRIX.md`.

Evidence on 2026-09-02: the built application Info.plist contains `NSPhotoLibraryUsageDescription`; 242 iOS tests across 62 suites and 78 backend tests across 22 suites passed; canonical JSON and diff checks passed.
