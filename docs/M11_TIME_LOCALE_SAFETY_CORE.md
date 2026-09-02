# M11 Time, Locale, Currency and Unit Safety Core

Requirements MS-833–MS-837. Status: VERIFIED_LOCAL.

- Dates remain absolute instants with an explicit IANA timezone where wall-clock intent matters; reminder due components preserve their timezone and reconstruct with it rather than silently adopting a later device zone.
- `RuntimePresentationContext` reads runtime locale/timezone without mutating persisted commands or preferences.
- `AuthoritativeTimeWindow` uses server-issued boundaries with an explicit bounded skew allowance.
- Money comparisons return a typed conversion-required result across currencies. Existing commerce/transport/ticket hard constraints already reject mismatched currencies.
- Grocery quantities normalize mass and volume separately and explicitly refuse comparisons across incompatible dimensions.

Behavioral tests cover timezone/DST-stable instants, bounded clock skew, runtime locale changes with unchanged stored intent, cross-currency refusal and compatible/incompatible unit comparison.

Verification evidence (2026-09-02): 5 targeted tests passed; full iOS regression passed 227 tests in 57 suites; full backend regression passed 76 tests in 21 suites.
