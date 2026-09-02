# M12 Universal Personal Search Core

Requirements MS-956–976. Status: VERIFIED_LOCAL; live status remains inherited from each queued source integration.

`UniversalPersonalSearchEngine` accepts one natural request and deterministically selects it against available authorized local, connected-email and connected-service sources. `PersonalSearchSourceRouter` selects only plausible sources for record/appointment, document, email/ticket/invoice and photo queries. Selected independent sources execute concurrently and receive only the original minimal provider query plus a bounded limit.

Every result retains typed source, real source-object ID, exact open reference and local/live/cached/unknown freshness. A high-confidence OPEN/SHOW request returns one exact-open action; ambiguity returns at most three results. Provider failure preserves verified results from other sources and explicitly marks partial coverage without invented values.

Evidence: `UniversalPersonalSearchEngine.swift` and `UniversalPersonalSearchEngineTests.swift`. Four behavior tests cover the dentist-record flow with actual concurrency and source exclusion, Files + connected-email document provenance, truthful partial provider failure and the three-result ambiguity cap. Full regression passed on 2026-09-02: 264 iOS tests across 68 suites and 78 backend tests across 22 suites; canonical JSON and diff checks passed.
