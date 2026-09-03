# Owner Test Queue

Authoritative source: `LIVE_VERIFICATION_QUEUE.json`. Human-readable complete index: `docs/LIVE_VERIFICATION_QUEUE_REPORT.md`.

There are **59** precise live/physical/provider verification items. None is represented as PASS or VERIFIED_LIVE. Every item records its requirement ID, provider/system, missing dependency, dependency owner, local evidence, exact live action, expected result, timestamps and empty completion evidence. Items remain `READY_FOR_LIVE_VERIFICATION` and do not block independent local work.

No immutable signed owner-test build is currently registered, so no test is requested now. When a signed delivery channel/device/provider credential becomes available, select matching queue items, execute only their stated live action, record read-back evidence, and advance the relevant requirement only after the required E4/E5/E6 result.
