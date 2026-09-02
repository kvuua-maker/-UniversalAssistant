# M11 App Version Support Policy

Requirements: MS-801–MS-802. Status: VERIFIED_LOCAL.

- The backend supports the current iOS minor release and two prior minor release lines by default. The count is explicit configuration, not scattered branching.
- A supported older version receives an update-available response, never a forced update for convenience.
- Raising the minimum version requires one typed reason: critical service compatibility, security, or legal.
- Malformed versions, reversed ranges, and an unexplained minimum-version cutoff fail closed.
- Production minimum/current values remain Remote Config/deployment configuration and do not require rewriting core logic.

Evidence: `AppVersionSupportPolicy.swift` and `AppVersionSupportPolicyTests.swift`; 72 backend tests across 20 suites passed and the Development iOS simulator build succeeded on 2026-09-02.
