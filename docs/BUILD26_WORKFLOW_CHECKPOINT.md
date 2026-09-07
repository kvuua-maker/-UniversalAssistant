# Build 26 canonical repair checkpoint

- Baseline physical release: `aab4b308cf79a38626e29bf86cc4a46513f2402a` (0.1.0 Build 25).
- Latest green source checkpoint: `c1234b140d369a2d48b071b4bac5285b3887dc93` (`Refresh Calendar authorization after grant`).
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

## Exact continuation point

1. Complete Photos permission/latest-photo presentation lifecycle: restrict latest intent to one newest accessible asset and replace non-functional `ph://` Link handling with a public PhotoKit-backed in-app presentation.
2. Complete Files bounded query cancellation/stale suppression.
3. Continue semantic equivalence and system/local routing families covering B25-02–B25-71 without phrase-specific production switches.
4. Continue in master priority order: voice/entity pipeline; Files bounded execution; multi-step lowering; CurrentContext; Photos/Places; local utilities; real configured information providers; production UI.
5. Persist the exactly 71-row B25 forensic matrix, capability inventory, voice evidence, and VPS correlation artifact.
6. Run all repository gates and checkpoint green source before incrementing to Build 26.

No B25 row is claimed physically fixed. All B25-01 through B25-71 remain in the authoritative acceptance matrix; confirmed Build-25 passes must be preserved.
