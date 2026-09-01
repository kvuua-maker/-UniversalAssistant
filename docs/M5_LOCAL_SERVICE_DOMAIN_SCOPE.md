# M5 Local Service Domain and Safe Handoff

- The command engine recognizes local-service intent and typed categories for towing, plumbing, locksmith, electrician, cleaning, car/tire service, dentist, veterinary and courier requests across the V1 language set where deterministic terms are available.
- `LocalServiceRequest` requires a validated safe location and converts the request into the existing bounded places pipeline with a 10 km radius and 12-result limit.
- `LocalServiceHandoffPlanner` permits direct ordering only with provider-sourced availability evidence and an exact HTTPS booking path.
- When direct ordering is not proven, the shortest useful fallback is selected in order: callable provider phone, exact official service page, Apple Maps destination. Fallbacks never claim current availability.
- Prices and availability remain explicit evidence-bearing values. An unverified quote cannot become a live availability or completed-order claim.
- The service vertical reuses the existing command, location, places and native result-routing architecture; it introduces no eager startup/network work or provider credentials.

Verification: Development simulator build and all 95 iOS tests in 23 suites passed on 2026-09-01. Live booking remains provider-specific and must be enabled only after an official provider interface and evidence mapping are verified.
