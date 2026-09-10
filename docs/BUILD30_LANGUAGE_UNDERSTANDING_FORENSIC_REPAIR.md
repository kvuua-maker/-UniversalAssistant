# Build 30 Language Understanding Forensic Repair

Status: **IN PROGRESS — BUILD 31 NOT CREATED**
Date: 2026-09-09
Starting repository HEAD: `8c9aa2c5e74fb1e31ae9dec7521750798ec44d3c`
Build under physical test: `0.1.0 (30)`

## Authority and scope

The original UniversalAssistant canonical specification remains authoritative. Build-30 physical observations are evidence of production failures, not phrases to encode. The repair stays inside the frozen pipeline:

`voice/text → LanguageUnderstandingBlock → CanonicalSemanticFrame → typed parameters/entities → CurrentContext/dependencies → canonical router → public Apple executor/configured provider → verified result → renderer/follow-up`.

Build 31 is forbidden until the complete canonical repair and gate are green. Automated evidence is not physical iPhone evidence.

## Authoritative physical evidence

| Family | Build-30 observation | Current status |
|---|---|---|
| Contacts / normal call | Natural contact search and call close/crash the app | `IN_PROGRESS`; requires production crash evidence and root repair |
| ASR / entity recovery | Foreign app/service/brand entities are clipped or substituted and do not recover reliably | `IN_PROGRESS`; exact tokens are evidence classes, never aliases |
| Semantic Photos | Natural semantic search resolves the latest photo instead of searching by content | `IN_PROGRESS`; latest/ordinal and semantic search must remain distinct |
| Places / nearby grocery | Results are not consistently precise enough in proximity/category relevance | `IN_PROGRESS`; structured category + geodesic/travel relevance required |
| Protected simple paths | Spotify, Apple Music, Files and PDF remain physically useful | `PROTECTED`; must not regress |

## First proven production-diagnostic divergence

No authenticated session with payload build `30` is present in the SSH-only VPS store. The service journal does contain repeated authenticated diagnostic attempts on 2026-09-09, but their HTTP user agent identifies build `29`; they therefore cannot honestly be relabeled as Build-30 traces. Every observed `/v1/diagnostics` attempt terminated with HTTP 400 before storage. Representative request IDs include `43041E68-ADAD-44BA-89F7-79D42A428129` at `10:51:12Z`, `974365A8-74B1-4B01-AA65-688C3C13F46B` at `10:57:50Z`, and `780B75A6-5E71-4ADE-AC4C-3DF6FC27CF6B` at `15:35:50Z`.

The archived Build-30 source proves the same client/server contract drift existed in the Build-30 release:

- the client always starts a Home report with `home_request_started`;
- recovered pre-terminal reports use `feature=request` and `liveTestID=MS-800-RECOVERED-REQUEST`;
- the deployed server accepted only `feature=voice`, `MS-800-LIVE-VOICE-QA`, and an older marker allowlist;
- the client could retain up to 1,000 markers while the server accepted at most 250.

Consequently the server rejected the very request/crash breadcrumbs needed to locate the first semantic or crash stage. This is a diagnostics-contract defect, not proof of a Contacts, Speech, router or executor root cause. Rejected bodies are intentionally not logged, so raw transcript or personal content cannot be recovered from the journal.

### Material repair

- one shared server schema now accepts the current bounded voice and recovered-request session forms;
- all current privacy-safe lifecycle markers are explicitly allowlisted;
- the client caps delivery at 250 events while retaining the first 100 ingress markers and final 150 terminal markers, then renumbers them monotonically;
- transcript text, contacts, locations, photos, documents and arbitrary attributes remain forbidden.

### Verification

- `PhysicalDiagnosticsTests`: 6/6 PASS;
- `PhysicalDiagnosticDeliveryTests`: 12/12 PASS from finalized `.xcresult`;
- full backend suite: 115/115 PASS on the canonical macOS host;
- Development compile: PASS after clearing only task-owned temporary derived-data directories that had exhausted the system volume;
- the new tests cover current Home lifecycle, recovered crash sessions and preservation of ingress/terminal evidence under a busy request.

### VPS deployment evidence

The compatible schema is deployed to the existing owner-authorized VPS. A Production-only Linux build of `UniversalAssistantServer` completed successfully from source checkpoint `e597360db2015d3067c41731bb68daf8f4ecbe9f`. Its SHA-256 is `f2f23db0cc080a23d3f89717dbef7f30e917c467f48615b49abf3797e0e6d91d`.

Only `universalassistant-diagnostics.service` was stopped and restarted. The prior binary is preserved at `/mnt/HC_Volume_106589590/universalassistant-diagnostics/backups/pre-language-e597360-20260909/UniversalAssistantServer` with SHA-256 `176f044421c2a9596bac08b12f58ebfb82d5489e700d3da1d6130cba3f070510`. Stored diagnostics and App Attest registration data were not modified. The service is active and `GET /health` returned `{"status":"healthy","version":"v1"}` after deployment.

The unchanged Linux `swift test` path is CLOSED as a deployment gate because two pre-existing test-only files are not portable to Linux (`FoundationNetworking` availability and Linux `TimeInterval` inference); this does not affect the Production server product, and the full canonical backend suite is green on macOS. The materially different Production-only release build is the deployed artifact.

## CLOSED approaches

| Family | CLOSED approach | Evidence | Material replacement |
|---|---|---|---|
| Production diagnostics | Treat absence of a stored session as evidence that the request never reached a client stage | The VPS journal shows diagnostic POST attempts rejected by schema before storage | Verify client/server schema parity, retain bounded ingress and terminal breadcrumbs, and distinguish missing evidence from product causation |
| Language semantics | Keyword/stem/regex/alias routing as the top-level semantic authority | Repeated Build-27/28/29/30 physical failures despite broad automated suites | New authoritative structured language-understanding block with evidence-bearing normalization, constrained recovery, full-frame semantics and confidence policy |
| Entity recovery | Add exact noisy transcript → entity substitutions | Real ASR corruption varies by utterance, language, context and device | Role-scoped candidate domains plus phonetic/transliteration/edit/split-merge evidence and confidence margin |
| Test architecture | Direct parser/executor or injected mock PASS as proof of TestFlight reachability | Large green suites repeatedly diverged from physical behavior | Release-configuration E2E through `ProductionAssistantComposition`, with mocks only at unavoidable side-effect boundaries |

## Planned authoritative language block

1. Request-scoped Apple Speech enrichment using only APIs available on the target OS, bounded contextual vocabulary, alternatives and segment confidence.
2. Unicode/token normalization that preserves original and normalized forms.
3. mixed Ukrainian/Russian/Latin language evidence without forcing the entire command to one language.
4. reusable morphology for command roles, entities, temporal and numeric units.
5. role-scoped phonetic/transliteration/edit/split-merge recovery with candidate provenance and confidence margin.
6. shared structured numbers and temporal roles before capability selection.
7. whole-command `CanonicalSemanticFrame` with confidence evidence.
8. indirect/proposition-level intent inference.
9. optional typed AI semantic fallback only where the original canon permits it; never direct privileged execution.
10. explicit execute/clarify/fail-closed policy; protected local/system/personal intent never falls into generic web.

## Authoritative Release semantic entry checkpoint

`LanguageUnderstandingBlock` is now the single `CommandParsing` instance created by
`ProductionAssistantComposition`. The identical instance is injected into
`AssistantViewModel`, `ProductionCanonicalCapabilityExecutor`,
`ProductionMultiStepCoordinator`, and `DeterministicExecutionPlanBuilder`.
`LocalCommandEngine` remains only a compatibility candidate generator inside the
new block; it no longer owns the shipped composition root or independently
reparses compound steps.

The block currently provides Unicode compatibility normalization, punctuation and
apostrophe normalization, the shared structured-number normalizer,
NaturalLanguage language hypotheses, structural-frame-first selection,
role-scoped verified-app recovery, evidence-bearing
folded/transliteration/phonetic/morphology similarity, confidence margin, and
fail-closed isolation for recognized system/local/personal roles. A general
structural distinction keeps timer/alarm `set` actions intact while treating an
object-free `start/launch` action as an application candidate.

Verification:

- new focused language and shipped Release-root suites: 9/9 PASS;
- affected semantic frame, entity, structured number, local utility, Contacts,
  Photos/Files and Release-root regressions: 35/35 PASS;
- Development compile: PASS;
- `git diff --check`: PASS.

Status is **AUTOMATED GREEN FOR THIS CHECKPOINT — PHYSICAL IPHONE RETEST
REQUIRED**. It does not close Speech enrichment, general service/contact/catalog
recovery, indirect semantics, physical Contacts crash, semantic Photos, Places,
or the full 96-function revalidation.

## Exact continuation point

Extend the authoritative language block with distinct, verified candidate domains
for SERVICE/CHANNEL, authorized CONTACT, and configured CATALOG/BRAND/PRODUCT
entities. Resolution must remain role-scoped and evidence-bearing: unique strong
candidate becomes a typed entity, close candidates clarify, and weak candidates
fail closed without generic-web substitution.

## Apple Speech enrichment checkpoint

The production `VoiceInputController` now configures every recognition request
with a bounded, deduplicated contextual vocabulary. Request-scoped candidates
have priority, followed by canonical function/service/application vocabulary, so
the public Speech framework's 100-entry boundary cannot evict the current
utterance's relevant entities. Entries longer than two words are excluded from
this bounded hint surface. Product/brand examples from physical testing are not
hardcoded.

`SFSpeechRecognitionResult.transcriptions`, per-segment `confidence`, and
`alternativeSubstrings` are captured as `VoiceRecognitionEvidence`. The evidence
is one-shot and generation-owned in `AssistantViewModel`, then delivered to the
same authoritative `LanguageUnderstandingBlock` used by typed input. An
alternative transcription may be adopted only when it agrees with the primary
non-web typed intent family and safely completes a missing typed role; it cannot
manufacture a different privileged action. `requiresOnDeviceRecognition` is not
forced: it is enabled only when explicitly requested and supported by the active
recognizer.

Privacy-safe diagnostics retain only alternative counts and a confidence bucket,
never transcript or personal entity content.

Verification:

- focused Voice/Speech/language/Release-root suites: 29/29 PASS;
- Development arm64 simulator compile: PASS;
- the first dual-architecture compile attempt failed solely with `No space left on
  device`; its finalized activity log proved an infrastructure failure before a
  source diagnostic. Completed task-owned DerivedData was removed, and the
  materially different arm64 compile passed;
- `git diff --check`: PASS.

Status is **AUTOMATED GREEN FOR SPEECH ENRICHMENT — PHYSICAL IPHONE RETEST
REQUIRED**.

## Context-scoped service, contact and catalog entity checkpoint

The authoritative language block now separates `APP`, `SERVICE_CHANNEL`,
authorized `CONTACT`, and configured `CATALOG/BRAND/PRODUCT/RETAILER` candidate
domains. A service is considered only after a communication frame and explicit
channel scope; an ordinary person's name therefore cannot silently select a
messenger. A unique high-confidence result becomes a typed entity, close
candidates produce a role-labelled clarification, and weak evidence remains
unresolved without generic-web substitution. A stronger resolution for one role
supersedes only an earlier ambiguity for that same role.

Phonetic evidence now handles generally clipped final syllables inside an
already-constrained domain, while the existing minimum score and runner-up margin
remain mandatory. Product/catalog recovery consumes only candidates supplied by
the configured registry/provider boundary. A verified catalog entity plus typed
commerce constraints can promote an otherwise unresolved sentence to a
provider-neutral product request; an unknown name cannot manufacture a brand or
commerce intent.

The production Speech contextual vocabulary now also receives a bounded list of
display names fetched from the currently authorized Contacts domain. Denied,
restricted and not-determined states disclose nothing. The same bounded domain is
used after the public Contacts exact-name predicate misses an inflected/noisy
name. Limited access is treated as an accessible subset, not an empty address
book. The resolver remains generation-owned and timeout-bounded.

Verification:

- focused language/contact/entity suites: 27/27 PASS;
- protected Contacts/Calls/messaging/semantic/Release-root suites: 61/61 PASS;
- Development arm64 simulator compile: PASS;
- `git diff --check`: PASS.

Status is **AUTOMATED GREEN FOR THIS ENTITY-DOMAIN CHECKPOINT — PHYSICAL IPHONE
RETEST REQUIRED**. Build-30 crash causation remains unproven because its diagnostic
payloads were rejected before storage; this checkpoint does not relabel that
missing evidence.

## Proposition, Places and semantic Photos checkpoint

`CanonicalPropositionAnalyzer` adds proposition-level evidence for natural
need/desire statements. It selects a capability only from a compatible set of
modality, activity, destination/content and proximity roles. A lone keyword is
never sufficient, and an inferred proposition cannot override an already typed
system or personal capability. The first Release-root run exposed two separate
legacy-precedence defects: inherited clarification survived a stronger complete
proposition, and application recovery could steal a concrete SETTINGS intent.
Both precedence mechanisms were corrected structurally rather than with phrase
exceptions.

Nearby requests now carry a typed `near_current_location` role to the production
MapKit boundary. MapKit's search region remains a provider hint, so the executor
also applies geodesic nearest-first ordering and a local five-kilometre cutoff for
an explicit nearby request. The first Release-root assertion caught the former
far-first behavior and is preserved as regression evidence.

Recent/ordinal PhotoKit selection and semantic Photos are now explicitly typed as
`photo_query_kind=recent|semantic`. Content-bearing OPEN/SHOW requests retain a
structurally extracted subject and use confidence-bearing Vision classification;
they cannot degrade to the latest private asset. Low-confidence classification and
an empty malformed semantic query fail inside the Photos family without web.
Generic photo requests and latest/ordinal PhotoKit behavior remain protected.

Verification:

- proposition and MapKit Release-root suites after the distance repair: 17/17 PASS;
- combined language, semantic frame, PhotoKit/Vision, Files collision,
  CurrentContext and Release-root MapKit suites: 47/47 PASS;
- Development compile: PASS;
- `git diff --check`: PASS.

Status is **AUTOMATED GREEN FOR THIS CHECKPOINT — PHYSICAL IPHONE RETEST
REQUIRED**.

## Morphology and crash-evidence checkpoint

`CanonicalMorphology` now supplies bounded productive inflection evidence for
Ukrainian, Russian and embedded Latin tokens. It retains the normalized surface
token and emits candidate forms rather than claiming a dictionary lemma. This is
important because the current SDK reports `Language`, `Script` and `TokenType`
tag schemes for `uk` and `ru`, but does not report `Lemma`; the implementation
therefore does not pretend Apple supplies a lemmatizer for these languages.

`LanguageUnderstandingBlock`, `CanonicalSemanticFrameAnalyzer` and
`CanonicalPropositionAnalyzer` consume the same form set. Lexical surface tokens
remain first-class, while derived forms are additional structural evidence only;
they cannot independently manufacture a capability. The old single-suffix
shortcut is removed. No contact, city, brand, service or physical test phrase is
encoded in this module.

Verification:

- focused language, frame, normalized-voice and shipped Release-root suites:
  44/44 logical tests PASS (57 parameterized executions), 0 failed, 0 skipped;
- finalized result bundle:
  `/tmp/ua-build31-morphology-dd/Logs/Test/Test-UniversalAssistant-2026.09.10_00-39-35-+0200.xcresult`;
- Development simulator compile: PASS;
- `git diff --check`: PASS.

The available Mac/Xcode locations contain no UniversalAssistant `.ips` or
`.crash` report for the Build-30 Contacts close event, and no physical iPhone is
currently attached to Xcode. The shipped app and production configuration do
contain `NSContactsUsageDescription`; its absence is therefore not a supported
crash theory. Since the Build-30 VPS payloads were rejected before storage, the
exact physical crash cause remains **UNPROVEN**, not silently reclassified as
fixed. The repaired diagnostic contract is deployed to capture the first wrong
stage on the next physical run.

Status is **AUTOMATED GREEN FOR MORPHOLOGY — PHYSICAL IPHONE RETEST REQUIRED**.

## Contacts framework and typed message-payload checkpoint

A serialized integration test now creates a test-owned contact through public
`CNContactStore` in the selected simulator, then instantiates the shipped
`ProductionAssistantComposition` with its default `LocalContactResolver` and
`SystemContactStoreQuery`. It verifies a natural normal-call request reaches an
intercepted `tel:` boundary rather than a messenger, and a natural message request
reaches the MessageUI presentation with the phone number resolved from the real
Contacts database. Only the test-created contact is deleted in cleanup.

The first runtime execution reached Contacts and both canonical actions without a
crash, but exposed a separate first wrong stage: `CanonicalSemanticFrame` retained
the recipient while dropping message content, so MessageUI received `body=nil`.
`CanonicalMessageRoleAnalyzer` now implements a structural recipient/content/
service grammar. It handles message-object position, colon, complement and topical
content boundaries without encoding a person, service or owner phrase. The resulting
typed `message_body` travels through the existing canonical executor.

Verification:

- framework Contacts + language/message-role suites: 19/19 PASS;
- protected Contacts lifecycle, normal-call/messenger, MessageUI and shipped
  Release-composition regressions: 26/26 PASS;
- Development simulator compile: PASS;
- `git diff --check`: PASS.

The Simulator evidence proves the public framework path and current shipped
composition terminate without a crash for this test-owned record. It does not
identify the unavailable Build-30 physical crash cause and therefore remains
**AUTOMATED GREEN — PHYSICAL IPHONE RETEST REQUIRED**.

## Typed temporal, numeric morphology and arithmetic-structure checkpoint

`CanonicalTemporalAnalyzer` now emits typed duration, relative-deadline, calendar-day, weekday, absolute-date, clock-time and date-time roles with confidence/evidence and an explicit ambiguity state. `NaturalDateTimeResolver`, EventKit extraction and multi-step lowering consume those typed entities before any compatibility text parse. Timer, alarm, Calendar and Reminder commands with an incomplete or incompatible temporal contract now terminate in local clarification instead of generic web.

`CanonicalArithmeticExpressionAnalyzer` adds a typed ordered-operation contract. Strong arithmetic structure outranks the former SHARE collision for division imperatives, while Calendar dates containing slash separators no longer become arithmetic. Prefix operators require a valid operand connector, chained operations consume the prior typed result, and `SpokenCardinalNormalizer` now covers a bounded class of Ukrainian/Russian case-inflected cardinals.

CLOSED approaches and material evidence:

- infix-only arithmetic parsing was disproved by an unseen operator-first chained command;
- treating any two numeric tokens following an add-like verb as arithmetic was disproved by Calendar plus clock time; prefix arithmetic now requires a structural operand connector;
- the first new Release-root execution reached the local executor but returned 12 rather than 17, proving an inflected-cardinal normalization gap; the repair covers the linguistic number-form class rather than the example.

Verification:

- full affected temporal, EventKit, AlarmKit, semantic-frame, language and local-utility suites: 76/76 logical tests PASS (95 parameterized executions), 0 failed, 0 skipped;
- finalized result bundle: `/tmp/ua-build31-temporal-final-dd/Logs/Test/Test-UniversalAssistant-2026.09.10_02-09-00-+0200.xcresult`;
- unseen shipped `ProductionAssistantComposition` arithmetic continuation returns 17 through the local deterministic renderer and never reaches web;
- Development simulator compile: PASS;
- `git diff --check`: PASS.

Status is **AUTOMATED GREEN FOR THIS CHECKPOINT — PHYSICAL IPHONE RETEST REQUIRED**.

## Confidence, ambiguity and protected-domain fail-closed checkpoint

`ContextScopedEntityResolver` now applies its configured confidence margin to
the complete ambiguity set. A weak single candidate is no longer presented as
a fabricated one-choice ambiguity: only two or more plausible candidates can
produce a choice list; otherwise resolution remains explicitly unresolved.

`LanguageUnderstandingBlock` records bounded confidence, runner-up margin,
mechanism and terminal resolution metadata for application, service/channel
and catalog domains. An unverified application target emitted by the legacy
compatibility parser is removed before the canonical domain decision. A
verified unique candidate restores the typed application identifier, a close
pair renders concise choices, and weak evidence remains a local clarification
without a generic-web handoff. `ProductionAssistantComposition` accepts an
injectable language block for boundary tests while its shipped default remains
the same single authoritative instance shared by Home and the canonical
executor graph.

CLOSED approach and evidence:

- the prior test expectation selected `telegrm` while deliberately injecting a
  second nearly identical Telegram candidate. The new margin policy correctly
  classified that domain as ambiguous. Automatic selection in a demonstrably
  close domain is CLOSED; high-confidence recovery is now asserted only in a
  unique verified domain, while the close-domain case must clarify.
- preserving the legacy parser raw application target after canonical
  unresolved evidence was disproved by the shipped Release-root test. That
  compatibility precedence is CLOSED; only a verified typed application entity
  may survive the authoritative boundary.

Verification:

- focused language, Release-root, device-router and production-composition
  confidence suites: 27/27 PASS, 0 failed, 0 skipped;
- finalized result bundle:
  `/tmp/ua-build31-confidence-dd/Logs/Test/Test-UniversalAssistant-2026.09.10_02-32-14-+0200.xcresult`;
- protected entity, Contacts/Calls, messaging and shipped Release-root
  regressions: 39/39 PASS, 0 failed, 0 skipped;
- finalized regression bundle:
  `/tmp/ua-build31-confidence-regression-dd/Logs/Test/Test-UniversalAssistant-2026.09.10_02-33-56-+0200.xcresult`;
- Development simulator compile: PASS;
- `git diff --check`: PASS.

Status is **AUTOMATED GREEN FOR CONFIDENCE/AMBIGUITY — PHYSICAL IPHONE RETEST REQUIRED**.

## Generated noisy-ASR, mixed-script and token-boundary checkpoint

Generated language tests now vary token boundaries and scripts inside already
verified APP, SERVICE_CHANNEL and CATALOG domains. Whitespace split/merge is
normalized before candidate scoring; Cyrillic/Latin transliteration remains
candidate-domain constrained; Speech alternatives may improve only the same
typed intent family and cannot substitute an unrelated timer/device command.
The shipped `ProductionAssistantComposition` also verifies split Spotify and
YouTube entities reach their exact legitimate application handoffs and never
a generic-web result.

The first run did not reach assertions: Xcode failed while emitting
`Darwin.pcm` with `No space left on device` (119 MiB free). Production source
was not changed for that infrastructure failure. No Xcode/XCTest process was
active; only obsolete task-owned DerivedData directories were removed from
`/tmp`, restoring 5.7 GiB. One rerun in the established DerivedData then
completed normally.

Verification:

- generated normalization, mixed-language/entity, Speech-alternative and
  shipped Release-root suites: 25/25 PASS, 0 failed, 0 skipped;
- finalized result bundle:
  `/tmp/ua-build31-confidence-dd/Logs/Test/Test-UniversalAssistant-2026.09.10_02-48-48-+0200.xcresult`;
- `git diff --check`: PASS.

Status is **AUTOMATED GREEN FOR GENERATED LANGUAGE VARIATION — PHYSICAL IPHONE RETEST REQUIRED**.

## Authoritative Release-root revalidation checkpoint

The 96-row inventory now uses the authoritative `LanguageUnderstandingBlock`
for every natural-language entry assertion in the shipped Release composition
suite. Non-Home platform/account operations remain recorded as exact legitimate
Apple, backend or owner boundaries rather than being mislabeled as Home
commands.

The first complete run exposed two first-wrong-stage defects:

- parcel tracking and loyalty-benefit requests could lose their structured
  external-provider domain before the production provider boundary, producing
  clarification instead of a finite truthful result;
- an emergency-call confirmation preserved generation ownership correctly but
  the original request had no typed emergency telephone destination, so the
  confirmed continuation re-entered Contacts resolution instead of the
  legitimate telephone handoff.

Material repair:

- `CanonicalExternalProviderBoundaryAnalyzer` requires compatible ACTION and
  OBJECT evidence, emits a typed provider-neutral domain/query/confidence
  contract, and permits deliberate browser handoff only after the missing
  provider reports `external_provider_required`;
- `CanonicalEmergencyNumberPolicy` resolves and validates the locale-supported
  user-initiated emergency number before confirmation. The executor consumes
  that exact typed `phone_number`; it never reparses confirmation text or
  substitutes a hardcoded destination.

Verification:

- focused changed Release-root suites: 9/9 PASS;
- finalized result bundle:
  `/tmp/ua-build31-release-revalidation-dd/Logs/Test/Test-UniversalAssistant-2026.09.10_03-52-21-+0200.xcresult`;
- protected language/router/provider/call regressions: 91/91 PASS;
- finalized regression bundle:
  `/tmp/ua-build31-provider-emergency-regression-dd/Logs/Test/Test-UniversalAssistant-2026.09.10_03-57-07-+0200.xcresult`;
- complete shipped Release-root inventory suite: 42/42 PASS in 14 suites;
- finalized inventory bundle:
  `/tmp/ua-build31-provider-emergency-regression-dd/Logs/Test/Test-UniversalAssistant-2026.09.10_04-02-50-+0200.xcresult`;
- Development simulator compile: PASS;
- no Release-root test in `Build29ReleaseCompositionForensicsTests.swift`
  enters through `LocalCommandEngine` directly;
- `git diff --check`: PASS.

Status is **96/96 RELEASE REACHABILITY ACCOUNTED FOR — AUTOMATED VERIFIED;
PHYSICAL IPHONE RETEST REQUIRED**.

## Exact continuation point

Run the complete canonical gate set, validate the current diagnostic schema and
VPS delivery readiness without inventing the rejected historical Build-30
payloads, reconcile recovery-artifact locations factually, and create Build 31
only if every autonomous completion gate remains green.
