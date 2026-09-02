# ADR 0002: Local persistence and migration

- Date: 2026-09-02
- Version: 1
- Context: Assistant-owned aliases, history, feedback, allowance and sync state must survive restart without replacing Apple-owned system records.
- Decision: Use small Codable records in Application Support, atomic writes with complete file protection, explicit schema envelopes, deterministic migration and corruption quarantine. Secrets use Keychain instead.
- Alternatives considered: Core Data/SwiftData would add model and migration machinery not justified by the current bounded records; UserDefaults is inappropriate for protected structured state.
- Consequences: Persistence stays dependency-free and testable with temporary directories. Large/shared server datasets must use a separately selected durable store rather than loading app files into memory.
