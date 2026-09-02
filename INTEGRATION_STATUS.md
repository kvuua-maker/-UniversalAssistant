# Integration Status

No external commerce provider is claimed integrated. The provider-neutral M4 registry, RetailProvider contract, GTIN validation and exact variant resolver are locally implemented/tested at E3; provider status must enter the registry capability-by-capability after official feasibility evidence.

## M12 device/system actions

`UniversalDeviceCommandRouter` now reuses the structured command parser, `LocalActionRouter`, capability registry and documented launch/deep-link catalog. Exact localized aliases open silently; collisions produce one clarification; verified exact contexts win over generic launch; absent mechanisms return a truthful unsupported reason. Capability-by-capability public-mechanism evidence is recorded in `PROVIDER_CAPABILITY_MATRIX.md`. Installed-device App Intents/App Shortcuts discovery and launch observation remain a physical-device-only verification item, not a claimed live success.
