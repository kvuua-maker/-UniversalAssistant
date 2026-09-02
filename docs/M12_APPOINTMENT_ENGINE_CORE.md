# M12 Appointment Engine Core

Requirements MS-1050–1056. Status: VERIFIED_LOCAL; named-provider live execution is READY_FOR_LIVE_VERIFICATION.

`AppointmentEngine` supports dental/medical, salon/barber, car/tire, veterinary, repair and extensible categories. It concurrently searches bounded providers and accepts only fresh provider-attributed slots explicitly marked availability-verified. Category, date/time, maximum exact `Decimal` price and minimum rating are hard filters. Unknown availability never appears as a slot.

Direct booking requires explicit confirmation and authoritative provider response with matching provider/slot/booking IDs, confirmed state and source reference. Reschedule and cancel likewise require matching read-back state. When no direct provider contract exists, the engine distinguishes official HTTPS handoff from phone/navigation fallback and never calls either a confirmed booking. A confirmed booking alone can generate a `CalendarEventDraft` and route-evidence-based departure time; reschedule/cancel return data needed to synchronize those linked artifacts.

`OfficialAppointmentHTTPProvider` is the production boundary: configurable official search/booking endpoints, bearer credential injection, eight-second transport timeout, Codable request/response parsing, and explicit authentication/rate-limit/provider error mapping. Secrets are neither logged nor persisted.

Behavioral evidence in `AppointmentEngineTests` covers the canonical after-15 tire-service constraints; unverified/stale rejection; confirmed booking, reschedule and cancel; Calendar/departure linkage; exact HTTP requests/responses, credential rejection and rate-limit handling. Full regression on 2026-09-02 passed 306 iOS tests across 76 suites and 79 backend tests across 22 suites. Commit evidence is the atomic commit containing this document and referenced files.
