# Build 26 canonical repair checkpoint

- Baseline physical release: `aab4b308cf79a38626e29bf86cc4a46513f2402a` (0.1.0 Build 25).
- Latest green source checkpoint: `985e54bd0687cce6754e3bba8c90d0ec369cdca9` (`Rank explicit nearest place results by distance`).
- Build metadata remains 0.1.0 (25). Build 26 has not been created.
- Recovery artifacts remain untouched and untracked.

## Completed in this checkpoint

- Added injectable Contacts authorization, synchronous store-query, and bounded async query production boundaries.
- Moved synchronous Contacts framework queries onto a dedicated user-initiated queue.
- Added a 3-second local Contacts deadline, cancellation completion, and late-completion suppression.
- Added Home canonical-request generation ownership: a newer request cancels the previous capability task and stale completions cannot mutate UI.
- Development simulator compile passed.
- Contacts/Calls production-boundary and affected parser/capability suites passed: 21 tests in 5 suites.
- Contacts lifecycle tests directly cover unique, no-result, ambiguity, denied/restricted/failed authorization, 3-second production deadline, cancellation, stale completion, Home supersession, and spinner termination.
- Normal calls now resolve only to the public `tel:` handoff; explicit WhatsApp is separately parsed and resolves to `https://wa.me/`. Direct-number calls bypass Contacts.
- Added semantic convergence for latest/newest photo, personal calendar query, natural navigation, pharmacy/gas nearby search, and new-note variants; VoiceTextInputQualityTests passed 11 tests in 1 suite.
- Calendar authorization is injectable and now performs bounded 500 ms post-grant status refresh before returning to the pending EventKit operation; denied, restricted, write-only, and rejected grants fail truthfully. Calendar/EventKit suites passed 15 tests in 2 suites.
- Photos latest/newest intents now converge, request and immediately re-evaluate authorization, accept full or limited access, select exactly one newest accessible PhotoKit asset, and fail truthfully for denied or empty libraries.
- Removed the non-functional `ph://` path. Photo result actions now open a public PhotoKit-backed in-app sheet; semantic photo search is Photos-only and fails closed instead of returning unrelated Contacts/Files.
- Photos/voice/result affected suites passed 31 tests in 4 suites; Development compile passed.
- Files security-scoped metadata reads now run behind an injectable user-initiated async query boundary with a 3-second interactive deadline, cancellation completion, and late-result suppression. Files/Photos boundary suites passed 14 tests in 2 suites; Development compile passed.
- Voice recognition now creates the public `SFSpeechRecognitionTask` before audio capture starts, closing the first-buffer readiness race, and supplies bounded domain contextual vocabulary for mixed-language brands, QR/OCR, system nouns, and Ukrainian imperatives.
- Voice/audio suites passed 17 tests in 2 suites before the subsequent documented public device-action audit.
- Remaining SYSTEM-FIRST families now converge locally before web: public AVFoundation torch, UIDevice battery read, volume-capacity storage read, and UIPasteboard write execute through typed mechanisms; Wi-Fi page, Bluetooth toggle, Low Power Mode, system brightness/volume, missed calls, Calculator/Phone app opening, contacts-list and alarms-list requests return truthful public-platform limitations instead of Google. Injected production boundary plus semantic suites passed 19 tests in 2 suites; Development compile passed.
- Reminder date resolution now supports relative minute/second intervals such as `через 10 хвилин`; EventKit title sanitation removes command, recipient, relative-duration, and day-period residue. NaturalDateTime/EventKit/AlarmKit suites passed 21 tests across 3 suites.
- QR entity recovery now corrects bounded ASR variants (`Q Club`, `Q клуб`, `quad`) only inside scanner/recognition context; public VisionKit scanner, Vision OCR, and in-app camera presentation remain wired. OCR/QR/voice suites passed 29 tests in 3 suites.
- Explicit nearest-place requests now use stable physical-distance ordering (unknown distances last), while general discovery retains relevance ranking; pharmacy and fuel intents use structured MapKit categories. Places/navigation/route-aware/voice suites passed 26 tests in 4 suites.

## Exact continuation point

1. In `DeterministicExecutionPlanBuilder.typedPlan`, replace `.typedCommand` nodes with intent-derived concrete capabilities and remove the `.deterministicCompose` plan node; aggregation remains coordinator-owned. Update `ProductionStepOperationMap.operation` so any concrete step carrying `step.command` executes through `typedExecutor` before generic travel operations. Add top-level natural-input tests for Nike place→destination→navigation and product→current-source truthful fallback; assert no abstract IDs in plan, facts, warnings, or renderer.
2. Continue in master priority order: Places/navigation; multi-step lowering; CurrentContext/Share Extension; local utilities; Notes/clipboard audit; real configured information providers; production UI.
3. Persist the exactly 71-row B25 forensic matrix, capability inventory, voice evidence, and VPS correlation artifact.
4. Run all repository gates and checkpoint green source before incrementing to Build 26.

No B25 row is claimed physically fixed. All B25-01 through B25-71 remain in the authoritative acceptance matrix; confirmed Build-25 passes must be preserved.
