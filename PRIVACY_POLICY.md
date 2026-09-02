# UniversalAssistant Privacy Policy — Pre-publication Draft

Last updated: 2026-09-02. This draft matches the current repository implementation and is not a substitute for owner/legal approval or a publicly hosted policy URL.

UniversalAssistant processes commands to provide requested assistant actions. Typed and spoken command content is held for the current interaction and is not included in a wrong-result feedback record. A feedback record contains only a generated diagnostic identifier, the category `wrongResult`, and time, and is retained locally in a bounded protected queue.

With the user's permission, the app may access Apple-managed Contacts, Calendar, Reminders, microphone/speech recognition, location, MapKit, WeatherKit, MusicKit, Sign in with Apple, StoreKit and CloudKit features. Access is requested for the selected feature and can be changed in system settings. Provider OAuth credentials are stored in the iOS Keychain and removed on disconnect; expired or revoked credentials require reauthorization.

When a user requests a live provider result, the minimum query/location/account data needed for that provider may be transmitted over secure transport. Proactive notifications require a device token and minimal payload through Apple Push Notification service. Partner attribution uses pseudonymous references where appropriate and retains auditable conversion/financial evidence. UniversalAssistant does not currently integrate third-party advertising/tracking or analytics SDKs and does not sell personal data.

Retention and deletion follow `DATA_RETENTION.md`. Users can remove local recordings and disconnect credentials; account deletion coordinates assistant-owned cloud data, push tokens, provider connections, proactive jobs and local session state. Legal/financial records may be retained where required and are adjusted rather than erased when audit truth must be preserved.

The current external-service inventory is `DATA_PROCESSOR_INVENTORY.md`. Production regions, subprocessors, public support/privacy contacts, live deletion propagation, and the public policy URL must be completed and approved before App Store release.
