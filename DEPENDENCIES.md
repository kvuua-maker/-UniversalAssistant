# Dependency Inventory and Policy

Last audited: 2026-09-10.

## Runtime inventory

| Component | Version/source | Purpose | License | Privacy implications | Update status |
| --- | --- | --- | --- | --- | --- |
| Apple platform SDK frameworks | Xcode SDK selected by the checked-in project; minimum iOS 18 | SwiftUI, system capabilities and Apple service boundaries | Apple SDK agreement | Permission- and entitlement-gated system data; covered by the privacy manifest and capability-specific policy | Reviewed with every Xcode/iOS baseline change |
| Swift standard library and Foundation | Swift 6 toolchain selected by Xcode/SwiftPM | App and backend language/runtime primitives | Toolchain/platform distribution terms | No additional third-party processor | Reviewed with every toolchain baseline change |
| Vapor | SwiftPM 4.122.1, pinned by `Backend/Package.resolved` | Existing `UniversalAssistantServer` HTTP transport, localhost binding and typed routes | MIT | Receives only schema-validated diagnostic metadata through the owner VPS; no analytics SDK or external processor | Security and release review required before updates |
| Swift Crypto | SwiftPM 3.15.1, pinned by `Backend/Package.resolved` | Cross-platform cryptography and App Attest assertion verification | Apache-2.0 | Cryptographic processing is local to the owner VPS; no data recipient | Security and release review required before updates |
| AppAttest (Ian Sampson) | Git revision `f4fc1ea12c712d6833905d9c11c73c1601ae4001`, pinned by `Backend/Package.resolved` | Server-side verification of Apple's App Attest certificate chain, nonce, app identity and assertions | MIT | Processes Apple attestation objects and public device-bound key state only; no transcript/audio/user content | Revision is fixed; re-audit before change |
| Firebase Apple SDK (`FirebaseCore`, `FirebaseCrashlytics`) | SwiftPM `12.19.0`, exact version in `UniversalAssistant.xcodeproj` and resolved workspace lock | Initializes the registered Firebase app and sends fatal Crashlytics reports plus one bounded diagnostic non-fatal trace per opted-in TestFlight command; official Crashlytics script uploads dSYM files | Apache-2.0 | Firebase/Google receives crash metadata, custom keys/logs and, only while detailed diagnostics consent is enabled, the final and normalized command transcript; credentials, tokens and raw audio are excluded/redacted | Exact version; review Firebase release notes, privacy manifests, data disclosure and symbol-upload behavior before updates |

The iOS app target contains only the inventoried Firebase Apple SDK products above; the Share Extension has no Firebase product dependency. Firebase's SwiftPM-resolved transitive open-source components are locked by `Package.resolved` and distributed under their upstream license terms. The backend uses only the three inventoried source packages above; all dependencies are reproducibly pinned. There are no copied provider/catalog media assets. Provider imagery is loaded only from runtime provider URLs and is never bundled as copied catalog content.

## First-party bundled content

| Asset | Provenance | Rights/use | SHA-256 |
| --- | --- | --- | --- |
| `UniversalAssistant/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png` | Generated specifically for UniversalAssistant with OpenAI image generation from the owner-approved purple/blue orb visual canon on 2026-09-04 | First-party project app icon; permitted for product and App Store distribution; no third-party marks or copied provider content | `b2ca19316a2ad5483b96bd4fe63ba97c373fb3d1a964d28d1526cc1f68e8c113` |

## Admission, pinning and update policy

- Prefer Apple/native facilities. A new dependency needs a documented material risk or maintenance benefit and an ADR when consequential.
- SwiftPM dependencies, if admitted later, must use a reproducible exact version or checked-in resolved lock appropriate to the deployable target. Unbounded branches and floating revisions are prohibited for release builds.
- Dependency changes are reviewed in a dedicated change, built and tested in CI/staging, and assessed for release notes, license compatibility, privacy manifests/data processing, security advisories, binary provenance and minimum-platform impact before promotion.
- Critical dependencies are never auto-upgraded directly into production. Emergency security updates still require focused regression evidence and an auditable release decision.
- Commercial App Store compatibility and required attribution/notices must be recorded here before a third-party component or content asset is shipped. Incompatible or unverified licenses are rejected.

## Content copyright policy

UniversalAssistant uses code-native layout, SF Symbols and localized text owned by the project. Protected retailer, fashion or business images/catalogs must not be copied into the binary. Official provider data may be rendered only within its terms and with source/freshness evidence; when reuse is not permitted, the app opens the official source. Any future bundled asset requires provenance, license, permitted commercial use and attribution recorded in this inventory before merge.
