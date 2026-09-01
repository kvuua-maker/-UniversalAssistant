# M4 Commerce Offer Normalization and Ranking

- Normalized offers preserve exact identity evidence, seller identity/quality, availability, Ukraine delivery, ETA, exact purchase URL, provider source and timestamps.
- Total cost is item + shipping + tax + duties + required costs only when every component is known or explicitly estimated; unknown values never become an invented total.
- Freshness is explicit and stale source timestamps are not treated as current.
- Ranking prioritizes exact variant, freshness, availability, Ukraine delivery and seller protections. Affiliate support/commission is deliberately absent from the score.
- Deduplication requires the same provider offer and seller; different sellers or variants remain distinct.

Verification: Development simulator suite passed 63 tests in 17 suites on 2026-09-01.
