# Post-Build-28 canonical repair ledger

Build 28 physical evidence date: 2026-09-08. Starting repository HEAD:
`8929153da4c58f5f3015461d4a1b733321d891fe`. Build 29 does not exist.

`AUTOMATED GREEN` never means physical iPhone success. Every repaired family
requires a later TestFlight physical retest.

## Stable status

| ID | Status | Evidence / next material action |
|---|---|---|
| PB28-01 VPS_DIAGNOSTICS | IN_PROGRESS | Read-only pinned-host VPS correlation completed for Build-28 sessions on 2026-09-08. Diagnostics intentionally omit transcript text. Completed sessions end at `13:32:36Z`; physical Contacts crashes have no completed session, so correlation is sequential/time-window only. |
| PB28-02 CONTACTS_CALLS_CRASH | AUTOMATED GREEN | Physical crash occurred after Home entry and before terminal diagnostic delivery. Removed retained cross-executor `CNContactStore`, confined store creation/use to one worker invocation, mapped Objective-C framework errors to a Sendable typed failure before crossing the continuation, made no-number calls terminal, and added privacy-safe authorization/query markers. Affected production-boundary suites: 33/33 PASS. Physical retest required. |
| PB28-03 REQUEST_TERMINATION_PHOTOS | NOT_STARTED | Inspect `Відкрий фото`/`Відкрий моє фото` semantic action and PhotoKit completion. VPS proves a `photoSearch` unavailable terminal in 5.3 s and another session spanning 77.8 s across Photo→OCR→later utility; it does not prove a 77.8 s PhotoKit query. Add per-request execution IDs/stages before attributing duration. |
| PB28-04 VOICE_CRASH_LIFECYCLE | NOT_STARTED | No current device crash report is connected to Xcode. Preserve prior generation/stale-callback repair; correlate VPS incomplete sessions and add durable crash breadcrumbs before further lifecycle changes. |
| PB28-05 ASR_ENTITY_NUMBERS | NOT_STARTED | Repair confidence-based installed-service/contact/entity recovery and general grouped-number structure; no phrase patches. |
| PB28-06 SEMANTIC_COMPOUND_FAMILIES | NOT_STARTED | Repair complete physical collision matrix and general typed dependency output contract. |
| PB28-07 PROVIDERS_CAPABILITIES | NOT_STARTED | Continue existing audits and only legitimate configured/autonomous integrations. |
| PB28-08 FULL_INVENTORY_GATES | NOT_STARTED | Reconcile original capability inventory and run all canonical gates only after family repairs. |
| PB28-09 NEXT_BUILD_GATE | NOT_STARTED | Build 29 forbidden until no independently resolvable implementation defect remains. |

## CLOSED approaches

| Family | CLOSED approach | Physical evidence | Material replacement |
|---|---|---|---|
| Contacts | Retain `CNContactStore` inside an `@unchecked Sendable` object and invoke it later on a separate DispatchQueue; transport arbitrary Objective-C framework errors through the continuation | Four distinct Contacts/Call commands terminated Build 28 before any completed diagnostic session | Same-invocation store ownership on the worker plus Sendable typed value/error crossing and explicit stage breadcrumbs |
| Diagnostics | Treat a missing completed diagnostic session as proof of a parser or executor result | Crash prevents the session from reaching idle/delivery | Use time-window correlation honestly and persist stage breadcrumbs before framework entry/after return |

## Exact continuation

After committing/pushing PB28-02, continue PB28-03 in
`CanonicalSemanticFrameAnalyzer`, `ProductionCanonicalCapabilityExecutor.photo`,
`AssistantViewModel.executeCanonicalCapability`, and PhotoKit production-boundary
tests: distinguish open Photos app/library from recent-photo selection, guarantee
one terminal state, and attach request-scoped stage markers without raw content.
