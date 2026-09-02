# M9 Feed Health and Offboarding Core

Partner data is classified as `VERIFIED_LIVE`, `PARTNER_PROVIDED_RECENT`, `STALE` or `UNKNOWN` from source provenance, source timestamp and configurable age policy. Manual/profile data can never become verified live. Health is independently classified as healthy, degraded, stale, temporarily unavailable or suspended.

The indexed category directory uses bounded paginated queries rather than loading every partner record. Failure state is partner-specific, so one unavailable integration does not invalidate healthy alternatives. Monetizable handoff requires active onboarding plus acceptable health and freshness; suspension/termination blocks new handoffs. Offboarding revokes integration credentials while conversion, accounting and audit history remain untouched.
