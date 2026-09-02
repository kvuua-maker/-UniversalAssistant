# Dependency Inventory and Policy

Last audited: 2026-09-02.

## Runtime inventory

| Component | Version/source | Purpose | License | Privacy implications | Update status |
| --- | --- | --- | --- | --- | --- |
| Apple platform SDK frameworks | Xcode SDK selected by the checked-in project; minimum iOS 18 | SwiftUI, system capabilities and Apple service boundaries | Apple SDK agreement | Permission- and entitlement-gated system data; covered by the privacy manifest and capability-specific policy | Reviewed with every Xcode/iOS baseline change |
| Swift standard library and Foundation | Swift 6 toolchain selected by Xcode/SwiftPM | App and backend language/runtime primitives | Toolchain/platform distribution terms | No additional third-party processor | Reviewed with every toolchain baseline change |

There are no third-party runtime packages, SDKs, binary frameworks or copied media/catalog assets in the current repository. `Backend/Package.swift` has no external package declaration, and the Xcode targets have empty package-product dependency lists. Provider imagery is loaded only from runtime provider URLs and is never bundled as copied catalog content.

## Admission, pinning and update policy

- Prefer Apple/native facilities. A new dependency needs a documented material risk or maintenance benefit and an ADR when consequential.
- SwiftPM dependencies, if admitted later, must use a reproducible exact version or checked-in resolved lock appropriate to the deployable target. Unbounded branches and floating revisions are prohibited for release builds.
- Dependency changes are reviewed in a dedicated change, built and tested in CI/staging, and assessed for release notes, license compatibility, privacy manifests/data processing, security advisories, binary provenance and minimum-platform impact before promotion.
- Critical dependencies are never auto-upgraded directly into production. Emergency security updates still require focused regression evidence and an auditable release decision.
- Commercial App Store compatibility and required attribution/notices must be recorded here before a third-party component or content asset is shipped. Incompatible or unverified licenses are rejected.

## Content copyright policy

UniversalAssistant uses code-native layout, SF Symbols and localized text owned by the project. Protected retailer, fashion or business images/catalogs must not be copied into the binary. Official provider data may be rendered only within its terms and with source/freshness evidence; when reuse is not permitted, the app opens the official source. Any future bundled asset requires provenance, license, permitted commercial use and attribution recorded in this inventory before merge.
