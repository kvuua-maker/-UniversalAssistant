# M11 Server Data Migration Core

Requirement: MS-804. Status: VERIFIED_LOCAL.

The production implementation is a file-backed staging runner: it loads real encoded schema state, requires a contiguous version plan, creates an atomic protected pre-migration backup, applies and validates every step, commits atomically, and restores the exact backup on any transform/validation/plan failure. The runner rejects production-mode execution so an untested migration cannot bypass staging.

Behavioral tests prove successful restart persistence, exact rollback after validation failure, and the staging-only gate. A real production database dataset/host remains part of the existing deployment live-verification queue; no local work is deferred to it. Verification: 75 backend tests across 21 suites passed and the Development iOS simulator build succeeded on 2026-09-02.
