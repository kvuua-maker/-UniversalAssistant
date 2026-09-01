# Provider Capability Matrix

No live commerce provider is claimed integrated. The M4 typed registry and eligibility logic are `IMPLEMENTED_TESTED` locally; individual sources remain capability-by-capability research/integration work.

Commerce providers additionally require per-capability fields for exact identity/variant, Ukraine region/delivery, price/final-cost components, availability/freshness, seller protection, affiliate network/attribution, exact handoff, credentials/approval, rate limits, restrictions and last official verification.

| Source | Region | Capability | Status | Credentials / approval | Official evidence | Fallback |
|---|---|---|---|---|---|---|
| Commerce core registry | UA + extensible | region/capability/status filtering and kill switch | IMPLEMENTED_TESTED (E3) | none | internal contract tests, 2026-09-01 | none |
| Retail providers | UA first | search/exact product/price/availability/shipping/handoff | RESEARCH_PENDING | provider-specific | not yet verified | exact official page where legitimately known |
