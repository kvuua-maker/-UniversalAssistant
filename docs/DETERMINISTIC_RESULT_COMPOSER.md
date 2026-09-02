# Deterministic Result Composer

- Composes primary answer, priority-stable verified facts, typed actions and warnings with zero AI calls.
- A verified value requires its source and observation time. Unknown/unavailable facts cannot carry placeholder or invented values.
- Action destinations are typed and validated; clarification/retry remain destination-free.
- Existing domain-specific card presenters remain intact and can consume this shared result contract rather than being duplicated.
- Local verification: 191 iOS tests across 48 suites and 29 backend tests across 7 suites passed on 2026-09-02.
- Exit state: `SUCCESS` at local E3.
