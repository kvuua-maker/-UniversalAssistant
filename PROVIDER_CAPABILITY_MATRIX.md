# Provider Capability Matrix

No live commerce provider is claimed integrated. The M4 typed registry and eligibility logic are `IMPLEMENTED_TESTED` locally; individual sources remain capability-by-capability research/integration work.

Commerce providers additionally require per-capability fields for exact identity/variant, Ukraine region/delivery, price/final-cost components, availability/freshness, seller protection, affiliate network/attribution, exact handoff, credentials/approval, rate limits, restrictions and last official verification.

| Source | Region | Capability | Status | Credentials / approval | Official evidence | Fallback |
|---|---|---|---|---|---|---|
| Commerce core registry | UA + extensible | region/capability/status filtering and kill switch | IMPLEMENTED_TESTED (E3) | none | internal contract tests, 2026-09-01 | none |
| Retail providers | UA first | search/exact product/price/availability/shipping/handoff | RESEARCH_PENDING | provider-specific | not yet verified | exact official page where legitimately known |

## M12 device application capability evidence (MS-854–870)

| Target | Public mechanisms checked | Deepest implemented behavior | Unsupported boundary / fallback |
|---|---|---|---|
| Apple local domains | Contacts, EventKit/Reminders and AVFoundation public frameworks; App Intents entry points | Existing typed local action routes perform supported contact, event, reminder, note and recorder work | No private system-app launch or `App-Prefs` URL; return the typed local result or truthful unavailable state |
| Apple Maps / navigation | MapKit and HTTPS Maps links; local/external capability route | Existing navigation capability receives the structured destination rather than a generic application launch | Installed-app selection remains system-controlled |
| Telegram | Officially documented `tg:` URL scheme and public deep-link form | Exact alias launch; exact public username context via `tg://resolve?domain=…` | No arbitrary chat/message side effect; unsupported context is not fabricated |
| Viber | Publicly documented application URL scheme | Exact alias application launch | No deeper action is claimed without a currently verified official contract |
| Google Maps | Official Maps URLs / Universal Links | Exact search context through HTTPS Maps URL | Falls back to the same legitimate web destination if the app is absent |

App Intents/App Shortcuts exposed by third-party binaries are discoverable only on an installed physical-device configuration. That specific verification is queued; no private inter-app enumeration or control is used.
