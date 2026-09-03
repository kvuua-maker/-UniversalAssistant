# Privacy / AI data-flow hardening — Phase A and B

## Phase A — read-only evidence map

| Source | Local boundary | Persistence/cache | External recipients | Current evidence |
|---|---|---|---|---|
| credentials/auth | Keychain/server credential stores | scoped credential records | exact authenticated provider only | ProviderAuthenticationBoundary; BackendAccessControl |
| contacts/calendar/reminders | typed Apple frameworks and bounded lookup | selected typed result | action provider only when requested | LocalContactResolver; CalendarService; ReminderService |
| photos/files/scans/PDF | limited PhotoKit/document picker/on-device transforms | app storage/temp lifecycle | no generic upload path | AppleLocalContentSources; OnDevicePDFProcessor |
| email/messages | provider client and exact thread/message | provider-scoped | Gmail or explicit handoff | GmailEmailProvider; MessagingIntegration |
| location | CurrentContext/typed route/place engines | freshness-bounded context | maps/weather/search as required | AccurateLocationEngine; RouteEngine |
| voice/transcript | visible AVAudio/Speech session | transient controller/explicit recordings | Apple speech path where authorized | VoiceInputController; AudioRecorderController |
| commerce/business/jobs | typed domain/tenant models | LocalStore/backend stores | contracted provider/ATS only | commerce cores; tenant authorization; JobsMarketplace |
| analytics/logging | metadata-only performance/incident events | bounded telemetry | no third-party analytics SDK found | PerformanceRecorder; OperationalIncidentMonitor |
| notifications/share/clipboard | typed payloads and explicit user action | app-group inbox/push registry | APNs/selected share target | ShareViewController; APNSDelivery |

Production endpoint inventory is represented by concrete URLSession adapters; no general unrestricted AI filesystem/Keychain/device-resource tool exists. Secondary paths (logs, retries, backups, notifications and temp files) were included. Provider-side retention and physical permission/network observations are not inferred.

## Phase B — compatibility/threat analysis

| Gap/threat | Before | Minimal after | Capability impact |
|---|---|---|---|
| field classification absent | payload-specific ad hoc checks | typed field/payload classification | no capability removed |
| secrets could enter composed context indirectly | no central universal gate | absolute NEVER_AI redaction/block | requested non-secret content remains usable |
| permission could be confused with transfer consent | contextual OS permission only | separate typed transfer consent | previously approved bounded flows reusable |
| excessive context | per-engine minimization | central purpose/bounds/metadata stripping | semantics-preserving bounded subset |
| prompt injection | content handled as data by architecture but no shared contract | untrusted-content isolation and no authority elevation | retrieval remains functional |
| provider/model switch | provider policies distributed | same gate independent of destination identity | no provider-specific weakening |
| cache/user bleed | several scoped caches | reusable scope key and revocation invalidation contract | caching preserved |

No proposed fix disables a provider, local capability, checkout, search, voice, document, Jobs or Business flow. Unsafe sensitive transmission fails closed while local/minimized fallback remains available.
