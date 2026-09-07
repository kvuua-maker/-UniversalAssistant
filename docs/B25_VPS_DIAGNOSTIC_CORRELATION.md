# Build 25 VPS diagnostic correlation

Evidence was collected read-only with `Scripts/live_diagnostics.py` from
`root@178.105.32.46`. The app posts through HTTPS/nginx to the localhost-only
`universalassistant-diagnostics.service` (`127.0.0.1:8787`); its store is
`/mnt/HC_Volume_106589590/universalassistant-diagnostics/data/sessions`.

For Build 25, 107 privacy-safe sessions span `2026-09-07T10:28:06Z` through
`2026-09-07T13:35:41Z`. The physical report is authoritative. Server schema
explicitly forbids transcript, contact, message, photo, document and location
fields, so evidence is sequential/time-window correlation, never transcript-
authoritative matching.

Router counts: `unknown=36`, `open=18`, `deviceAction=9`, `show=6`,
`navigation=4`, `productSearch=4`, `translation=4`, `cameraCapture=2`,
`contactCall=2`, `fashionDiscovery=2`, `photoSearch=2`, `placeSearch=2`,
and one each for `audioRecord`, `calendarCreate`, `multiStep`, `noteCreate`,
`weather`. Recorded failures include `open=15`, `navigation=4`,
`contactCall=2`, plus external-provider-required product/fashion paths.

One retained example (`E3A2B1EA-F4F2-4C5B-A0BD-B2E24C0E779F`) shows an
available `uk_UA` recognizer, audio buffers, partial/final callbacks, final
length 27, route `open`, and `capability_unavailable`. It contains no text and
therefore cannot identify which physical command it represents.

No production state, service, log, or stored record was changed.
