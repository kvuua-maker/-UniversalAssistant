# M12 CarPlay and Sensitive Data Policy

Requirements MS-977–981. Status: VERIFIED_LOCAL policy; CarPlay activation is READY_FOR_LIVE_VERIFICATION because it requires owner category selection and an Apple managed entitlement.

Apple's current official documentation says CarPlay applications require a category-specific managed entitlement, Apple review and agreement to the CarPlay Entitlement Addendum. UniversalAssistant currently has no approved CarPlay category or entitlement, so adding a CarPlay scene/template now would be an unverifiable entitlement claim. `PlatformEligibilityPolicy` fails closed independently for audio, communication and navigation; approval for one never enables another. If approved later, UI must use the applicable CarPlay templates, not the phone UI.

Official sources checked 2026-09-02: https://developer.apple.com/documentation/carplay/requesting-carplay-entitlements and https://developer.apple.com/documentation/carplay/.

HealthKit, financial-account and government-identity access are excluded unless both a concrete requirement and explicit owner scope decision exist. Tests verify owner-only, entitlement-only and exact-category gates plus default exclusion of all unapproved sensitive domains. The project entitlements contain none of those capabilities.
