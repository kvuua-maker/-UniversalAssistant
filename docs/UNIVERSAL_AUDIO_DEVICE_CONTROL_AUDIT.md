# Universal Audio Device Control — evidence audit

Audit date: 2026-09-04. Rule: vendor-app functionality is not a third-party API. Unknown remains unknown.

## Existing reuse and implemented gaps

Existing `MediaIntegrationEngine`, `AudioSessionEventMonitor`, MusicKit, voice, privacy and Action Graph boundaries remain unchanged. The new typed layer adds a capability/evidence registry, provider-policy gate, idempotent coordinator with authoritative readback, scoped persistent profiles, safe automation, permitted-stream DSP, public Apple route picker, deterministic no-AI commands and capability-driven native presentation.

## Current official ecosystem evidence

| Ecosystem | Official mechanism/evidence | Current truthful integration state |
|---|---|---|
| Apple/AirPods/Beats/AirPlay | [AVRoutePickerView](https://developer.apple.com/documentation/avkit/avroutepickerview), [MediaPlayer](https://developer.apple.com/documentation/mediaplayer), [MusicKit](https://developer.apple.com/documentation/musickit) | Public system picker/media/MusicKit only. AirPods settings are system handoff; physical behavior is live-only. |
| Google Cast | [iOS Sender integration](https://developers.google.com/cast/docs/ios_sender/integrate), [sender checklist](https://developers.google.com/cast/docs/design_checklist/sender) | Official SDK boundary; real receiver/app-ID verification required. iOS physical volume buttons are not claimed. |
| Sonos | [Control API](https://docs.sonos.com/docs/control-sonos-players) | Official OAuth/cloud Control API and subscriptions, scoped to documented commands; account/hardware verification required. |
| HEOS / Denon / Marantz | Official HEOS CLI specification supplied through Denon developer documentation | Forward-compatible documented response parser; supported hardware/LAN verification required. |
| Bang & Olufsen Mozart | [official third-party drivers/model list](https://support.bang-olufsen.com/hc/fr/articles/360049859212-Drivers-for-3rd-Party-integration) | ControlLink is model-scoped; no transfer to other B&O families. |
| BluOS / Bluesound / OEM | [BluOS downloads](https://bluos.net/downloads/) | Custom Integration API is installer/partner and model scoped; approval/hardware verification required. |
| WiiM / Linkplay | [official HTTP API](https://www.wiimhome.com/pdf/HTTP%20API%20for%20WiiM%20Products.pdf) | Documented WiiM products only; hardware verification required. |
| Spotify | [Developer Policy](https://developer.spotify.com/policy) | Voice-enabled SDA, content alteration/DSP/AI ingestion and prohibited commercial streaming paths are blocked. |
| Sony, Bose, Devialet, JBL/Harman Kardon, Marshall, Sennheiser, Shokz, Ultimate Ears, Jabra, Bowers & Wilkins, Naim, Yamaha/MusicCast, Cambridge Audio, KEF, Audio Pro, Samsung, LG | No current public cross-product third-party deep-control API was established by official evidence in this audit | System route/media control or official app handoff only; proprietary EQ/ANC/grouping remains `UNKNOWN`/unsupported, never inferred from vendor apps. Legacy/archived APIs remain family-scoped. |
| YouTube Music, Deezer, TIDAL, Amazon Music and other content services | Provider-specific public SDK/terms required | Playback/handoff metadata never implies raw-audio DSP rights; unknown policy fails closed. |

## Live boundary

Simulator/unit evidence proves local semantics only. Bluetooth/AirPlay/Cast/vendor hardware, firmware, battery, interruptions, OAuth/cloud/LAN/MFi commands and model-specific readback require exact physical/provider live verification. One device never proves a brand.
