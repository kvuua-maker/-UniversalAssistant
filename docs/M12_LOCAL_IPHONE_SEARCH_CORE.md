# M12 Local iPhone Search Core

Requirements MS-871–878 and MS-895–905. Status: VERIFIED_LOCAL.

`LocaliPhoneSearchEngine` is a typed, offline, AI-free coordinator over permitted local repositories. Independent sources execute concurrently off the main actor. Results are filtered by hard date constraints, ranked reproducibly by relevance, exact-name match, source preference and recency, then capped at ten items; a single result is exposed only when confidence separation is sufficient. Permission failures are explicit and never generate synthetic matches.

`PrivacySafeLocalSearchIndex` supports incremental upsert and source-wide removal when permission is lost, and stores typed local references rather than backend payloads. Production Apple adapters for Contacts/EventKit, Photos, Files and Core Spotlight are tracked in their dedicated following blocks; this core does not claim their physical-device behavior.

Evidence: `UniversalAssistant/Search/LocaliPhoneSearchEngine.swift` and `UniversalAssistantTests/LocaliPhoneSearchEngineTests.swift`. Four behavioral tests verify actual concurrency, deterministic ordering, hard date filtering/bounded shortlist, truthful denial, and stale-reference removal. Full regression passed on 2026-09-02: 239 iOS tests across 61 suites and 78 backend tests across 22 suites.
