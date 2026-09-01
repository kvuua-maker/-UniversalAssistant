# M4 Fashion Discovery and Official SHOW/OPEN

- Fashion requests preserve audience, footwear/clothing/accessory category, brand, size, color, season, maximum price and online/nearby channel as typed filters.
- Brand, size, color, category, season and price constraints remain explicit hard constraints; a provider adapter must not silently relax them.
- Latest collection, new arrival and discount are typed source claims. Requested claims must be present in current provider evidence before an item can be opened as that claim.
- Official opening follows verified official app URL first, then an exact allowlisted HTTPS page. Homepages, unapproved hosts/schemes and non-exact paths are rejected.
- SHOW/OPEN prepares a destination only; it does not claim availability, purchase or that a complete third-party catalogue exists inside UniversalAssistant.

Verification: Development build and simulator suite passed 83 tests in 21 suites on 2026-09-01. Live fashion catalogue claims remain provider-specific integration gates.
