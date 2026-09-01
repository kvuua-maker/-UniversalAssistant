# M3 AccurateLocationEngine

- One central foreground-only Core Location engine; no background/always permission.
- Six required quality states: precise, good, approximate, poor, suspicious, unavailable.
- Validator uses real horizontal accuracy, timestamp, reduced-accuracy authorization, coordinate validity, prior accepted sample, elapsed time, and physical jump plausibility.
- Suspicious/unavailable samples are prohibited for location actions; poor/suspicious samples receive at most two bounded recovery attempts.
- One-shot requests time out after 10 seconds; accuracy is raised only for nearby/navigation/emergency purposes.
- Manual location is explicitly tagged and remains usable offline without being represented as device GPS.

Official API evidence verified 2026-09-01:

- https://developer.apple.com/documentation/corelocation/cllocationmanager
- https://developer.apple.com/documentation/corelocation/cllocationmanager/accuracyauthorization
- https://developer.apple.com/documentation/bundleresources/information-property-list/nslocationwheninuseusagedescription

Verification: Development simulator suite passed 41 tests in 11 suites. Permission, reduced/full accuracy, physical movement, timeout, and recovery remain `DEVICE_TEST_REQUIRED`.
