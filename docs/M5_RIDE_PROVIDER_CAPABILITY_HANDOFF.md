# M5 Ride Provider Capability and Handoff Registry

Last verified: 2026-09-01 from official provider sources.

| Provider | Live price/ETA/availability | Deep handoff | Status |
|---|---|---|---|
| Uber | Not enabled. Official estimate APIs require registered-app scopes; a deep link itself cannot fetch estimates. | Official `https://m.uber.com/looking` route prefill is documented and requires a client ID. | `credentialRequired` |
| Bolt | No public rider integration contract verified in official consumer/support material. | No documented route-prefill contract verified. | `researched`, disabled |
| Uklon | No public rider integration contract verified in official material. | No documented route-prefill contract verified. | `researched`, disabled |

Primary sources:

- Uber deep-link contract and parameters: https://developer.uber.com/docs/riders/ride-requests/tutorials/deep-links/introduction
- Uber clarification that deep links do not return time/price estimates: https://developer.uber.com/docs/riders/ride-requests/tutorials/deep-links/faq
- Uber estimate scope/API migration reference: https://developer.uber.com/docs/riders/guides/migration-steps
- Bolt official rider ordering flow: https://bolt.eu/en/support/articles/115002296213/
- Uklon official site reviewed for a public integration entry point: https://uklon.com.ua/

Implementation truth:

- `RideProviderRegistry` cannot execute a merely researched provider or use it as comparison evidence.
- `UberRideHandoffBuilder` creates only the documented HTTPS host/path, requires a runtime client ID, validates both coordinates and user-visible names/addresses, and never represents handoff as a booked ride.
- No private endpoint, scraped quote, inferred vehicle availability or undocumented custom URL scheme is used.

Verification: Development simulator build and all 103 iOS tests in 25 suites passed on 2026-09-01.

Owner-only gate: register/approve the UniversalAssistant application in Uber Developer Dashboard and provide the public client ID through approved runtime configuration before enabling the handoff in production. Estimate scopes or ride booking require their own provider approval and OAuth work. Bolt/Uklon remain disabled until an official integration contract is provided or published.
