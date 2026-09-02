# Deterministic Multi-Step Coordination + Bounded AI Fallback Addendum

Status: canonical additive requirement accepted 2026-09-02. It augments Master Spec v13.2 and every previously accepted addendum; it does not reopen completed M0–M7 work.

## Deterministic core

UniversalAssistant is the primary command interpreter, coordinator, executor and result composer. AI is not the mandatory router, planner, scheduler, execution engine, or critical path. Known capabilities must produce a typed plan: resolved intent and constraints, required capabilities, dependencies, bounded parallel groups, hard constraints, soft preferences, completion criteria, verified results and deterministic composition. Existing routing, capability registries, providers and Swift concurrency must be reused.

Unambiguous commands use the shortest deterministic path with zero AI calls. Independent operations run concurrently with bounded concurrency, timeout, cancellation and honest partial failure; dependencies wait only for real prerequisites. A slow optional provider must not block a sufficient verified result.

Relative semantics are resolved in this order: explicit command constraint; relevant user preference; current task context; geography/currency/time/category context; documented category-specific default. Material residual ambiguity produces one minimal clarification, never a guess. Hard constraints exclude candidates; soft preferences deterministically and reproducibly rank eligible candidates.

The required travel acceptance flow resolves dates, Calendar return deadline, origin and candidates, then safely parallelizes Weather, Transport and Hotel/pricing. The return deadline is hard. AI calls equal zero.

## Facts and composition

Only verified module/provider results may supply prices, availability, weather, routes, duration, delivery, booking/marketplace state, Calendar/contact data or other live facts. Missing facts remain unknown/unavailable. Deterministic composition produces the primary answer, supporting facts, ranking, cards/list/map, actions, warnings and unknowns without AI for routine text, arithmetic, comparisons, prices, routes or formatting.

## Bounded AI fallback

AI is allowed only after deterministic processing leaves unresolved semantic interpretation, non-representable complex language, or synthesis that the deterministic composer genuinely cannot express. Interpretation is limited to one bounded request per unresolved decision, returns schema-validated structured constraints, and then hands control back to the deterministic coordinator. Recursive AI planning is forbidden.

AI never performs side effects. Buying, booking, messaging, Calendar mutation, navigation, orders and all external actions remain behind existing capability, safety and confirmation contracts. Synthesis receives only the minimum verified structured facts and cannot alter them. AI outage/timeout returns the deterministic result; completed deterministic results cancel or bypass unnecessary AI. Mechanical work—arithmetic, conversion, sorting, filtering, comparison, dedupe, caching, timeouts, URL/capability routing, ranking and structured formatting—never uses AI.

## Observability and acceptance

Privacy-safe metrics cover intent resolution, planning, provider and critical-path latency, first useful result, completion latency, provider/cancellation counts, AI invocation/latency/token/cost metadata where available, and fallback reason. No secrets or unnecessary personal data are recorded.

Mandatory tests cover: simple zero-AI fast path; concurrent deterministic multi-module execution; Calendar/location/Weather/Transport/Hotel travel case with zero AI; exactly one schema-valid AI interpretation after explicit unresolved state; AI timeout with continued deterministic operation; honest provider partial failure; hard-constraint exclusion; cancellation of obsolete parallel work.

Roadmap rule: persist this addendum, record fulfilled requirements without duplication, schedule only missing coordination/AI work in the existing orchestration milestone, and continue the first unfinished current milestone. Do not create a foundation model, operating system, duplicate router/registry/provider architecture, or separate universal AI engine.
