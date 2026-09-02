# M7 Integration Depth Audit

The executable audit applies requirements 1364–1371 and 1614–1617 without inferring a deeper capability from a shallower mechanism.

| Provider/system | Proven local contract | Maximum claim | External/device gate |
|---|---|---|---|
| Telegram / Viber | exact draft/share context | L2 handoff; send remains user action | installed-app device test |
| Google Maps / Waze | exact search/navigation destination | L2 context handoff | installed-app route test |
| Apple Music | authorization gateway and managed-control contract | local E3 core; live L3/L4 not yet claimed | entitlement, account, device |
| Find My | manual system-app instruction | L1 compliant fallback | no public third-party location API |
| Camera / Files | public system-first flow planning | prepared UI, not completed mutation | permission and device UI |
| QR / barcode / translation | typed local interpretation contract | local E3 safety core | live Vision/Translation device path |
| Ukraine emergency | exact `tel:` destination | L2 Phone handoff | SIM/network/device |

All launch-market records retain documented/device-required status. None is promoted to production-verified merely from documentation, simulator tests, or another capability's success.

Local verification: 161 iOS tests across 39 suites and 29 backend tests across 7 suites passed on 2026-09-02. Exit state: `SUCCESS` at local E3; all listed external/device gates remain open and explicit.
