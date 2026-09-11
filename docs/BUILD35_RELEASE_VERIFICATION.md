# UniversalAssistant Build 35 Release Verification

- Verification date: `2026-09-11`
- Version/build: `0.1.0 (35)`
- Build-34 systemic repair source HEAD before increment:
  `30a4bfd0e0c2961697d59fdccca8fd2d6809f7fc`
- Release/archive HEAD: `11aff3fb116f05e25d3682537e8bce59caf6c670`
- Archive: `/Users/Shared/UniversalAssistantBuild35.xcarchive`
- IPA: `/Users/Shared/UniversalAssistantBuild35IPA/UniversalAssistant.ipa`
- IPA SHA-256:
  `5a827375441d62847eeb086abf5f1ab03c9cd4e51f68cb0e8fafac3a18f9b99f`
- App Store Connect Delivery UUID:
  `97b73260-fca9-4895-87be-22d313a69a6c`

## Repair and automated gate evidence

- Physical evidence came from TestFlight Build 34 on the owner's iPhone SE
  (2nd generation), `iPhone12,8`, iOS `26.6.2`.
- Crashlytics issue `62da7fe5f9324f7f559c6122e3baf7e1` symbolicated
  two Build-34 fatal events to
  `AppleVoiceAudioCaptureBackend.installTap(_:)`. The trace proved a 48 kHz
  active hardware session followed by a stale explicit 44.1 kHz tap.
- General in-place repairs and their exact physical/targeted evidence are
  recorded in `docs/BUILD34_PHYSICAL_SYSTEMIC_REPAIR.md`.
- Final affected targeted test run: `9/9 PASS`.
- Full iOS official xcresult: `936/936 PASS`, zero failures/skips. This
  includes all shipped Release-root inventory suites, Build-34 systemic
  semantics, voice lifecycle/ownership, Contacts lifecycle/framework,
  messaging, Photos/Files, provider, restaurant, stale-generation and
  Crashlytics side-car tests.
- Production main app + Share Extension compile: PASS.
- `git diff --check`: PASS before the source and release commits.

## Archive, signing, capabilities and symbols

- Fresh Production archive: PASS (`** ARCHIVE SUCCEEDED **`).
- App Store IPA export: PASS (`** EXPORT SUCCEEDED **`); ZIP integrity PASS.
- Bundle IDs: `com.universalassistant.app` and
  `com.universalassistant.app.share`; both contain Build `35`.
- Team: `9V5XXDXF3N`; identity:
  `Apple Distribution: Vladyslav Khomenko (9V5XXDXF3N)`.
- Main profile: `UniversalAssistantAppStore`,
  UUID `a3d6b73f-0bc7-4afd-9d8b-6f7cd7b29d01`, expiry
  `2027-09-06`.
- Share profile: `UniversalAssistantShareAppStore`,
  UUID `7729d5d4-36bb-4a5b-a5c6-6164b3f93dbd`, expiry
  `2027-09-06`.
- Main and nested Share Extension signatures pass strict deep verification.
  `get-task-allow=false` for both.
- Main production entitlements contain production APNs, App Attest,
  WeatherKit, App Group, Sign in with Apple, CloudKit/iCloud and concrete KVS.
  Share Extension contains the matching App Group.
- Required AlarmKit, Apple Music, Calendar, Camera, Contacts, Location,
  Microphone, Photos, Reminders and Speech usage descriptions are embedded.
- Firebase configuration and SDK privacy manifests are embedded.
- Main binary/dSYM UUID:
  `9E0E7786-115E-3A5D-BDA6-0E888DDA261E`.
- Share Extension binary/dSYM UUID:
  `99E0DCAA-BD65-3626-B4A6-E638A90C3CB6`.
- Official Firebase `upload-symbols`:
  `Successfully uploaded Crashlytics symbols` for the Build-35 main dSYM.

## Apple validation and TestFlight processing

- Official `altool` validation through Team API key:
  `VERIFY SUCCEEDED with no errors`.
- Upload: `UPLOAD SUCCEEDED with no errors`; `7,090,626` bytes transferred;
  Delivery UUID `97b73260-fca9-4895-87be-22d313a69a6c`.
- Apple processing: `processingState=VALID`, `import-status=VALID`,
  `build-status=VALID`, `is-on-app-store-connect=true`, Build `35`,
  `APP_STORE_ELIGIBLE`, non-exempt encryption `false`.
- Apple import processing is complete. Assignment/visibility to a particular
  TestFlight tester group is not inferred from transport status.

## Remaining legitimate boundaries

- ShazamKit remains an App-ID/profile owner/Apple boundary.
- Live commercial provider results and transactions require their documented
  credentials/contracts. No live data, availability or booking was fabricated.
- The three recovery/handoff artifacts remain outside the checkout at
  `/Users/Shared/UniversalAssistantRemote` and retain their recorded SHA-256.
- `AUTOMATED VERIFIED` is not `PHYSICAL IPHONE VERIFIED`. Build 35 requires
  a fresh TestFlight retest on the owner's physical `iPhone12,8`.
