# M3 Weather Context and Location Recovery

- `WeatherProvider` normalizes current, hourly and daily weather without exposing provider payloads to UI or command layers.
- `AppleWeatherKitProvider` uses Apple's native WeatherKit service on demand; it records source, fetch time, context and device/manual location provenance.
- Requests reject suspicious/unavailable location, validate forecast bounds, and enforce a bounded provider timeout.
- Weather context explicitly distinguishes current location, manual location, destination, event and travel use.
- Location recovery retries poor/suspicious/unavailable readings or offers an explicit manual context; denied permission routes to Settings/manual context. Suspicious coordinates are never used.
- No mock value is presented as production weather. WeatherKit live availability and attribution remain real-device/entitlement verification gates.

Official evidence checked 2026-09-01:

- https://developer.apple.com/weatherkit/
- https://developer.apple.com/documentation/weatherkit/weatherservice
- Xcode 26.6 iOS SDK WeatherKit public Swift interface (`WeatherService.weather`, current/hourly/daily forecast types).

Verification: Development simulator suite passed 55 tests in 15 suites. Live WeatherKit response, attribution and entitlement remain `LIVE_DEVICE_TEST_REQUIRED`.
