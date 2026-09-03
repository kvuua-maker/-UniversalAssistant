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
