# Build 26 canonical repair checkpoint

- Baseline physical release: `aab4b308cf79a38626e29bf86cc4a46513f2402a` (0.1.0 Build 25).
- Latest green source checkpoint: `8805ed4` (`Bound personal data requests and suppress stale results`).
- Build metadata remains 0.1.0 (25). Build 26 has not been created.
- Recovery artifacts remain untouched and untracked.

## Completed in this checkpoint

- Added injectable `ContactResolving` and `ContactQuerying` production boundaries.
- Moved synchronous Contacts framework queries onto a dedicated user-initiated queue.
- Added a 3-second local Contacts deadline, cancellation completion, and late-completion suppression.
- Added Home canonical-request generation ownership: a newer request cancels the previous capability task and stale completions cannot mutate UI.
- Development simulator compile passed.
- Affected Contacts/personal-search/canonical/context suites passed: 15 tests in 4 suites.

## Exact continuation point

1. Add deterministic direct tests for Contacts timeout, cancellation, late completion, denied/restricted authorization, ambiguity, and Home supersession/spinner termination.
2. Complete ordinary telephone versus explicit third-party-call routing and direct-number parsing.
3. Repair semantic equivalence and system/local routing families covering B25-02–B25-71 without phrase-specific production switches.
4. Continue in master priority order: voice/entity pipeline; Files bounded execution; multi-step lowering; CurrentContext; Photos/Places; local utilities; real configured information providers; production UI.
5. Persist the exactly 71-row B25 forensic matrix, capability inventory, voice evidence, and VPS correlation artifact.
6. Run all repository gates and checkpoint green source before incrementing to Build 26.

No B25 row is claimed physically fixed. All B25-01 through B25-71 remain in the authoritative acceptance matrix; confirmed Build-25 passes must be preserved.
