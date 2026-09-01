# M4 Exact Purchase and Affiliate Handoff

- Purchase routing accepts only an exact HTTPS offer page; provider homepages and malformed destinations are rejected.
- Without verified affiliate configuration, routing falls back to the same exact offer URL and truthfully reports no attribution configuration.
- Affiliate parameters are applied only for the matching provider, allowlisted official host and allowlisted parameter names. Existing exact variant query data is preserved.
- Official-app handoff requires an allowlisted scheme and carries the same allowlisted attribution and variant parameters; otherwise it fails safely rather than guessing.
- The output state is only `destinationPrepared`. An outbound click is never represented as a purchase, conversion or commission.
- Configuration stores no secrets and does not claim conversion attribution; provider reporting remains the only source of conversion/commission truth.

Verification: Development simulator suite passed 75 tests in 19 suites on 2026-09-01. Live provider affiliate agreements, IDs, approved domains/schemes and reporting remain provider-specific owner/partner gates.
