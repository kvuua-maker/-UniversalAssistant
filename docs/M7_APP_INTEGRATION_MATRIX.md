# M7 Launch-Market App Integration Matrix

Verified 2026-09-02 from official documentation.

| App | Verified path | Supported boundary | Status |
|---|---|---|---|
| Telegram | `t.me` / `tg:` deep links | Open exact chat/share draft; user sends | documented |
| Viber | `viber://forward` | Open editable share draft; user sends | documented |
| Google Maps | Maps universal URLs | Search/directions/navigation handoff | documented |
| Waze | `https://waze.com/ul` | Search/navigation handoff | documented |
| Apple Music | MusicKit | Search/library/playback with permission | device test required |

WhatsApp and other targets are not marked integrated until a current official consumer iOS capability source is captured. No messaging record claims silent sending, and no navigation handoff claims private app state or route data access.

Verification: 140 iOS tests across 33 suites and 29 backend tests across 7 suites passed.
