# M12 Device and System Actions Core

Requirements MS-851–MS-870. Status: VERIFIED_LOCAL for deterministic routing; installed-app execution remains covered by the existing physical-device queue.

The single parsed `StructuredCommand` now enters `UniversalDeviceCommandRouter`, which reuses `LocalActionRouter` for EventKit/Contacts/Reminders/recorder, routes outside-world intents to existing capability modules, and resolves supported apps through exact localized aliases. It never performs arbitrary fuzzy selection: multiple exact matches produce one typed clarification. Unambiguous app opens are marked silent, and a verified exact-context URL is preferred over generic launch.

The implementation reuses `AppCapabilityRegistry`, `LaunchMarketAppMatrix` and `SystemQuickActionPlanner`; it adds no duplicate provider registry. Only documented public schemes/Universal Links are represented, and unsupported resolution returns an explicit public-mechanism reason. Behavioral tests exercise local, external, direct app, ambiguity, unsupported spelling and exact Telegram context paths with zero AI involvement.

Evidence: `UniversalDeviceCommandRouter.swift`, `StructuredCommand.swift`, `UniversalDeviceCommandRouterTests.swift`, `LocalCommandEngineTests.swift`, `PROVIDER_CAPABILITY_MATRIX.md` and `INTEGRATION_STATUS.md`. Full regression on 2026-09-02: 235 iOS tests across 60 suites and 78 backend tests across 22 suites passed. The physical installed-app/App Intents/App Shortcuts observation is isolated in `LIVE_VERIFICATION_QUEUE.json`; it does not hide locally executable work.
