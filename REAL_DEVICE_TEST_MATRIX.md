# Real Device Test Matrix

| Capability | Why device is required | Status |
|---|---|---|
| Microphone and speech | Physical audio route, permission sheets, accents | DEVICE_TEST_REQUIRED — Test VOICE-001 queued |
| App Intent / Action Button route | System surfaces and device configuration | DEVICE_TEST_REQUIRED — Test VOICE-002 queued |
| Contacts | Real full/limited permission, exact-ID alias and ambiguous-name resolution | DEVICE_TEST_REQUIRED — CONTACTS-001 |
| Calendar | Full-access permission and real create/read/update/delete/undo | DEVICE_TEST_REQUIRED — CALENDAR-001 |
| Reminders | Full-access permission and real create/read/update/delete/undo | DEVICE_TEST_REQUIRED — REMINDERS-001 |
| Audio recorder | Permission, start/pause/resume/stop/play/rename/delete/share, interruptions and routes | DEVICE_TEST_REQUIRED — RECORDER-001 |
| GPS and navigation handoff | Physical sensors and installed apps | NOT_TESTED — M3 |
| Accurate location | When-in-use permission, reduced/full accuracy, stale/poor recovery and physical movement | DEVICE_TEST_REQUIRED — LOCATION-001 |
| Places | Live regional MapKit queries, place IDs, addresses, categories and ranking | LIVE_TEST_REQUIRED — PLACES-001 |
| Route/navigation | Live MapKit routes, actual detour and Apple/Google/Waze exact handoff | LIVE_DEVICE_TEST_REQUIRED — NAVIGATION-001 |
| WeatherKit | Live current/hourly/daily response, entitlement, attribution and destination context | LIVE_DEVICE_TEST_REQUIRED — WEATHER-001 |
| Location recovery | Poor/suspicious resampling, denied permission Settings route and explicit manual fallback | DEVICE_TEST_REQUIRED — LOCATION-002 |
| Ride handoff | Provider app/web behavior, exact pickup/dropoff preservation and owner-issued Uber client ID | LIVE_DEVICE_TEST_REQUIRED — RIDE-001 |
| Public transport | Regional scheduled versus real-time attribution and exact route handoff | LIVE_DEVICE_TEST_REQUIRED — TRANSPORT-001 |
| Ticket handoff | Exact itinerary/fare/inventory preservation and confirmation before leaving the app | LIVE_DEVICE_TEST_REQUIRED — TICKET-001 |
