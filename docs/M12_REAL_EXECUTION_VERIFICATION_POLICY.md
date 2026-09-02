# M12 Real Execution Verification Policy

Requirements MS-982–1004. Status: VERIFIED_LOCAL for enforceable policy and repository audit; every unavailable provider/device execution remains READY_FOR_LIVE_VERIFICATION rather than falsely VERIFIED_LIVE.

IntegrationVerificationPolicy is the executable evidence gate. Behavioral tests prove that E3 mocks/internal tests cannot promote an external capability, physical-device claims require E5, a queued handoff requires all four specific fields, and sensitive evidence is rejected. INTEGRATION_STATUS.md, REAL_DEVICE_TEST_MATRIX.md and LIVE_VERIFICATION_QUEUE.json now cover the connected-account, messenger, Apple-domain, Universal Personal Search and CarPlay surfaces.

Repository simulation audit found test fakes and explicit documentation references only; no production provider path reports fake success. Production integrations return typed failure/unavailable state. Maximum-depth decisions are capability-specific: Gmail uses its authorized REST API; Messages keeps final send in MessageUI; consumer messenger history/control is not claimed; Apple domains use public frameworks; personal search invokes every authorized source supplied to it concurrently; CarPlay is not activated without its managed entitlement.

Local verification: 271 iOS tests across 70 suites and 78 backend tests across 22 suites passed on 2026-09-02, including four policy-specific behavioral tests. No real credential, physical iPhone or managed CarPlay entitlement is currently available, so no E4/E5 success is invented.
