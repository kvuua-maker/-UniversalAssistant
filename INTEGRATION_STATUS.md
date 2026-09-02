# Integration Status

No external commerce provider is claimed integrated. The provider-neutral M4 registry, RetailProvider contract, GTIN validation and exact variant resolver are locally implemented/tested at E3; provider status must enter the registry capability-by-capability after official feasibility evidence.

## Evidence contract

IntegrationVerificationPolicy enforces MS-982–1004 and the ZERO-OMISSION statuses. Local implementation may be VERIFIED_LOCAL with behavioral E3 evidence, but no external capability may become VERIFIED_LIVE below E4 and no physical-iPhone capability below E5. READY_FOR_LIVE_VERIFICATION requires an exact dependency, owner, live action and expected result. Evidence containing credentials, private message/email bodies or other unnecessary sensitive values is rejected.

| Provider/domain | Deepest production path now implemented | Local evidence | Required external evidence |
|---|---|---|---|
| Gmail | OAuth boundary, real Gmail REST search/raw MIME/attachment/draft/send/labels | GmailEmailProviderTests, E3 | E4 controlled authorize → read → draft/send/label → read-back; queued |
| Messages and popular messengers | MessageUI composer and exact supported public handoffs; no fake send/history | MessagingIntegrationTests, E3 | E5 installed-app/device observation; queued |
| Photos / Files / Spotlight | PhotoKit authorized search, document picker/security scope, app-owned Spotlight index | local content behavioral tests, E3 | E5 permission/content/index observation; queued |
| Camera / Apple Music / Podcasts | real public framework/provider paths with truthful authorization/failure | Apple system-domain tests, E3 | E4 catalog plus E5 camera/playback; queued |
| Universal Personal Search | concurrent typed search of every supplied authorized source, exact open/shortlist and partial failure | UniversalPersonalSearchEngineTests, E3 | E5 combined controlled-source journey; queued with source items |
| CarPlay | fail-closed category/entitlement policy only; no entitlement claim | PlatformEligibilityPolicyTests, E3 | exact owner category + Apple entitlement + E5 environment; queued |

No row is labelled fully tested or verified live. Current credentials/device/entitlements are unavailable, so the exact remaining steps are persisted in LIVE_VERIFICATION_QUEUE.json.

## M12 device/system actions

`UniversalDeviceCommandRouter` now reuses the structured command parser, `LocalActionRouter`, capability registry and documented launch/deep-link catalog. Exact localized aliases open silently; collisions produce one clarification; verified exact contexts win over generic launch; absent mechanisms return a truthful unsupported reason. Capability-by-capability public-mechanism evidence is recorded in `PROVIDER_CAPABILITY_MATRIX.md`. Installed-device App Intents/App Shortcuts discovery and launch observation remain a physical-device-only verification item, not a claimed live success.
