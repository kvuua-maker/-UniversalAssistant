# M7 Ukraine Emergency Core

- Task ID: `M7-UKRAINE-EMERGENCY-CORE`
- Requirement ID: 1634.
- Selected path: exact user-visible system Phone handoff to Ukraine 112/101/102/103/104.
- Region boundary: these destinations are offered only when the resolved region is Ukraine (`UA`).
- Truth boundary: preparing a call never claims dispatch, operator connection, or location sharing.
- Device gate: actual call UI, SIM/network behavior, and any future official 112 Ukraine app mechanism require physical-device verification.
- Local verification: 158 iOS tests across 38 suites and 29 backend tests across 7 suites passed on 2026-09-02.
- Exit state: `SUCCESS` for the bounded local E3 handoff contract.
