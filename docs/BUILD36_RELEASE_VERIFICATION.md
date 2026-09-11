# UniversalAssistant Build 36 Release Verification

- Verification date: `2026-09-11`
- Version/build: `0.1.0 (36)`
- Verified systemic-repair source HEAD before increment: `38c23087a77074b20b9e7b58eca88be29953d9b5`
- Release/archive HEAD: `5562bab931967700342fa80a97c5b16a04adaafb`
- Archive: `/Users/Shared/UniversalAssistantBuild36.xcarchive`
- IPA: `/Users/Shared/UniversalAssistantBuild36IPA/UniversalAssistant.ipa`
- IPA SHA-256: `f63bf6b7f82ba8e24154d3aaa3945f09587a73fc5b5ddd2e355e0dc5ff9a5efe`
- App Store Connect Delivery UUID: `70b89703-5974-429c-8c46-4947292a7fd9`

## Source and automated gate boundary

- Build 36 contains only the already verified systemic repair plus build-number metadata.
- No functional source changed after the final Build-35 repair gates.
- Previously completed automated gates were not repeated: full iOS `939/939 PASS`, Release-root `46/46 PASS`, affected/protected `139/139 PASS`, ASan/TSan/MainActor checks and Production compile PASS.
- Build 37 was not created.

## Archive, signing and symbols

- Production archive: `ARCHIVE SUCCEEDED`.
- App Store export: `EXPORT SUCCEEDED`; IPA ZIP integrity PASS.
- Bundle version `36`; marketing version `0.1.0`.
- Main and nested Share Extension signatures pass strict verification.
- Signing identity: `Apple Distribution: Vladyslav Khomenko (9V5XXDXF3N)`.
- Main profile: `UniversalAssistantAppStore`, UUID `a3d6b73f-0bc7-4afd-9d8b-6f7cd7b29d01`, expires `2027-09-06`, `get-task-allow=false`.
- Share profile: `UniversalAssistantShareAppStore`, UUID `7729d5d4-36bb-4a5b-a5c6-6164b3f93dbd`, expires `2027-09-06`, `get-task-allow=false`.
- Main binary/dSYM UUID match: `053E2CEA-ABEE-33ED-921A-4C1B34C084AE`.
- Share Extension binary/dSYM UUID match: `99E0DCAA-BD65-3626-B4A6-E638A90C3CB6`.
- Official Firebase upload: `Successfully uploaded Crashlytics symbols`.

## Apple validation, upload and processing

- API-key validation: `VERIFY SUCCEEDED with no errors`.
- Upload: `UPLOAD SUCCEEDED with no errors`; `7,124,669` bytes; Delivery UUID `70b89703-5974-429c-8c46-4947292a7fd9`.
- Apple processing: `processingState=VALID`, `import-status=VALID`, `build-status=VALID`, `is-on-app-store-connect=true`, Build `36`, `APP_STORE_ELIGIBLE`, non-exempt encryption `false`.
- Import processing is complete. Assignment/visibility to a particular TestFlight tester group is not inferred from transport status.

## Boundary

- `AUTOMATED VERIFIED` is not `PHYSICAL IPHONE VERIFIED`.
- Build 36 requires physical TestFlight verification on the owner's iPhone.
