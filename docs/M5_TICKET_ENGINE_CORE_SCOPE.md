# M5 Ticket Engine Core

- `TicketEngine` provides a provider-neutral domain for rail, coach, flight, ferry, event and future ticket offers.
- It validates ordered, non-overlapping itinerary segments and keeps fare evidence separate from seat/inventory evidence.
- Missing or stale fare evidence cannot satisfy a budget. Unknown, stale or source-less inventory cannot satisfy a verified-availability request.
- Departure, arrival, currency, budget and transfer constraints are hard filters; absent evidence does not satisfy them.
- Purchase handoff requires a fresh provider-sourced available inventory state and an exact HTTPS offer path.
- A successful handoff is only `destinationPrepared`; it never claims that a ticket was held, booked, paid for or issued.
- The engine performs no network work and initializes no ticket provider at app startup.

Verification is recorded in repository state after the Development simulator build and complete iOS/backend test runs pass.
