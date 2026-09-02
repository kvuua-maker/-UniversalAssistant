# Data Processor Inventory

Status: implementation-aligned local inventory; production activation requires owner/privacy approval and live evidence.

| Service | Data categories actually sent/available | Purpose | Region/retention/security note | Current status |
|---|---|---|---|---|
| Apple platform services (Contacts, EventKit, Speech, MapKit, WeatherKit, Sign in with Apple, StoreKit, CloudKit when configured) | User-authorized system records, speech audio/transcript, requested location/query, Apple identity subject, purchases/sync records as applicable | Core Apple-native capabilities | Governed by Apple account/device/service terms; repository does not establish processing region/retention | READY_FOR_LIVE_VERIFICATION per capability |
| Apple Push Notification service | Device token, app topic, minimal alert and internal route | Proactive notification delivery | TLS endpoint selected by sandbox/production; invalid tokens removed | READY_FOR_LIVE_VERIFICATION |
| Silpo official MCP | Bearer token and explicit product/catalog arguments | Read-only grocery discovery | Fixed HTTPS host; timeout and read-tool allowlist; provider retention/region not established | READY_FOR_LIVE_VERIFICATION |
| Direct/affiliate partners | Pseudonymous attribution, offer/agreement refs, conversion evidence and monetary state when activated | Referral attribution/reconciliation | No production partner configured; contract and geography define retention/transfer | READY_FOR_LIVE_VERIFICATION |
| Optional AI interpretation provider | Only unresolved text and allowed constraint-key schema when explicitly configured | One bounded semantic fallback | No production provider/credential configured; must not receive live facts or execute actions | READY_FOR_LIVE_VERIFICATION |

No third-party analytics, crash-reporting, ad network, tracking SDK, payment processor, KYC provider, or external database client dependency is linked in the current targets. Re-run this inventory and privacy-manifest audit for every dependency/provider change.
