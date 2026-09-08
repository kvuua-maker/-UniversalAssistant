# Build 28 release verification

- Product source/archive HEAD: `bb34ead`.
- Version/build: `0.1.0 (28)`.
- Archive: `/Users/Shared/UniversalAssistantBuild28.xcarchive` — `ARCHIVE SUCCEEDED`.
- IPA: `/Users/Shared/UniversalAssistantBuild28IPA/UniversalAssistant.ipa`.
- IPA SHA-256: `e9f03617a2219c4374f241575662dc9d49f5fc3fc766978377f7cd8dddb3a233`.
- Main and Share Extension: Apple Distribution, Team `9V5XXDXF3N`; `codesign --verify --deep --strict` passed.
- Profiles: `UniversalAssistantAppStore`, `UniversalAssistantShareAppStore`.
- Main entitlements: production APNs, production App Attest, WeatherKit, App Group, Sign in with Apple, CloudKit, concrete KVS, `get-task-allow=false`.
- Share entitlement: App Group and `get-task-allow=false`.
- Physical archive and IPA `NSAlarmKitUsageDescription`: `UniversalAssistant creates alarms and timers only when you explicitly request them.`
- Apple response: `Upload succeeded. Uploaded package is processing.`
- TestFlight state at evidence capture: processing; availability not yet proven.
- Build 29 was not created. Automated verification is not physical iPhone verification.
