# Build 27 function repair ledger

Authoritative base: `b85822247ec39c577ea9c92460eb3dca8ab6473a` (0.1.0 Build 26).

Physical status is not assigned here. `GREEN` means source implementation is connected to the production path and applicable automated gates pass; owner iPhone retesting remains required.

## Stable execution status

| ID | Status |
|---|---|
| B27-00 | IN_PROGRESS |
| B27-01 | GREEN |
| B27-02 | GREEN |
| B27-03 | IN_PROGRESS |
| B27-04 | IN_PROGRESS |
| B27-05 | IN_PROGRESS |
| B27-06 | IN_PROGRESS |
| B27-07 | IN_PROGRESS |
| B27-08 | IN_PROGRESS |
| B27-09 | IN_PROGRESS |
| B27-10 | NOT_STARTED |
| B27-11 | NOT_STARTED |
| B27-12 | IN_PROGRESS |
| B27-13 | IN_PROGRESS |
| B27-14 | IN_PROGRESS |
| B27-14.01 | GREEN |
| B27-14.02 | GREEN |
| B27-14.03 | NOT_STARTED |
| B27-14.04 | NOT_STARTED |
| B27-14.05 | NOT_STARTED |
| B27-14.06 | NOT_STARTED |
| B27-14.07 | NOT_STARTED |
| B27-14.08 | NOT_STARTED |
| B27-14.09 | NOT_STARTED |
| B27-14.10 | NOT_STARTED |
| B27-14.11 | NOT_STARTED |
| B27-14.12 | NOT_STARTED |
| B27-14.13 | NOT_STARTED |
| B27-14.14 | NOT_STARTED |
| B27-14.15 | NOT_STARTED |
| B27-14.16 | NOT_STARTED |
| B27-14.17 | NOT_STARTED |
| B27-14.18 | NOT_STARTED |
| B27-14.19 | NOT_STARTED |
| B27-14.20 | EXTERNAL_PROVIDER_DEPENDENCY |
| B27-15 | IN_PROGRESS |
| B27-16 | IN_PROGRESS |
| B27-17 | IN_PROGRESS |
| B27-18 | IN_PROGRESS |
| B27-19 | NOT_STARTED |
| B27-20 | GREEN |
| B27-21 | NOT_STARTED |
| B27-22 | NOT_STARTED |
| B27-23 | GREEN |
| B27-24 | NOT_STARTED |
| B27-25 | IN_PROGRESS |

## CLOSED approaches

| Family | Attempted mechanism | Evidence | Why closed | Materially different mechanism |
|---|---|---|---|---|
| Contacts / Files | Per-provider three-second timeout plus injected source tests | Build 26 still hung on physical Contacts and Files commands | The stripped query lost its source kind, so universal personal search fanned out to Contacts, Photos, and Files before the timeout boundary could provide canonical behavior | Route `.contactLookup` directly to the bounded Contacts resolver and `.fileSearch` directly to the public security-scoped document picker |
| Semantic Photos | Broad accessible-asset matching | Build 26 returned unrelated latest assets and hung | Accessibility is not semantic relevance | Require bounded local analysis and fail closed when relevance is unproven |
| Voice QR/entities | Narrow hints and token substitutions | Build 26 still produced Q-club/verb corruption | Phrase hints did not repair capture/final reconciliation | Repair the public Speech lifecycle and confidence-aware structured entity recovery |
| System actions | Broad `.deviceAction` followed by unavailable/web fallback | Build 26 sent recognized device intents to Google or generic unavailable | Capability kind was not resolved before fallback | Typed public-capability registry with local truthful limitation and documented handoff |
| Multi-step | Injected coordinator tests | Build 26 leaked abstract planner identifiers physically | Test bypassed the full Home production boundary | Preserve concrete lowering and add Home-to-renderer production tests |

## Completed material repair: B27-14.01 / B27-14.02

Physical evidence: Files search and Contacts lookup could remain processing for tens of seconds or indefinitely. The production route stripped the source-bearing words and passed only names such as `PDF` or `Сашко` into `UniversalPersonalSearchEngine`. Source routing then had no Files/Contacts marker and selected every available personal source.

Material repair:
- `.contactLookup` now invokes the existing bounded `ContactResolving` production boundary directly.
- `.fileSearch` now presents the public security-scoped document picker directly; iOS has no public API for silently searching arbitrary Files providers.
- Existing normal-call routing remains `tel:` and explicit WhatsApp remains a separate `https://wa.me/` handoff.

Production-boundary regression: `ProductionPersonalRoutingBoundaryTests` proves Contacts and Files commands do not invoke an injected unrelated Photos source. Affected Contacts lifecycle, call routing, local-source, and Home result tests pass. Physical retest remains required.

