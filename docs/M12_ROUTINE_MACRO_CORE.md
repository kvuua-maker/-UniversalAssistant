# M12 Routine / Macro Core

Status: `VERIFIED_LOCAL`
Canonical requirements: MS-1057–MS-1063

## Production implementation

- `RoutineMacroEngine` compiles supported natural routine phrases into typed `RoutineTrigger`, `RoutineCondition`, and `RoutineAction` records.
- Actions reference existing `ExecutionCapability` values and execute through `DeterministicPlanExecutor`; capability behavior is not duplicated.
- The executor preserves dependency order, runs independent steps concurrently with its bounded concurrency and timeout policy, propagates cancellation, and reports honest partial failures.
- `RoutineMacroStore` persists structured, editable, enable/disable/delete-capable routines using atomic complete-file-protection storage.
- `RoutineExecutionLedger` durably claims a bounded event key before execution, preventing repeated consequential work across retries/restarts.
- Per-action permissions and explicit confirmation for consequential actions are enforced before invoking the capability operation. Missing authorization becomes a typed unavailable outcome; unrelated local/offline actions continue.
- Graph validation rejects cycles, duplicate action IDs, empty routines, and overlarge definitions. Since actions can reference capabilities but cannot invoke another routine, recursive macro loops cannot be encoded.
- Deterministic Ukrainian creation covers the canonical work route/travel-time/first-meeting scenario and the home/store-along-route scenario. Unsupported wording fails honestly for clarification instead of creating an opaque guessed macro.

## Behavioral evidence

`UniversalAssistantTests/RoutineMacroEngineTests.swift` verifies:

1. natural language compiles to typed actions and dependencies;
2. persistence plus edit/disable/delete across a store restart;
3. independent route/calendar work runs concurrently while dependent composition waits;
4. permission denial and missing confirmation are isolated partial failures;
5. identical event execution is idempotent;
6. cyclic graphs are rejected and cancellation becomes a cancelled outcome.

Verification on 2026-09-02:

- targeted Routine suite: 5 tests, 0 failures;
- full iOS regression: 306 Swift Testing tests / 76 suites plus 5 XCTest routine tests, 0 failures, `** TEST SUCCEEDED **`;
- full backend regression: 79 tests / 22 suites, 0 failures;
- AI invocation count remains zero for routine execution.

No Routine/Macro requirement needs a provider-specific live check: individual capability live verification remains tracked by its existing queue item and is not falsely inherited as routine success.
