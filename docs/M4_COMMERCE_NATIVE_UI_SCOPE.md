# M4 Native Commerce Results UI

- `CommerceOfferPresentation` converts normalized provider data into a compact, native card model without raw payloads or URL lists.
- Cards show the exact variant, current item price, evidence-backed discount, seller, availability, Ukraine delivery, known cost components, returns, warranty, buyer protection and source freshness. Unknown final cost remains explicitly unknown.
- Best-total and fastest-delivery labels require a unique objective winner. Total prices are never compared across currencies. Official-store labels require an affirmative provider value.
- `CommerceResultsState` updates existing offers in place and appends newly verified offers, preventing chaotic reordering during progressive loading.
- Images use bounded card thumbnails and load asynchronously; Commerce views and provider paths remain absent from application startup initialization.
- The purchase button says only that it opens the exact seller offer. It does not claim a purchase, conversion or affiliate commission.
- SwiftUI uses semantic text styles, localized strings in all five V1 languages, accessibility containers, labels and hints for Dynamic Type and VoiceOver compatibility.

Verification: Development build and simulator suite passed 79 tests in 20 suites on 2026-09-01. Visual VoiceOver, largest Dynamic Type and exact deep-link handoff checks remain in the device/UI acceptance matrix.
