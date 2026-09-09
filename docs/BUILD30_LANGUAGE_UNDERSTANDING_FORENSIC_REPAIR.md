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

## Exact continuation point

Add proposition-level indirect-intent and reusable Ukrainian/Russian morphology
evidence to `LanguageUnderstandingBlock`, then prove semantic-photo versus
latest-photo isolation and nearby ranking through `ProductionAssistantComposition`.
