# Post-Build-28 VPS diagnostic correlation

Read-only evidence was retrieved on 2026-09-08 with the pinned-host reader
`scripts/live_diagnostics.py --ssh root@178.105.32.46`. No VPS service, file,
record, or production state was modified.

## Evidence boundary

Build 28 contains 78 privacy-safe sessions from `2026-09-08T12:12:23Z`
through `2026-09-08T13:32:29Z`: 54 `SUCCESS` and 24 `UNKNOWN`. The schema
intentionally excludes transcript, contact, photo, file, message, and precise
location contents. Correlation with the owner's physical sequence is therefore
time-window/ordering evidence only, never transcript-authoritative evidence.

## First observable wrong stages

| Observable production path | Count | First observable divergence |
|---|---:|---|
| `unknown` → `web_handoff_fallback` | 14 | semantic/capability selection did not produce a canonical local, personal, structured, or system family before the generic fallback |
| `open` → `capability_unavailable` | 10 | an open intent was selected, but typed app/destination resolution or legitimate handoff was unavailable |
| `deviceAction` → `capability_unavailable` | 5 | system intent was recognized, but the capability registry/executor could not provide a public action or truthful specialized terminal result |
| `mediaSearch` → `capability_unavailable` | 2 | media semantics reached a structured family, but no executable media capability was resolved |
| `photoSearch` → `capability_unavailable` | 1 | Photo semantics reached the family but did not obtain an executable result |
| voice lifecycle ended at `state_delivered_to_view_model` with no router stage | 6 | no final command reached the router; privacy-safe evidence cannot distinguish empty recognition, deliberate cancellation, or abandoned input |

Other observed structured success paths include `deviceAction` (7), `open`
(6), `cameraCapture` (4), `settings` (3), `fileSearch` (3), `calendarQuery`
(3), `translation` (2), `reminderQuery` (2), `placeSearch` (2), `weather`
(1), `navigation` (1), `localUtility` (1), and `audioRecord` (1). One
Photo→OCR trace reached `photoSearch`, then `localUtility`, and rendered both a
typed Photo result and OCR presentation, proving executor reachability but not
semantic correctness for every natural command.

The completed diagnostic sessions stop before the owner's four physical
Contacts/Call crashes. Their absence is consistent with a hard termination
before idle/delivery, but cannot identify a transcript or prove a specific
crash symbol. The later Contacts ownership repair and new stage breadcrumbs
remain AUTOMATED VERIFIED and require physical iPhone retest.

## Repair consequences

The evidence supports mechanism-level work already in progress: structural
semantic framing before generic fallback; role-scoped app/service/entity
resolution; typed system limitations; bounded Photo/Contacts lifecycles; and
request-generation ownership. It does not justify phrase patches or claims
about omitted raw text. Future builds include privacy-safe pre/post-framework
breadcrumbs so a hard crash can be bounded more precisely.

