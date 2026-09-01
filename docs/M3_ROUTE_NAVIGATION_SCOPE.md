# M3 Route-aware Search and Navigation

- Public MapKit Directions adapter returns provider-calculated distance, expected travel time, timestamp, and concise route steps.
- Route-aware detour is calculated from real baseline and two route legs; straight-line distance is never presented as detour.
- Candidate route evaluation is bounded to eight and isolates individual route failures.
- Exact destination handoffs support Apple Maps, official Google Maps URLs (`api=1`), and official Waze deep links with attribution.
- Invalid coordinates fail before handoff and never degrade to a provider homepage.
- User default navigation provider persists locally and defaults truthfully to Apple Maps.

Official evidence verified 2026-09-01:

- https://developer.apple.com/documentation/mapkit/mkdirections
- https://developers.google.com/maps/documentation/urls/get-started
- https://developers.google.com/waze/deeplinks

Verification: Development simulator suite passed 51 tests in 14 suites. Live route calculation and installed-app handoff remain `LIVE_DEVICE_TEST_REQUIRED`.
