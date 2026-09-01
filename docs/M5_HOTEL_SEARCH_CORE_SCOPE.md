# M5 Hotel Search Core — Requirement Scope Pack

- Task ID: `M5-HOTEL-SEARCH-CORE`
- Requirement IDs: 21–23, 38–49, 101–102, 203, 219–223, 288–302, 400–406, 603–607, 613–618, 628, 641–645, 790–795, 814, 1422–1425, 1476–1480, 1490–1496, Addendum 7, 12–17, 24–35, 41–59.
- Exact capability: normalize and rank real-evidence hotel/accommodation offers against hard destination/date/guest/budget constraints; preserve provider/source/freshness; expose only a truthful exact booking handoff state.
- Selected path: provider-neutral local domain and adapter contract, with no live provider claim until a later capability-specific official integration passes E4.
- Feasibility: `PASS_SELECTED_PATH` for the provider-neutral E3 core; individual Booking.com/Dobovo/provider capabilities require separate official capability contracts and feasibility gates.
- Integration depth: local E3 core only; no external provider is integrated by this task.
- Required evidence: Development simulator build, focused and full iOS tests, backend regression tests, truthful state/docs.
- Failure cases: invalid itinerary/dates/guests, stale or missing price/availability evidence, mixed price bases/currencies, unavailable offer, unverified booking state, invalid/generic destination, partial provider failure.
- Privacy: no guest identity, payment credential or provider account data is stored by the core.
- Stop condition: deterministic core and tests pass; state explicitly avoids any live availability/booking claim; checkpoint committed and pushed.
