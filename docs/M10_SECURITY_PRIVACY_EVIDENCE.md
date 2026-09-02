# M10 Security and Privacy Evidence

Date: 2026-09-02. Verification type: local static/source review plus behavioral tests. Hosted Standard scan `d848e733-3aab-498d-b727-f7f17d8ee101` completed with zero reportable findings and complete declared coverage (4,913,936 measured tokens, one parent thread). Independent workers were unavailable by runtime policy, so the documented sequential parent fallback was used. The hosted artifact is bound to its initial worktree snapshot; the in-audit fixes and added evidence were separately rechecked by full 216-test iOS and 69-test backend suites.

## Reviewed boundaries

| Surface | Evidence | Verification |
|---|---|---|
| Local data protection | `LocalStore.swift`, `AudioRecorderController.swift`, `UserFeedbackStore.swift` | atomic/complete protection; feedback bounded to 100 |
| OAuth/session | `ProviderAuthenticationBoundary.swift`, `AppleAccountSession.swift` | scope/expiry/revocation and this-device-only Keychain |
| Network destinations | `SilpoMCPClient.swift`, `APNSDelivery.swift`, route/navigation builders | fixed/validated HTTPS endpoints and bounded timeouts/payload |
| Webhook ingress | `PartnerWebhookIngestion.swift` | constant-time HMAC, replay window, mandatory durable dedupe, 1 MiB default body limit, bounded IDs/schema |
| Tenant/admin | `PartnerTenantAuthorization.swift` | tenant match, role/permission enforcement, allow/deny audit |
| Financial history | `CommercialAgreements.swift`, `ConversionLedger.swift`, `ReconciliationSettlement.swift` | version binding, Decimal, valid transitions, append/adjust evidence |
| Coordination/AI | deterministic plan/executor/result composer and bounded AI files | bounded concurrency/time/cancellation; one schema-validated fallback; no AI action authority |
| Privacy/release | privacy manifest, entitlements, package/project/workflows/config, processor/data/retention/legal docs | no linked third-party package, tracking domain or analytics/ad SDK; live claims remain queued |

Repository checks found no tracked private-key/API-token signature, no arbitrary-load entitlement, and no product-source cleartext HTTP endpoint. The two `http://` matches are XML DTD declarations, not runtime network destinations. Backend has no external Swift package dependency. The only product `print` emits the static health payload.

## In-audit defects and disposition

1. Requirement 779 was not end-to-end evidenced: the visible button used an unrelated clarification label and the test called the store directly. Fixed with the localized `feedback_wrong_result` action, real HomeView→ViewModel→UserFeedbackStore wiring, protected persistence and a behavioral reload/JSON-key test.
2. Partner webhook replay persistence was optional and could degrade to process-local deduplication. Fixed by requiring a durable URL for every ingestion instance. Added bounded body/identifier validation and restart/oversize tests.

After these fixes, no additional source-backed reportable vulnerability was validated in the locally executable implementation. This does not assert properties of an undeployed ingress, identity provider, KMS, database ACL, App Store privacy report, real OAuth account, APNs account or physical device; those exact operations remain in `LIVE_VERIFICATION_QUEUE.json`.

## Requirement 779 end-to-end proof

`AssistantHomeView.swift:20-22` connects the result-card action to `AssistantViewModel.reportWrongResult()`. `CompactResultCard.swift:35-40` renders the localized action with accessibility ID `assistant.feedback.wrong-result`. `AssistantViewModel.swift:58-64` records only `.wrongResult`. `UserFeedbackStore.swift:5-8,21-32` defines/persists only diagnostic ID, category and time. `UserFeedbackStoreTests.wrongResultUserActionPersistsOnlyPrivacySafeMetadataEndToEnd` submits a sensitive raw command, invokes the user action, reloads the persistent store, asserts the raw command is absent, and asserts the serialized key set is exactly `diagnosticID/category/createdAt`.

## Apple privacy audit

`PrivacyInfo.xcprivacy` is valid and declares no tracking, tracking domains, collected-data persistence, or Required Reason API category for the current target. Source/dependency inspection found no direct current use of the five Required Reason categories (active keyboards, disk space, file timestamps, system boot time, UserDefaults). The target uses filesystem content operations but does not query file timestamps. Re-audit is a release gate when code or SDK dependencies change. App Store-generated privacy report and metadata answers are live-only evidence.

Official basis checked 2026-09-02:

- Apple Privacy Manifest Files: https://developer.apple.com/documentation/bundleresources/privacy-manifest-files
- Apple Required Reason APIs: https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api
- Apple App Privacy: https://developer.apple.com/help/app-store-connect/manage-app-information/manage-app-privacy/
- Apple App Review privacy policy rule: https://developer.apple.com/app-store/review/guidelines/
