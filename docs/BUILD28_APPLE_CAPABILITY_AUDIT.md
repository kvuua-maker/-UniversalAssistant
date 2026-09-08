# Build 28 Apple capability audit

Audit date: 2026-09-08. Deployment target: iOS 18.0. This is source/account evidence, not physical iPhone verification.

| Family | Current public mechanism | Project/account state | Classification | Required action |
|---|---|---|---|---|
| Speech recognition | `SFSpeechRecognizer`, `SFSpeechAudioBufferRecognitionRequest`; `contextualStrings` is a short vocabulary hint; `requiresOnDeviceRecognition` is valid only where `supportsOnDeviceRecognition` is true | Speech and microphone usage descriptions present; session-owned lifecycle implemented | REQUIRED_ENABLED | Preserve runtime availability checks; do not treat vocabulary hints as semantic parsing |
| Alarm/timer | AlarmKit on its public availability range | Usage description present; physically proven in Build 25/26 | REQUIRED_ENABLED | Preserve availability gate and truthful older-OS behavior |
| Weather | WeatherKit | `com.apple.developer.weatherkit=true` | REQUIRED_ENABLED | Preserve WeatherKit structured route |
| App Attest | App Attest entitlement | Production build setting resolves production environment | REQUIRED_ENABLED | Preserve |
| APNs | `aps-environment` | Production build setting resolves production environment | REQUIRED_ENABLED | Preserve |
| App Group | App Groups | Main and Share Extension use `group.com.universalassistant.shared` | REQUIRED_ENABLED | Preserve and reverify profiles at release gate |
| iCloud | CloudKit + concrete KVS | Main entitlement contains CloudKit and concrete team KVS identifier | REQUIRED_ENABLED | Preserve; no unrelated iCloud service expansion |
| Sign in with Apple | Sign in with Apple capability | Main entitlement present | REQUIRED_ENABLED | Preserve |
| Shazam catalog recognition | ShazamKit framework plus ShazamKit service enabled for the App ID | No ShazamKit authorization appears in current executable entitlements/profile evidence; production executor therefore returns a truthful capability-required result | REQUIRED_OWNER_ACTION | In Certificates, Identifiers & Profiles, enable ShazamKit for `com.universalassistant.app`; regenerate the matching App Store profile. Then implement and live-test catalog recognition before claiming availability |
| Share Extension | Public share extension + App Group | Target and entitlement present | REQUIRED_ENABLED | Preserve and physically retest extension-to-host lifecycle |
| App Store Connect automation | App Store Connect API JWT or authenticated Xcode/Transporter workflow | No repository credential is allowed or present | REQUIRED_OWNER_ACTION | Account Holder first enables API access if unavailable; Account Holder/Admin creates a least-privilege key, or eligible user creates an individual key; store `.p8` outside Git and provide key ID/issuer through secure local configuration |

## Official authority

- Apple Speech `contextualStrings`: short app-specific phrases, preferably one or two words, maximum 100.
- Apple Speech `supportsOnDeviceRecognition`: `requiresOnDeviceRecognition` can be honored only when support is reported.
- Apple ShazamKit: catalog recognition requires enabling the ShazamKit service for the App ID in Certificates, Identifiers & Profiles.
- Apple App Store Connect API: Account Holder requests initial access; team keys require Account Holder/Admin; private keys are downloadable once and must be protected.

No private API, undocumented system URL scheme, or wildcard entitlement was introduced by this audit.
