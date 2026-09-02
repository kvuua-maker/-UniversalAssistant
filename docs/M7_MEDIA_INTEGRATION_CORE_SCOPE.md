# M7 Media Integration Core

- Task ID: `M7-MEDIA-INTEGRATION-CORE`
- Requirement IDs: 265, 816, 1618–1623.
- Capability: authorized provider search, exact item play, managed pause/resume/next/previous, and exact provider-item handoff.
- Selected path: MusicKit authorization gateway plus provider-neutral adapter; no control of playback not started by UniversalAssistant.
- Device gate: real Apple Music authorization/catalog/playback requires signed entitlement and physical-device test.
- Local verification: 147 iOS tests across 35 suites and 29 backend tests across 7 suites passed on 2026-09-02.
- Exit state: `SUCCESS` for the bounded local E3 core; live provider playback remains explicitly entitlement/device gated.
