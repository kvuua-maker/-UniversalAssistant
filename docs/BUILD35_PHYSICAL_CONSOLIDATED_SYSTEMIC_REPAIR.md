# Build 35 — consolidated physical evidence and systemic repair

Status: Phases A-D complete. Systemic repair is implemented and automated verification is GREEN; physical verification has not been performed. Build 35 was not rebuilt or re-uploaded. Build 36 was not created.

## Evidence boundary

- Physical authority: TestFlight Build 35, iPhone12,8, iOS 26.6.2.
- Available Crashlytics snapshot contains one Build-35 non-fatal connectivity probe. Its mutable request keys correlate to generation 32 / request `5B94AAB7-C11F-41E7-B018-22A4DEBA4D34`, capability `photoSearch`, last PRE `PHOTOKIT_PRE`, last POST `SPEECH_START_POST`, terminal `ERROR`. This proves only a probable Photos boundary, not a confirmed crash root.
- No Build-35 fatal report or complete per-command terminal report was returned by the available Crashlytics snapshot. A later API read returned `403 SERVICE_DISABLED`; absent payloads are not treated as evidence.
- No local Apple Organizer `.crash`/`.ips` artifact was found. App Store Connect returned no diagnostic-signature resource for the Build-35 resource ID.
- ASan: 58/58 focused tests PASS, no memory violation.
- TSan (separate run): 58/58 focused tests PASS, no race report.
- Main Thread Checker plus Swift actor data-race checks: 58/58 focused tests PASS, no violation. An earlier x86_64/Firebase linker mismatch was a corrected invocation failure, not a product defect.
- MetricKit was not present as a complete Crashlytics side-car in physical Build 35. Existing `PhysicalMetricKitDiagnostics` now handles both `MXDiagnosticPayload` and `MXMetricPayload`, persists bounded/redacted JSON, and forwards one correlated report through the existing Crashlytics bridge. Physical MetricKit evidence requires a later build.

## Consolidated defect map

| Root cause | Affected families | Evidence | Required general repair |
|---|---|---|---|
| Speech capture readiness and endpoint ownership are coupled to an awaited contact/catalog vocabulary fetch; custom end-of-speech is driven by a fixed absolute RMS threshold and a partial-result timer. Quiet continuation or speech begun immediately after the tap can be missed before/after the recognized fragment. | Multiword speech, initial action tokens, Telegram/Viber/app names, addresses, proper nouns, timer/calendar/booking slots | Physical missing first/middle/final tokens; production `VoiceInputController.start` awaits vocabulary before installing the tap; `VoiceSpeechActivityTracker` uses fixed RMS 0.002; every partial arms local finalization | Bound vocabulary wait, cache/refresh it, guarantee capture-ready state before accepting speech, use adaptive activity evidence and a bounded quiet window, keep Apple final result authoritative, configure full-command dictation plus bounded canonical context |
| Bounded contextual vocabulary has no reserved capacity by entity class: request-scoped contacts/catalog can consume the 100-item Apple limit before canonical app/service vocabulary. | Proper apps/services and mixed-language names | Production ordering is `contacts + catalog + canonicalVocabulary`; Apple documents a 100-phrase limit | Reserve bounded capacity for canonical app/service/function vocabulary while retaining a bounded request-scoped slice; no entity-specific substitution |
| Contact resolution accepts a sufficiently high-scoring `CNContact` predicate subset before comparing against the complete privacy-authorized candidate domain. The phonetic score removes vowels, so short unrelated labels can look uniquely strong in a one-candidate subset. | Search/call/Messages/email/WhatsApp and Ukrainian inflections | Physical “мамі” selecting another contact; source early-return on predicate evidence; same resolver is shared downstream | Deduplicate predicate + accessible contacts, rank once across the whole authorized domain, prefer exact/morphology evidence, require safe margin, clarify/fail closed rather than pick a different person |
| Cyrillic normalization is inconsistent in message/entity helpers and email SERVICE vocabulary lacks productive adjective+noun forms. | Explicit Telegram/email routing, PERSON/SERVICE separation, email recipient prefill | `CanonicalMessageRoleAnalyzer` diacritic-folds Cyrillic; email candidates recognize only a narrow surface list; a leading send verb stays generic share when email service is missed | Reuse Cyrillic-safe normalization and morphology; recognize email as a service role from adjective/mail-noun morphology; remove the typed service phrase from recipient text; preserve explicit channel through continuation |
| Translation target-language clause is detected but a trailing target clause remains in `source_text`. | Translation | Physical output includes “in English”; `translationSource(in:)` strips only leading target clauses | Extract one typed target-language clause at either command boundary and remove that span from source text before execution |
| MapKit region is only a hint and `localServices` orders but does not radius-filter provider results. | Explicit car-rental/local-service location | Physical Kyiv request returned LAX; explicit location is resolved first, but returned places are not locally bounded | Enforce request radius against resolved explicit location before rendering/handoff; explicit command location remains authoritative |
| Semantic Photos uses unstructured detached work: timeout resumes the caller but does not cancel the image/classification group; per-asset high-quality network fetches may continue. | Semantic/content Photos, bounded lifecycle, resource pressure | Physical processing over 15 seconds; probable Crashlytics `PHOTOKIT_PRE` without POST; source detached task plus independent timeout completion | Use structured cancellation/deadline, cancel child image requests, bound concurrency/candidates and remote fetch behavior, guarantee exactly one terminal outcome |
| Device-storage semantics depend on narrow phrases; canonical storage object misses the productive “free/available + space” construction. | Storage/system-first | Physical storage requests went to web/clarification; storage executor exists and previously worked | Add compositional free/available + storage/space role detection before web fallback; keep local executor authoritative |
| Calendar/restaurant failures may be downstream consequences of lost Speech tokens rather than executor defects. Current typed tests already resolve the complete Calendar slots and one booking grammar. | Calendar, restaurant booking | Physical clarification vs current typed parser PASS for comparable structures | First repair Speech; extend unseen typed/voice-like slot tests. Change slot extraction only where those tests prove a remaining general gap; provider absence stays truthful |
| The contact framework query resumed a checked continuation from independent operation/timeout queues without an explicit happens-before edge for the shared completion payload. | Contacts, request cancellation and concurrency | Final TSan exposed a concrete race in `LocalContactResolver`; the same suite was clean before only because the timing window did not occur | Serialize operation, timeout and cancellation delivery through one result queue; resume the continuation only from that queue |
| Product/marketplace live execution is at a provider boundary, not a semantic success. AlarmKit, audio route picker, Files/PDF, weather/location, arithmetic, battery, timer/reminder and known app-open executors are protected. | Providers and protected families | Physical provider-required outcomes and physical PASS list | Preserve truthful provider state and working Apple executors; do not fabricate or rewrite them without new evidence |

## One coherent repair pass

1. Speech readiness, bounded context allocation, adaptive endpointing, and authoritative final transcript.
2. Whole-domain contact ranking and shared morphology-safe entity evidence.
3. Communication SERVICE/PERSON roles plus translation clause boundaries.
4. Explicit-location result bounds, structured Photos cancellation, and system-storage composition.
5. Calendar/restaurant unseen slot verification; only proven remaining gaps receive changes.
6. Preserve provider boundaries and all Build-35 physical PASS behavior.

## Verification checkpoint

### Implemented systemic mechanisms

- Speech capture starts without waiting on live contact/catalog vocabulary. Context is cached/prewarmed, request-bounded and reserves capacity for canonical app/service vocabulary. Endpointing uses adaptive noise-floor evidence and a 2400 ms continuation window; Apple final results remain authoritative.
- Contact resolution deduplicates and ranks the complete privacy-authorized candidate domain once, gives exact/morphology evidence priority and fails closed on an unsafe fuzzy margin. Its async operation/timeout/cancellation handoff is serialized through a single result queue.
- Communication retains PERSON and SERVICE/CHANNEL as distinct typed roles; explicit email/messenger service survives recipient cleanup and continuation. Translation removes the target-language clause from source text.
- Explicit requested place bounds local-service results by radius instead of accepting provider-default geography. Semantic Photos work is cancellable, concurrency-bounded and returns one bounded terminal result. Device free-space language reaches the local storage capability before web fallback.
- Calendar and restaurant supplied-slot commands were verified through the shipped production semantic root. Provider-dependent booking/product execution remains a truthful external boundary; no live result or booking success is fabricated.
- MetricKit extends the existing diagnostics side-car: diagnostic and metric payloads are availability-guarded, locally bounded/redacted/deduplicated and correlated into the existing Crashlytics channel. No Build-35 MetricKit physical evidence is claimed.

### Automated evidence

- Phase-C systemic target: 11/11 PASS — `/tmp/ua-build35-phasec-arm64-dd/Logs/Test/Test-UniversalAssistant-2026.09.11_19-40-05-+0200.xcresult`.
- Affected and protected families: 139/139 PASS — `/tmp/ua-build35-phasec-arm64-dd/Logs/Test/Test-UniversalAssistant-2026.09.11_19-44-52-+0200.xcresult`.
- Final Address Sanitizer: 58/58 PASS, no ASan finding — `/tmp/ua-build35-final-asan-dd/Logs/Test/Test-UniversalAssistant-2026.09.11_19-45-52-+0200.xcresult`.
- Final Thread Sanitizer after the serialized contact handoff repair: targeted 14/14 PASS and full relevant 58/58 PASS, no TSan finding — `/tmp/ua-build35-final-tsan-dd/Logs/Test/Test-UniversalAssistant-2026.09.11_20-18-43-+0200.xcresult` and `/tmp/ua-build35-final-tsan-dd/Logs/Test/Test-UniversalAssistant-2026.09.11_20-20-56-+0200.xcresult`.
- Main Thread Checker plus strict Swift actor checks: 58/58 PASS, no main-thread/actor/continuation violation — `/tmp/ua-build35-final-mainactor-dd/Logs/Test/Test-UniversalAssistant-2026.09.11_20-21-50-+0200.xcresult`.
- Shipped Production composition root: 46/46 PASS across all Build-29 release-root suites — `/tmp/ua-build35-final-mainactor-dd/Logs/Test/Test-UniversalAssistant-2026.09.11_20-26-45-+0200.xcresult`.
- Full iOS: 939/939 PASS across 158 suites, zero skipped — `/tmp/ua-build35-final-mainactor-dd/Logs/Test/Test-UniversalAssistant-2026.09.11_20-36-03-+0200.xcresult`. Swift Testing parallel width was set to one because concurrent test-created `AssistantViewModel` instances share the process-wide diagnostics singleton, unlike the single shipped Home composition root. A legacy PB28 assertion was corrected to exercise authoritative `LanguageUnderstandingBlock`, not the bounded legacy command helper.
- Production compile: PASS (`** BUILD SUCCEEDED **`) using the Production scheme and generic arm64 iOS destination. The first invocation failed only because its temporary DerivedData lacked the Crashlytics SPM script at the path required by the existing Xcode phase; restoring that temporary package checkout made the same source build pass.
- `git diff --check`: PASS before final checkpoint.

### Evidence limits and remaining boundaries

- Crashlytics remains enabled, but the available Firebase API snapshot did not supply a Build-35 fatal stack or complete command-by-command trace; no absent crash detail was invented. Physical Build-35 symptoms plus inspected production paths and automated production-root evidence define this repair.
- MetricKit cannot retroactively produce Build-35 data. Its first physical payload requires a later authorized verification build and normal Apple delivery latency.
- Commercial restaurant/product/marketplace providers remain `PROVIDER_REQUIRED` where credentials/contracts are absent. Alarm/audio/Files/provider mechanisms are not declared physically improved beyond the owner-reported Build-35 evidence.
- Automated GREEN is not physical iPhone GREEN. A separately authorized Build 36 is required to physically verify these repairs on iPhone12,8 / iOS 26.6.2.
