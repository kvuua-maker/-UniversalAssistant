# Deterministic Coordination Acceptance

The canonical acceptance matrix is covered without putting AI on the deterministic critical path:

- simple deterministic routing: `DeterministicExecutionPlanTests.simpleKnownCommandUsesFastPathWithZeroAI`;
- concurrent multi-module work: `CoordinationAcceptanceTests.travelExecutesCalendarLocationWeatherTransportAndHotelWithZeroAI`;
- complete travel dependency flow with Calendar, location, Weather, Transport and Hotel: the same integration test, with AI count zero;
- exactly one schema-validated unresolved interpretation: `BoundedAIInterpretationTests.unresolvedCaseMakesExactlyOneValidatedCall`;
- AI timeout/unavailable deterministic fallback: `BoundedAIInterpretationTests.timeoutReturnsDeterministicFallbackWithoutHanging`;
- truthful provider partial failure: `CoordinationAcceptanceTests.providerFailureReturnsTruthfulPartialResultWithoutInventedValue`;
- hard constraints: `TravelPlanEngineTests` rejects deadline/budget/stay violations;
- obsolete parallel work cancellation: `CoordinationAcceptanceTests.sufficientResultCancelsObsoleteParallelWork`.

`DeterministicPlanExecutor` executes typed dependency groups in order, runs independent operations concurrently with a strict bound, applies per-operation timeout, preserves typed unavailable outcomes, and supports cooperative cancellation once a sufficient result exists. Provider errors are reduced to typed states rather than copied into user-visible telemetry or fabricated values.
