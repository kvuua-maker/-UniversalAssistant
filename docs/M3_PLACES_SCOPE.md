# M3 Places

- Extensible `PlaceProvider` protocol and complete normalized place model with source, timestamp, verification, coordinates, distance, travel time, contact/site, rating/reviews, hours/open status, and price level.
- Apple MapKit adapter uses bounded regional `MKLocalSearch`, stable place IDs, current iOS 26 location/address APIs, and an iOS 18 compatibility path.
- Unsafe/suspicious location, empty query, excessive radius, and excessive result limits are rejected before provider work.
- Aggregator runs at most four providers concurrently with per-provider timeout and failure-isolated partial results.
- Dedup uses same-provider stable IDs or conservative cross-provider name/category/30 m evidence; different stable IDs remain distinct.
- Stable user-first ranking uses relevance, requested category, open status, distance, rating evidence, and verification — never provider monetization.

Official API evidence verified 2026-09-01:

- https://developer.apple.com/documentation/mapkit/mklocalsearch/request
- https://developer.apple.com/documentation/mapkit/mkmapitem

Verification: Development simulator suite passed 47 tests in 13 suites. Live MapKit data remains `LIVE_TEST_REQUIRED`.
