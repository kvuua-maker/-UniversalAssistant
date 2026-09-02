# M8 CloudKit Sync Core

- Requirements: 657–659, 705, 708, 817.
- Local data remains immediately usable and primary; cloud failure returns an explicit local-only outcome.
- Stable IDs collapse local/remote versions to one record. Latest modification wins; deletion wins an equal-time conflict; device ID provides a reproducible final tie-break.
- Tombstones prevent deleted data from reappearing and conflicts never replay external actions.
- The transport is protocol-bounded so reconciliation is testable without a CloudKit account.
- External gate: the production CloudKit container identifier, Apple capability provisioning and multi-device physical tests require owner Apple Developer configuration; no container name is invented.
- Local verification: 177 iOS tests across 44 suites and 29 backend tests across 7 suites passed on 2026-09-02.
- Exit state: `SUCCESS` for the provider-neutral local E3 reconciliation core.
