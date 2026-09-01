# M4 Grocery Two-Store and Route-Aware Optimization

- Optimization is bounded to 12 candidate stores and evaluates only one- or two-store combinations.
- Every requested basket item must have an exact or equivalent-quantity quote with a real same-currency line price. Substitutes, unavailable and unverified items cannot silently complete a plan.
- Quotes have an explicit 15-minute default freshness bound; stale input fails rather than becoming a current recommendation.
- Only stores actually used by item assignments contribute detour distance/time and travel cost.
- Detour is constrained by an explicit policy budget. Travel cost is an explicit same-currency input derived outside the optimizer; the engine does not invent a monetary value for user time.
- The selected plan minimizes item subtotal plus known/estimated travel cost. Stable tie-breaking prefers fewer stores, lower detour and then stable store identifiers.

Verification: Development build and simulator suite passed 90 tests in 22 suites on 2026-09-01. Live route measurements and supermarket quotes remain provider/runtime evidence inputs.
