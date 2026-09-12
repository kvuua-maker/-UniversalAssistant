# Provider Capability Matrix

Last revalidated: 2026-09-12. Cost policy: zero additional provider cost. Public
handoffs never claim live price, inventory, availability, booking, purchase or
delivery completion.

## Build 40 physical provider evidence

- Physical source: 260 RequestIDs from iPhone12,8 / iOS 26.6.2.
- 43 requests reached the production `PROVIDER_PRE` boundary.
- 1 completed correctly through the existing ECB current-FX provider.
- 42 failed at or immediately after the provider boundary: 40
  `PROVIDER_REQUIRED`, 1 restaurant availability `ERROR`, and 1 NBU
  currency request rejected as `CLARIFICATION`.
- Provider-family requests rejected or misrouted before `PROVIDER_PRE` remain
  semantic/router evidence; they are not misreported as missing-provider proof.

## Zero-owner/no-cost completion

The in-place `OfficialPublicProviderHandoffRegistry` contains 26 credential-free
official consumer destinations. `RegionalCurrentFXProvider` adds the 27th
newly connected source, NBU reference rates. Search routes preserve the real
query when the official destination supports it; fixed official catalogs are
explicitly marked `query_preserved=false`.

| Family | Connected official destinations | Mechanism | Truth boundary |
|---|---|---|---|
| Marketplaces | Amazon, eBay, AliExpress, Temu, Prom.ua | exact official search route | provider confirms items, seller, price, delivery and purchase |
| Grocery/retail | Silpo, ATB, Fora, Fozzy | exact official consumer search | no cart/order or live-availability claim |
| Lodging | Booking.com, Dobovo | destination search / official catalog | no live-room or booking claim |
| Car rental | Getmancar | official consumer rental entry | no availability, quote or booking claim |
| Events | KARABAS | official event catalog | no event/seat availability claim |
| Cinema | Multiplex, Planeta Kino | official schedule/catalog | no seat or ticket-purchase claim |
| Jobs | Work.ua, robota.ua, Jobs.ua, State Employment Service, Djinni, DOU, Happy Monday | official public job search/catalog | no vacancy freshness or application claim |
| Rail | Ukrzaliznytsia | official ticket-search entry | no schedule/inventory/fare/purchase claim |
| Parcels | Nova Poshta, Ukrposhta, Meest | official tracking form | no tracking status is invented |
| FX involving UAH | National Bank of Ukraine | official credential-free reference-rate API | reference rate, not executable exchange quote |

Existing zero-owner system providers remain unchanged: Apple MapKit Places and
routes/transit, Apple WeatherKit, ECB reference rates, Apple Maps navigation,
public app/media handoffs and the system audio-route picker.

## Complete remaining external boundaries

These are capability boundaries, not silent omissions. They remain
`PROVIDER_REQUIRED` only because a public handoff cannot truthfully complete
the requested live or account-scoped action.

### OWNER_ACTION (17)

1. Marketplace live item/price/availability/seller comparison APIs — provider
   developer/affiliate accounts and credentials.
2. Grocery live price/availability/cart/checkout — retailer OAuth/feed contract.
3. Restaurant live availability/book/modify/cancel — approved reservation
   provider account and bearer credential.
4. Hotel live inventory/price/booking — approved inventory-provider account.
5. Car-rental live availability/quote/booking — provider account/API or user
   transaction login.
6. Uber route-prefill/live ride data — registered application/client ID and
   separately approved OAuth scopes.
7. Rail/coach/air live inventory/fare/purchase — authorized provider contract.
8. Glovo/Bolt Food live menu/cart/order — provider-approved credentials.
9. Nova Poshta/Ukrposhta/Meest live tracking/watch — carrier credentials.
10. Appointment availability/book/modify/cancel — selected provider account.
11. Gmail account search/send — Google OAuth client and consent.
12. Commercial jobs/ATS feeds — provider credentials/agreement.
13. Loyalty/personal prices/affiliate attribution — merchant OAuth and contract.
14. Business CRM/ERP/marketplace/booking connectors — selected partner account.
15. Audio/media control beyond public system/app handoff (Spotify Web API,
    Cast, Sonos, HEOS, B&O, BluOS, WiiM) — provider/device credentials and
    approvals.
16. Diia/vehicle plate sources — partner approval and lawful issued credentials.
17. Employer payments/StoreKit live purchase — configured products, agreements
    and sandbox/production account.

### PAID (2)

1. Current independent web/news/AI retrieval — selected Brave Search/Answers or
   NewsAPI production plan.
2. Commercial stock/market quotes — licensed Alpha Vantage or equivalent
   production entitlement.

### NO_OFFICIAL_MECHANISM (1)

1. Bolt/Uklon documented rider route-prefill or live comparison: no public
   consumer integration contract is currently verified; official app/site
   launch alone cannot preserve a typed ride request or provide live evidence.

Zero-owner `PROVIDER_REQUIRED` remaining: **0**.

## M12 device application capability evidence (MS-854–870)

| Target | Public mechanisms checked | Deepest implemented behavior | Unsupported boundary / fallback |
|---|---|---|---|
| Apple local domains | Contacts, EventKit/Reminders and AVFoundation public frameworks; App Intents entry points | Existing typed local action routes perform supported contact, event, reminder, note and recorder work | No private system-app launch or `App-Prefs` URL; return the typed local result or truthful unavailable state |
| Apple Maps / navigation | MapKit and HTTPS Maps links; local/external capability route | Existing navigation capability receives the structured destination rather than a generic application launch | Installed-app selection remains system-controlled |
| Telegram | Officially documented `tg:` URL scheme and public deep-link form | Exact alias launch; exact public username context via `tg://resolve?domain=…` | No arbitrary chat/message side effect; unsupported context is not fabricated |
| Viber | Publicly documented application URL scheme | Exact alias application launch | No deeper action is claimed without a currently verified official contract |
| Google Maps | Official Maps URLs / Universal Links | Exact search context through HTTPS Maps URL | Falls back to the same legitimate web destination if the app is absent |

App Intents/App Shortcuts exposed by third-party binaries are discoverable only on an installed physical-device configuration. That specific verification is queued; no private inter-app enumeration or control is used.

## M12 messenger capability evidence (MS-941–948)

| Messenger | FIND | OPEN_CHAT | COMPOSE | SEND | CALL | SEARCH_HISTORY | APP_INTENT | DEEPLINK | API | Deepest V1 behavior |
|---|---|---|---|---|---|---|---|---|---|---|
| Messages/SMS/iMessage | no | no | yes | no | no | no | device audit | no | MessageUI compose only | system composer; user sends |
| WhatsApp consumer | no | yes | yes | no | no | no | device audit | yes | no authorized consumer-history API | exact click-to-chat draft |
| Telegram consumer | no | yes | yes | no | no | no | device audit | yes | Bot/API access is not user inbox access | exact public username draft |
| Viber consumer | no | no | yes | no | no | no | device audit | yes | Bot API is not user inbox access | public share draft |
| Signal consumer | no | no | no | no | no | no | device audit | not claimed | no authorized consumer API | system share-sheet selection |
