# General Unknown-Intent Discovery — Evidence Matrix

## Pre-implementation audit

| Capability | Status | Existing evidence | Gap |
| --- | --- | --- | --- |
| A Unknown detection | ALREADY_IMPLEMENTED | `LocalCommandEngine`, unknown/parser tests | Unknown currently stops at clarification |
| B Generic typed intent | MISSING | `StructuredCommand` is closed-enum capability routing | No extensible typed semantic request |
| C–E discovery/retrieval/extraction | PARTIAL | controlled web URL plus complete generic-retail pipeline | Retail-only query and Product/Offer normalization |
| F–G source/provenance/freshness/conflict | PARTIAL | verified fact and retail evidence models | No domain-neutral per-fact conflict resolution |
| H native generic rendering | PARTIAL | deterministic composer and typed cards | No generic discovered-entity card pipeline |
| I truthful action | PARTIAL | Action Graph and typed handoff | No generic action derivation contract |
| J bounded AI | ALREADY_IMPLEMENTED | one schema-validated bounded interpretation | Needs generic coordinator integration |
| K no-AI fallback | MISSING | unknown currently clarifies | Deterministic generic discovery not connected |
| L clarification | ALREADY_IMPLEMENTED | one clarify presentation pattern | Must occur only after generic attempt |
| M privacy minimization | PARTIAL | allowlisted context/telemetry | No generic query sanitizer |
| N consequential safety | ALREADY_IMPLEMENTED | command validator and Action Graph | Must be enforced by generic handoff |
| O partial failure | ALREADY_IMPLEMENTED | bounded provider fanout | Needs generic provider adoption |
| P cache identity/freshness | PARTIAL | request-keyed bounded caches | No generic semantic cache key |

Only PARTIAL/MISSING rows may add minimal reusable production code. The post-implementation matrix must name concrete files, behavioral tests and commit evidence; live search/provider execution belongs in `LIVE_VERIFICATION_QUEUE.json` after all local work is complete.


## Post-implementation evidence matrix

| Capability | Status | Production evidence | Behavioral evidence |
| --- | --- | --- | --- |
| A Unknown detection | VERIFIED_LOCAL | `LocalCommandEngine` precedence plus `GenericUnknownRequestCoordinator` | specialized capability wins; unknown request continues to discovery |
| B Generic typed intent | VERIFIED_LOCAL | extensible `GenericIntent` typed core and bounded metadata | role/location/budget/time/risk parsing |
| C–E discovery/retrieval/extraction | VERIFIED_LOCAL | `ConfiguredGenericWebDiscoveryProvider`, `RetailDiscoveryTransport`, `RetailPageRetrieving`, `GenericStructuredExtractor` | concrete request/response/retrieval test and non-retail JSON-LD entities |
| F–G provenance/freshness/conflict | VERIFIED_LOCAL | `GenericSourceEvidence`, domain-aware source scoring and freshness filter | authoritative conflict, stale, blocked, snippet and duplicate tests |
| H native rendering | VERIFIED_LOCAL | reused `DeterministicResultComposer` | native facts/actions without browser transcript |
| I truthful action | VERIFIED_LOCAL | generic informational result exposes only typed `.open` handoff | open-only and consequential fail-closed tests |
| J bounded AI | VERIFIED_LOCAL | one optional `GenericAIIntentResolver` attempt then deterministic execution | exactly one call and `aiInvocationCount == 1` |
| K no-AI fallback | VERIFIED_LOCAL | deterministic parser/provider/extractor/coordinator path | end-to-end unknown job request with zero AI calls |
| L clarification | VERIFIED_LOCAL | typed `ambiguous` error carries one useful question | exactly-one clarification behavior |
| M privacy minimization | VERIFIED_LOCAL | `GenericQuerySanitizer` allowlisted semantic query | sensitive metadata/token/email exclusion test |
| N consequential safety | VERIFIED_LOCAL | informational/open/view allowlist; unknown side effects fail closed | unsafe action behavioral test |
| O partial failure | VERIFIED_LOCAL | concurrent task-group provider fanout | partial useful result and all-provider failure tests |
| P cache identity/freshness | VERIFIED_LOCAL | encoded full validated intent plus domain freshness TTL | differing budget constraints produce distinct keys |

Evidence run (2026-09-03): 28 targeted tests passed; full iOS regression passed with 465 tests across 100 suites; backend regression passed with 92 tests across 25 suites. Ten golden unknown-intent journeys are production data in `GenericUnknownJourneyCatalog` and executable-test covered. Commit evidence: this atomic implementation/evidence commit.

Only a controlled live search endpoint and public-page execution remain live-only; they are recorded in `LIVE_VERIFICATION_QUEUE.json`. Global ZERO-OMISSION reconciliation resumes at MS-566+.
