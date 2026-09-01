# M1 Command Core Scope Pack

- Task: M1-COMMAND-CORE
- Requirements: 61–70, 72, 79–116, 521–524, 1518–1525, 1583
- Capability: deterministic multilingual text → validated `StructuredCommand`
- Path: native Swift deterministic lexicons, token/regex extraction and bounded structured context
- Depth/evidence: local E3
- Acceptance: recognize representative Ukrainian/Russian/English/German/French intents; preserve brands; extract price, size and requested app; resolve safe short follow-ups; return `unknown` rather than guess
- Failure cases: empty/unsupported input and ambiguous context remain unresolved
- Stop condition: iOS project builds and all command-core tests pass
