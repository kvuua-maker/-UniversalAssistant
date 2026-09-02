# Bounded AI Interpretation Fallback

- Deterministic resolution bypasses the provider with zero calls.
- Only an explicit typed unresolved contract can trigger one request. The provider returns constraints only; allowed keys, non-empty values and confidence range are schema-validated.
- AI output becomes a soft interpretation input and returns to deterministic coordination. It cannot contain execution scripts, side effects or live factual fields outside the allowlist.
- Timeout, provider failure or invalid schema returns an immediate deterministic fallback and never retries recursively.
- Local verification: 195 iOS tests across 49 suites and 29 backend tests across 7 suites passed on 2026-09-02.
- Exit state: `SUCCESS` at local E3.
