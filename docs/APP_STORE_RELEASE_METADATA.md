# App Store Release Metadata Draft

This is a local preparation artifact, not proof of TestFlight distribution, App Review approval, or publication. Final naming, public URLs, screenshots, legal disclosures, pricing, and market availability require owner/legal approval and current App Store Connect validation.

## Name candidates

- UniversalAssistant
- Universal Assistant — Actions
- UniversalAssistant — Voice & Tasks

The owner selects the final available name. Do not imply that optional AI providers, live partners, or unsupported system control are built in.

## Description draft

UniversalAssistant turns a spoken or typed request into a concise result or a legitimate action on iPhone. It uses supported Apple capabilities and connected providers for tasks such as routes, reminders, documents, shopping comparisons, travel, appointments, and delivery tracking. Availability varies by device, permission, region, connected account, and provider. Live facts remain source-attributed; unsupported actions use a truthful handoff or unavailable state. Optional AI is a bounded fallback and is not required for deterministic commands.

## Privacy disclosure inventory

- Personal device data stays local unless a user-approved capability requires a documented provider request.
- Microphone, speech, location, Contacts, Calendar, Reminders, Photos, Files, notifications, and connected-account access are requested only in context.
- Raw command text is not stored in diagnostic feedback or aggregate telemetry.
- Credentials use Keychain or server-side secret injection; no merchant password is requested.
- Affiliate or sponsored disclosure is shown where required; tracking is not used to fabricate commission eligibility.
- Final App Privacy answers must be generated from the release build and compared with `UniversalAssistant/PrivacyInfo.xcprivacy` and `DATA_PROCESSOR_INVENTORY.md`.

## Permission usage descriptions

The generated Info.plist strings must explain the exact user-facing feature for microphone, speech recognition, location, Contacts, Calendar, Reminders, Photos, camera/document scanning, and notifications. Release verification rejects vague advertising/tracking purposes or a permission not reachable from an enabled capability.

## Screenshot plan

Capture owner-approved localized physical-device images for: Home and voice orb; listening; native result list/detail; deterministic compact success; shopping handoff; travel option; appointment; scanner/document; connected account; truthful partial/unavailable result; dark/light appearance; and accessibility scaling. Do not use fabricated prices, availability, bookings, partner connection, or purchase success. Produce current App Store-required device sizes only after checking App Store Connect.

## Public URLs

- Support URL: owner-controlled HTTPS page with contact/support scope and current app version guidance — value pending owner approval.
- Privacy Policy URL: owner/legal-controlled HTTPS policy matching actual data flows and processors — value pending owner/legal approval.

Placeholder or repository URLs must never be submitted as production metadata.

## App Review notes draft

Explain that simple routing is deterministic, optional AI is off until explicitly connected, consequential actions retain confirmation, provider availability may vary, and no private API or cross-app screen automation is used. List every entitlement and reviewer-visible permission trigger. Provide exact navigation to voice/text fallback, connected accounts, privacy/data controls, account deletion, subscription cancellation, scanner, and sample local-only flows. Never describe a handoff as a completed external transaction.

## Review test-account strategy

Use dedicated staging/test accounts with least privilege and synthetic/non-sensitive data only where a reviewer must exercise a connected provider. Credentials are delivered through the approved App Review channel, never source control or screenshots. Each account records provider, permitted scope, expiry/revocation owner, reset steps, and a truthful unavailable fallback. If no lawful reviewer account exists, disclose the limitation and provide locally testable flows; do not simulate provider success.

## Release gates

- Owner selects an available name and approves copy, screenshots, categories, countries, and disclosures.
- Legal owner approves public support/privacy URLs and commerce/affiliate wording.
- Release build privacy report, signing, entitlements, StoreKit products, reviewer accounts, TestFlight, and physical-device flows are verified separately.
- Current Apple documentation and App Review requirements are rechecked immediately before submission.
