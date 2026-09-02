# Golden User Journeys

Canonical requirements: MS-1077–MS-1087. The executable source of truth is `GoldenUserJourneyCatalog`: 20 canonical high-frequency families across Ukrainian, Russian, English, German and French, yielding 100 distinct journey records.

Each generated record contains: stable ID, input/recognized language, expected parsed intent/entities, required capabilities/provider source, truth/freshness contract, side-effect and confirmation rule, expected UI/result, failure behavior, behavioral evidence suite, local/live status, manual baseline steps and generic-AI baseline steps. `GoldenJourneyRunner` records actual normalized recognition, parsed intent/entities, selected capability/source, actual typed completion action, measured latency, taps, confirmations, PASS/READY status and failure reason.

| Family | Coverage | Behavioral evidence |
|---|---|---|
| App open / offline | deterministic zero-AI fast path and unavailable-app honesty | LocalActionRouterTests |
| Weather / partial failure | fresh facts, fan-out isolation, unavailable rather than invention | WeatherContextTests; ProviderFanoutEngineTests |
| Navigation / calendar / reminders | validated place/time, exact EventKit/route action, reversible mutation | RouteNavigationTests; CalendarServiceTests; ReminderServiceTests |
| Email/message/call | exact contact/provider object and user-controlled side effect | MessagingIntegrationTests; UniversalDeviceCommandRouterTests |
| Commerce / grocery | source-backed prices/availability, comparable totals, purchase handoff | CommerceSearchEngineTests; GroceryBasketEngineTests |
| Appointment / ticket / hotel / parcel | authoritative availability/state, exact object and confirmation boundary | AppointmentEngineTests; TicketEngineTests; HotelSearchEngineTests; ParcelDeliveryEngineTests |
| Government | official allowlisted handoff; no fabricated private access | GovernmentLocalServicesEngineTests |
| Routines | typed dependency graph, permissions, confirmation, cancellation and deduplication | RoutineMacroEngineTests |
| Connected accounts | actual OAuth connection/revocation state | ConnectedAccountsHubTests |
| Consequential cancellation | explicit confirmation and exact target | InteractionDecisionEngineTests |
| Bounded AI fallback | deterministic attempt first, one schema-validated interpretation, no AI facts/actions | BoundedAIInterpretationTests |

The 100-record count is executable, not a prose assertion. Local deterministic records must PASS the command→parser→typed-plan runner. Provider/device/account journeys remain READY_FOR_LIVE_VERIFICATION until their linked queue action produces real evidence; mocks are not reported as live success. Existing domain behavioral suites provide the deeper engine/provider-boundary execution for every family above.

Metrics emitted per execution support completion/no-extra-question rate, time-to-action, tap/confirmation count and fallback/live-success separation. Manual baseline means opening the relevant app, locating the object/provider and completing the action; generic-AI baseline additionally includes leaving chat for the real action. A core journey cannot pass UX acceptance if it consistently adds unnecessary steps without compensating verified value.
