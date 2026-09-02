# ADR 0006: Deterministic coordination and bounded AI

- Date: 2026-09-02
- Version: 1
- Context: Simple commands and known multi-provider tasks must remain fast, reproducible and usable during AI outage.
- Decision: Reuse the command router/capability registry to create typed execution plans, execute independent work with bounded Swift concurrency, compose verified facts deterministically, and permit one schema-validated timed AI interpretation only after an explicit unresolved state. AI has no side-effect authority.
- Alternatives considered: AI-first routing, recursive planning and a separate orchestration framework were rejected due to latency, cost, nondeterminism and duplicated architecture.
- Consequences: Deterministically resolvable commands make zero AI calls. Optional AI failure returns a truthful deterministic result and never fabricates live facts.
