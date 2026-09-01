# M3 Acceptance Checkpoint

M3 local evidence level E3 is complete:

- Accurate location validates accuracy, age, reduced accuracy and impossible movement, with bounded resampling and explicit manual/offline context.
- Place search uses MapKit behind a provider contract with bounded concurrency, timeout, partial results, conservative deduplication and stable user-first ranking.
- Route-aware search uses actual MapKit route legs; navigation produces exact Apple Maps, Google Maps or Waze destination handoffs.
- Weather uses an on-demand WeatherKit adapter for normalized current/hourly/daily context with bounded timeout and location provenance.
- Poor, suspicious, unavailable and denied location states have deterministic recovery actions; suspicious coordinates are not consumed.
- Development simulator suite: 55 tests in 15 suites passed on 2026-09-01.

E4 remains queued for physical GPS/reduced-accuracy recovery, live regional places/routes, installed-app handoff and live WeatherKit entitlement/attribution. These device gates do not block independent M4 work.
