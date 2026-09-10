# UniversalAssistant Build 32 Release Verification

- Verification date: `2026-09-10`
- Version/build: `0.1.0 (32)`
- Firebase/local diagnostics source HEAD before increment: `ab8993067172c31fb8598b20aabc1155009a4021`
- Release/archive HEAD: `4215f69d92ef777719df423d3424107c50b500b2`
- Archive: `/Users/Shared/UniversalAssistantBuild32.xcarchive`
- IPA: `/Users/Shared/UniversalAssistantBuild32IPA/UniversalAssistant.ipa`
- IPA SHA-256: `995bf21a0e41b5ba3281d2a6bc44697b7c964123f5b35ffbcff757fc7a1c1d8f`
- Upload attempt diagnostics: `/Users/Shared/UniversalAssistantBuild32Upload/Build32UploadAttempt1.xcdistributionlogs`

## Firebase Crashlytics integration evidence

- Official Firebase Apple SDK `12.19.0` is exact-pinned by SwiftPM; the app links only `FirebaseCore` and `FirebaseCrashlytics`, while Share Extension links neither.
- Registered Firebase app: project `universalassistant-d23ec`, bundle `com.universalassistant.app`, app ID `1:209684650216:ios:1fdab1606235f9a758915d`.
- `GoogleService-Info.plist` is embedded in the production app and matches the registered bundle/app IDs.
- `FirebaseApp.configure()` runs in the real Production startup path before `ProductionAssistantComposition` construction.
- Existing request/session/generation and ordered local diagnostics are reused through `CrashlyticsDiagnosticBridge`; no second request identity or VPS backend was created.
- Firebase Console real read-back PASS for request `49C8F2CC-582E-4AD2-BF53-0946BDDCEF98`: normalized text, capability `deviceAction`, system-first true, generic web false with reason, executor, PRE/POST, result `execution_failed`, terminal `ERROR`, elapsed time and ordered logs are visible.
- Full spoken transcript collection is implemented and covered by focused tests, but cannot be called physical PASS on this Mac because no real microphone input is available. It requires Build 32 owner TestFlight verification.
- The simulator fatal signal report was captured locally and processed on relaunch; the supplied Firebase screenshot does not expose the issue type, so server-side fatal classification remains physical Build 32 evidence rather than a claimed PASS.
- Terminal non-fatal contract: maximum one `UA_DIAGNOSTIC_COMMAND_TRACE` per request.
- The prior VPS/Linux diagnostics deployment path remains CLOSED for this task. Its pre-existing WIP is preserved as `stash@{0}: preserve CLOSED VPS diagnostics WIP before Build 32` and is not included in the archive.

## dSYM and symbolication readiness

- Main binary and dSYM UUID match: `C129FA17-3F3A-306E-ADD5-D20CD5DC659C` (`arm64`).
- Share Extension binary and dSYM UUID match: `99E0DCAA-BD65-3626-B4A6-E638A90C3CB6` (`arm64`).
- Official Firebase `upload-symbols` result for the Build 32 main dSYM: `Successfully submitted symbols for architecture arm64` and `Successfully uploaded Crashlytics symbols`.
- Exported IPA contains both symbol records under `Symbols/`.

## Physical artifact verification

- Fresh Production archive: PASS (`** ARCHIVE SUCCEEDED **`).
- App Store IPA export: PASS (`** EXPORT SUCCEEDED **`).
- IPA ZIP integrity: PASS.
- Bundle IDs: `com.universalassistant.app`, `com.universalassistant.app.share`.
- Team ID: `9V5XXDXF3N`.
- Identity: `Apple Distribution: Vladyslav Khomenko (9V5XXDXF3N)`.
- Certificate SHA-1: `0F0B453862D200E7020FB8B11E5C9DF855F094F5`.
- Profiles: `UniversalAssistantAppStore` (`a3d6b73f-0bc7-4afd-9d8b-6f7cd7b29d01`) and `UniversalAssistantShareAppStore` (`7729d5d4-36bb-4a5b-a5c6-6164b3f93dbd`), valid through `2027-09-06`.
- Main and nested Share Extension signatures: PASS (`codesign --verify --deep --strict` and nested strict verification).
- `get-task-allow=false`: PASS for main app and Share Extension.
- Main entitlements: production APNs, App Attest, WeatherKit, App Group, Sign in with Apple, CloudKit/iCloud and concrete KVS: PASS.
- Share Extension App Group `group.com.universalassistant.shared`: PASS.
- Required microphone, Speech, Contacts, Calendar, Reminders, Camera, Photos, Location, Apple Music and AlarmKit usage descriptions: present.
- Firebase and transitive package privacy manifests are present in the exported IPA.

## Automated evidence

- Crashlytics focused integration: `5/5 PASS`.
- Voice ownership and dependency/license protected targeted suites: `7/7 PASS`.
- Final exact dependency/license allowlist assertions: `2/2 PASS`.
- Full iOS arm64 Simulator: `891/891 PASS` in 154 suites.
- Development compile: PASS.
- Production Simulator compile: PASS.
- Production device archive compile/sign: PASS.
- `git diff --check`: PASS.
- Initial full multi-architecture Simulator attempt failed before assertions because Firebase static SwiftPM products were arm64 while Xcode also attempted x86_64. This was a test-infrastructure architecture mismatch, not a production source failure; the materially different arm64 run reached assertions and passed 891/891.

## Apple upload state

Attempt 1 did not reach Apple validation or package transfer. Xcode returned:

- `Failed to Use Accounts`
- `App Store Connect access for “9V5XXDXF3N” is required. Ensure that your Apple Account usernames and passwords are correct in Accounts settings.`
- `Failed to find an account with App Store Connect access for team ... teamID=9V5XXDXF3N, teamName=(null)`

The verified archive and IPA must be reused. Rebuild, rearchive, build-number increment, and Build 33 are prohibited for this retry.

## Preserved recovery artifacts

The three intentional recovery/handoff files remain outside the active checkout at `/Users/Shared/UniversalAssistantRemote` with unchanged SHA-256:

- `UNIVERSALASSISTANT_DISASTER_RECOVERY.md`: `5b25e2d9d28eeb01bc2f4f935dcbb4722424631bfa070794106abda22f392c43`
- `UNIVERSALASSISTANT_FULL_CONTEXT_HANDOFF.md`: `8c5c7dbe1dcc7a1a7d88a338a1cd29b7101400168dec86e7ea0cd8e10672efe9`
- `UNIVERSALASSISTANT_RECOVERY_MANIFEST`: `94eeb81f67d54ee15d1ce688743fbf0a8a3cd07a2b4d7c823bc15fbc3a130f71`

## Exact continuation

In Xcode → Settings → Accounts, reauthenticate the Apple Account and verify that Team `9V5XXDXF3N` is displayed with App Store Connect access. Then retry only upload of the existing Build 32 archive using `/Users/Shared/UniversalAssistantBuild32Upload/UploadOptions.plist`, capture the exact Apple response, and check processing/TestFlight availability. Do not rebuild, rearchive, increment the build, or create Build 33.

`AUTOMATED VERIFIED` is not `PHYSICAL IPHONE VERIFIED`. Build 32 must be installed through TestFlight and physically exercised before Firebase fatal/full spoken-transcript collection is called verified.
