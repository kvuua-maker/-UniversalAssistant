# KILO REPAIR CHECKPOINT

Repair branch checkpoint. Read this first when resuming work. It records the
verified starting state, what was actually changed, how it was verified, and
what is still open. Nothing in this file substitutes for a physical test.

- Branch: `kilo/universalassistant-canonical-repair`
- START HEAD: `ef54b25a1c0632b3ce5cf13da3ccc174e490eeb9` (== `origin/experiment/ios27-speech-probe`)
- Merge-base with `origin/main`: `89b5a07d38a19c54b58a88285a5b9903314810db`
- `origin/main` and `origin/checkpoint/build59-pre-ios27-speech-probe`: untouched at `89b5a07`
- The experiment branch is strictly ahead of `main` (18 commits, no divergence).
  The repair branch therefore keeps the existing iOS 27 dictation work intact.

## Environment constraint that bounds every status below

This session runs on Linux with **no Swift toolchain**: no `swift`, `swiftc`,
`xcodebuild`, `xcrun`, no Xcode, no simulator, no Apple signing identity, no
CircleCI runner.

Therefore, in this checkpoint:

- No Swift file was compiled.
- No iOS or backend test suite was executed.
- No archive, export, IPA, codesign or TestFlight upload was produced.
- The CircleCI `ios27-dictation-probe-build64` job was **not** run and its
  branch/diff/build guards were **not** exercised.

Source-level correctness evidence only. Any "PASS" for compilation, archiving or
device behaviour would be fabricated.

## Cohort 1 — automotive domain ownership (production repair)

### Confirmed root cause at HEAD

`CanonicalDomainIntegrityPolicy.apply` decided automotive domain ownership from
`CanonicalAutomotiveEntityExtractor.brandAndModel`, which matched exactly three
marques via regex (BMW, Mercedes-Benz, Rolls-Royce). Consequences, all
reproducible from the source at `ef54b25`:

1. A purchase carrying a marque but no `офіційно` fell into the
   `product_catalog` branch — the generic commerce path that produced the
   historical Zara / Fozzy / Ukrposhta results.
2. A brandless vehicle purchase matched no marque at all, so it also reached
   `product_catalog` — the historical Prom.ua result for «Купити авто».
3. No open-world vehicle semantics existed, so a correct request for a sedan,
   crossover, EV or hybrid could not own the automotive domain.

Separately, `hasAmbiguousVehicleServiceGoal`
(`LanguageUnderstandingBlock.swift:217`) lists ordering roots
`["замов","закаж","book","order","request"]` and does **not** include `куп`.
That is why «Купити авто» never reached the existing typed vehicle-service
ambiguity and fell through to generic commerce instead.

### Repair

`UniversalAssistant/Core/CanonicalDomainRegistries.swift`

- Domain ownership now follows the meaning of the request, not a marque list:
  vehicle object semantics (авто / автомобіль / машина / body types /
  powertrain) plus ownership or dealer evidence.
- The brand/model is carried as data on `DomainEvidence`, never as the reason
  the domain was selected.
- The `product_catalog` automotive branch was removed entirely. An automotive
  request can no longer degrade into generic commerce.
- The pre-existing three verified marques remain trusted evidence on their own,
  so already verified marque-plus-official behaviour is preserved exactly.
- Guards keep the repair from displacing verified capabilities: public transport,
  parts/consumables/servicing, and any request already owned by `car_rental`,
  `vehicle_service` or `current_safety`.
- Open-world brand data is read as residual text only after vehicle semantics
  are established, with function words and vehicle vocabulary stripped and a
  length floor on the first token.

### Regressions added

`UniversalAssistantTests/LanguageUnderstandingBlockTests.swift`

- `automotiveDomainOwnershipFollowsRequestMeaningNotAMarqueList`
- `automotiveOwnershipIsOpenWorldOverVehicleObjectSemantics`
- `automotiveDomainOwnershipNeverDisplacesVerifiedCommerceOrCarRental`
- `automotiveDealerRequestsUseTheFreeGoogleMapsHandoff`

These assert the exact historical physical phrases plus unseen variants, and
they also assert that verified commerce and car-rental requests are *not*
captured. The pre-existing `build59AutomotiveEntitiesRemainOpenWorldPhysicalDealerQueries`
test is retained unchanged.

### How this was verified, and what that is worth

A faithful Python transcription of `CanonicalMorphology.forms(for:)` and the new
`domainEvidence` logic was executed over 31 cases: 3 preserved verified cases,
6 historical failure phrases, 6 open-world vehicle-type phrases, and 16
regression guards (sneakers, slippers, boots, bare vehicle ambiguity, car
rental, explicit rental, public transport, motor oil, consumables, tyres, car
service, car wash, spare parts, books, phone model token, verified marque plus
body type). All 31 passed.

That validates the **algorithm and its regression behaviour**. It is not a Swift
compile and not a substitute for one. Two defects were found and fixed this way
before committing: `vehiclePartsRoots` missed the Ukrainian «олія», and a
preposition («в») plus «салоні» leaked into the brand as `в салоні`.

## Cohort 2 — accepted-source content integrity

`docs/owner_sources/README_PROVENANCE.md` records that the `docs/` copies of the
Privacy, Loyalty, Audio and Live-Diagnostic addenda are one-line stubs: complete
ID sequences, lost requirement bodies. Reproducible SHA-256 values and worked
per-ID before/after proof are included. `docs/SPEC_SOURCE_OF_TRUTH.md` gained a
notice pointing auditors at the recovered text and at the IDs that remain
unverifiable.

`AUDIO-109…147` and `LIVE-DIAG-001…078` are marked `SOURCE_TEXT_REQUIRED`. The
owner instruction supplied Appendix A and B in full but ended Appendix C
mid-requirement at AUDIO-108 and contained no Appendix D body at all. No canon
was generated to fill either gap, and the historical stubs were left untouched
so their true hashes remain evidence.

## Still open — not attempted or not completed

- **Apple iOS 27 voice on iPhone SE 2 / iOS 27.** Requires the physical device
  and an Xcode 27 toolchain. Untouched. The contextual-bias question raised in
  the instruction (does `AnalysisContext.setContext` still bias the iOS 27 path
  via `ios27ApplicationContextualVocabulary`?) was **not** investigated.
- **Restaurant reservation.** `CanonicalDomainIntegrityPolicy` still rewrites a
  bare reservation into `placeSearch` (nearby restaurant in Maps). The instruction
  requires reservation to stay a booking flow. Confirmed present at HEAD, **not
  repaired** — changing it interacts with existing reservation/clarification
  tests that must be read before editing.
- **Route/address, Photos date, Photos semantic, apps/communications, safety**
  domains. Not audited to root cause in this session.
- **All provider integrations and their live/commercial verification.** Not
  audited. No provider adapter, credential, endpoint or partner status was
  touched or asserted.
- **Privacy, Loyalty, Audio, Jobs, Business, Finance, Diagnostics, Performance**
  audits. Not started. No data-flow map, capability registry entry or evidence
  matrix row was produced.
- No merge to `main`, no public release, no provider enrolment, no billing.

## Next step for the owner

One action, not a list: run the existing internal TestFlight candidate (or a
build from this branch once it can be compiled on Xcode 27) on the **iPhone SE 2
on iOS 27** and speak, in this order: «Відкрий Telegram», «Купити BMW сьомої
серії», «Купити авто». Record for each the Apple final transcript, the submitted
text, and the visible result. That single run is the only evidence that can
close either the voice cohort or the automotive cohort.
