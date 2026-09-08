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
| PB28-03 REQUEST_TERMINATION_PHOTOS | AUTOMATED GREEN | Open/show Photos requests now structurally select recent metadata instead of classifying action words; latest/penultimate, Open, Share and OCR use typed PhotoKit asset presentations. Authorization grant resumes the same command. Metadata lookup has a justified 3-second one-shot deadline; cancellation and late completion cannot publish a second result. Affected suites: 31/31 PASS. Physical retest required. |
| PB28-04 VOICE_CRASH_LIFECYCLE | AUTOMATED GREEN | No current device crash report is connected to Xcode, so exact physical crash causation remains unproven. Material preventive repair gives `AssistantViewModel` ownership of permission-suspending mic start tasks; repeated tap and scene transition cancel abandoned starts while existing controller generation guards suppress late authorization/Speech callbacks. Added interruption, scene and capture-stop breadcrumbs. Focused production lifecycle: 24/24 PASS; Development compile PASS. Physical retest required. |
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

## Completed material repair: PB28-03

First wrong stage: semantic framing converted generic Photo open/show wording into a semantic-classification query containing control words, while OCR/Share requests stopped at a preview card. Material repair: structural recent-asset selection, ordinal selection, typed Open/OCR/Share presentations, automatic in-app continuation after asset loading, and a one-shot 3-second metadata deadline. The deadline matches the established bounded local-personal query UX; it terminates the renderer while late framework completion is ignored. Empty, denied, limited, granted-during-command and timeout states have distinct terminal outcomes.

CLOSED test-environment approach: repeated launches on existing iOS 26.5 and 18.1 Simulator devices stalled at `waiting for workers to materialize`; changing only the runtime did not help. A fresh isolated simulator plus explicit boot/install restored execution. My Mac with signing disabled failed correctly with `No code signature found`; enabling signing was blocked by absent `.dev` provisioning profiles and was not used to mutate account state.

Verification: ApplePersonalSearchSourcesTests, ProductionContextContinuationTests, CanonicalSemanticFrameTests and CanonicalCapabilityExecutionTests: 31/31 PASS on iOS 26.5 Simulator. Development compile PASS.

## Completed material repair: PB28-04

Production root weakness: the UI did not own the permission-suspending microphone start `Task`; rapid re-entry or a scene transition invalidated controller callbacks but left abandoned Tasks alive. The view model now cancels and clears that Task on second tap and scene inactivity. Existing session-generation ownership and stale callback suppression remain authoritative. Privacy-safe markers now include interruption, scene transition and capture stop. No current `.ips` report is available, so this is AUTOMATED VERIFIED preventive lifecycle hardening, not a claim that the physical crash is fixed. Verification: VoiceInputSessionOwnershipTests, AudioRecorderControllerTests and AssistantResultStateTests, 24/24 PASS on isolated iOS 26.5 Simulator; Development compile PASS.

## Exact continuation

PB28-04 is AUTOMATED GREEN. Continue PB28-05 ASR_ENTITY_NUMBERS: inspect structured-number token composition and context-scoped app/service entity candidates, then replace split additive number fragments and low-confidence entity corruption without phrase-specific aliases.
