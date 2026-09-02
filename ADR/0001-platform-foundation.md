# ADR 0001: Platform foundation

- Date: 2026-09-01
- Version: 1
- Context: V1 is iPhone-only and requires current public Apple frameworks with a lightweight local-first core.
- Decision: minimum iOS 18, Swift 6, SwiftUI/Observation, system-first data ownership, dependency-free Swift backend skeleton.
- Alternatives considered: older iOS target increases compatibility branches; third-party project generators/dependencies add bootstrap and supply-chain cost at M0.
- Consequences: supports modern App Intents and concurrency while retaining iPhone SE-class hardware coverage for later measurement.
