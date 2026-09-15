# UniversalAssistant provider-first / Apple-first routing rebuild

Audit date: 2026-09-15. Owner routing decision, the unabridged v13.2 master
specification, Jobs, Commerce/Affiliate, Loyalty, Privacy and Audio addenda are
the joint source of truth. This document is the zero-omission migration record;
it does not turn documentation or an adapter into production evidence.

## Three-pass gate

1. Product/source audit: complete. Every `CommandIntent`, the 26 credential-free
   handoffs, the 64-provider partner inventory, Apple system boundaries and
   Build 40–51 physical evidence were reconciled.
2. Official capability audit: complete for every path changed by this migration.
   Apple ContactsUI/Contacts/EventKit/PhotoKit/FileProvider/NetworkExtension/
   CoreBluetooth public boundaries, Google Maps URLs, Places billing/key rules,
   Google Search availability, eBay/Amazon affiliate boundaries, Booking,
   KARABAS, ChoiceQR, Nova Poshta, Ukrposhta and Meest were checked against
   provider-owned documentation. Unknown access remains `UNKNOWN`.
3. Consistency audit: complete. The change reuses the parser, executor, current
   context, provider and affiliate registries, result renderer, Jobs rules,
   Apple modules, diagnostics and cost/privacy gates. It adds no second router,
   paid service, private API, provider password flow or invented attribution.

## Authoritative routing lanes

| Priority | Capability families / `CommandIntent` | Authoritative route | Fallback/status |
|---:|---|---|---|
| A | contact, message/call/mail, calendar, reminders, notes, photos, files, camera, device/settings, media/audio, app/open, personal/context | Apple public iOS integration | Truthful `SYSTEM_RESTRICTED`; never web |
| B | any explicit provider/retailer/app | That provider only | Its deepest official exact route; never chooser/substitution |
| C | product/fashion with explicit brand | Official brand route | Exact official search/catalog; no marketplace substitution |
| D | place/restaurant/service and unqualified physical product/grocery | Local discovery, exact Google Maps handoff | MapKit discovery + no-key Maps URL until Places billing is approved |
| E | hotel/accommodation | Booking.com | Exact destination search; Demand API awaits partner credentials |
| F | restaurant table reservation | Verified restaurant/provider booking boundary | Exact provider booking link; aggregate ChoiceQR/RestOn remains `UNKNOWN` |
| G | jobs | UniversalAssistant Jobs rules first | One external Ukrainian source only when internal results are insufficient |
| H | event/cinema/transport tickets | KARABAS / exact cinema / Ukrzaliznytsia | City/date/query preserved; no Kyiv default |
| I | parcel/delivery | Explicit Nova Poshta/Meest/Ukrposhta | One minimal clarification if provider is absent |
| J | weather, currency, local utilities, emergency, translation, routes, compound | Existing specialized executor | Same-domain truthful failure only |
| K | `webSearch`/genuinely informational `unknown` | Exact Google Search URL | Never Google homepage and never system-error fallback |

All 57 `CommandIntent` values are covered by the rows above: `placeSearch`,
`productSearch`, `fashionDiscovery`, `groceryBasket`, `serviceSearch`,
`restaurantSearch`, `reservation`, `taxiSearch`, `taxiCompare`, `navigation`,
`routeSearch`, `routeAwareSearch`, `calendarCreate`, `calendarQuery`,
`calendarUpdate`, `calendarDelete`, `reminderCreate`, `reminderQuery`,
`reminderComplete`, `reminderDelete`, `noteCreate`, `noteQuery`, `shoppingList`,
`contactLookup`, `contactCall`, `messageCompose`, `photoSearch`, `fileSearch`,
`cameraCapture`, `translation`, `musicRecognition`, `mediaSearch`,
`podcastSearch`, `parcelTrack`, `weather`, `publicTransport`, `transportRoute`,
`ticketSearch`, `ticketPurchaseHandoff`, `hotelSearch`, `travelPlan`, `emergency`,
`webSearch`, `deviceAction`, `appAction`, `audioRecord`, `show`, `open`, `cancel`,
`undo`, `localUtility`, `currencyConversion`, `multiStep`, `settings`, `help`,
`contextualSelection`, and `unknown`.

## Provider contracts: active functional registry

| Provider | Capability | Mechanism / exactness | Auth / owner action | UA cost | Attribution | Production status |
|---|---|---|---|---:|---|---|
| Amazon | marketplace | exact official search/product handoff | Associates approval for monetization | 0 | pending owner action | `FALLBACK_ONLY` |
| eBay | marketplace | exact official search/product handoff | EPN campaign; OAuth only for account data | 0 | pending owner action | `FALLBACK_ONLY` |
| AliExpress | marketplace | exact official search handoff | Portals approval for attribution | 0 | pending owner action | `FALLBACK_ONLY` |
| Temu | marketplace | exact official search handoff | partner account/app credentials | 0 | pending owner action | `FALLBACK_ONLY` |
| Prom.ua | marketplace | exact official search handoff | no buyer API claimed | 0 | unknown | `FALLBACK_ONLY` |
| Silpo / ATB / Fora / Fozzy | grocery | exact official query route, only when named | ATB Admitad approval for monetization | 0 | ATB pending; others unknown | `FALLBACK_ONLY` |
| Booking.com | accommodation | exact destination search | Affiliate ID/API token/Managed Partner scope for API depth | 0 | pending owner action | `IMPLEMENTED_AWAITING_CREDENTIALS` |
| Dobovo | apartments | official catalog; no exact query verified | affiliate registration | 0 | pending owner action | `FALLBACK_ONLY` |
| Getmancar | car rental | official consumer handoff | deeper partner access unknown | 0 | unknown | `FALLBACK_ONLY` |
| KARABAS | events | exact verified city subdomain; no public API endpoint invented | partner agreement, docs, Partner ID, API credentials | 0 | pending owner action | `IMPLEMENTED_AWAITING_CREDENTIALS` |
| Multiplex / Planeta Kino | cinema | official schedule handoff | no public purchase API claimed | 0 | unknown | `FALLBACK_ONLY` |
| Work.ua / robota.ua / Jobs.ua / State Employment Service / Djinni / DOU Jobs / Happy Monday | jobs | explicit provider exact route; external fallback only after Jobs policy | no password/API claimed | 0 | none/unknown | `FALLBACK_ONLY` |
| Ukrzaliznytsia | rail tickets | official booking destination | no public buyer API claimed | 0 | none verified | `FALLBACK_ONLY` |
| Nova Poshta | delivery | exact tracking; API connector boundary | business-cabinet API key | 0 | none | `IMPLEMENTED_AWAITING_CREDENTIALS` |
| Ukrposhta | delivery | exact tracking; API connector boundary | agreement/token | 0 | none | `IMPLEMENTED_AWAITING_CREDENTIALS` |
| Meest | delivery | exact tracking; API connector boundary | customer contract/token | 0 | none | `IMPLEMENTED_AWAITING_CREDENTIALS` |
| NBU | currency | official public reference API | none | 0 | not applicable | `PRODUCTION_VERIFIED` |

## Complete commercial/partner inventory

The canonical 64-provider audit remains authoritative and no provider is
silently dropped. In addition to the 27 records above it contains:

- Restaurant/food: Expirenza, Table, ChoiceQR (aggregate capability unknown),
  RestOn (public API unknown), Glovo and Bolt Food.
- Taxi/car: Bolt Drive, Uklon, Bolt and Uber.
- Appointments: Altegio.
- Travel/accommodation/activities: Expedia, Hotels.com, Vrbo, Agoda, Viator,
  GetYourGuide, DiscoverCars and Airbnb.
- Ukrainian retail/services: VARUS, Foxtrot, Answear, Citrus, MOYO, Telemart,
  INTERTOP, Master Zoo, ANC, Agromarket, Vivat, Budynok Igrashok, Knyharnia Ye,
  Duna, Brocard, Samsung Ukraine, Hotline.Finance and Pokupon.
- Tickets: Kontramarka and Tickets.ua.

`docs/BUILD40_BUILD41_CANONICAL_PARTNER_AFFILIATE_RESEARCH.md` holds one row and
current official source per provider. None is `AFFILIATE_ACTIVE`: no approved
partner credentials are present. Airbnb is `UNSUPPORTED`; paid or
billing-exposed paths are disabled; all unknown programs remain `UNKNOWN`.

## Apple/system capability matrix

| Family | Public mechanism | Exact limitation/status |
|---|---|---|
| Contacts/card | Contacts + ContactsUI `CNContactViewController(for:)` | Limited access distinguished from not-found |
| Email/message/call | Contacts resolution + MessageUI / `tel:` | One minimal disambiguation; no provider password |
| Calendar/reminders/clock | EventKit; AlarmKit on supported iOS | No Google fallback; actual framework result required |
| Photos/files | PhotoKit/Vision; picker/security-scoped URLs | Authorized content only; limited state is truthful |
| Wi-Fi | `NEHotspotConfigurationManager` can join a named network with consent | Hotspot Configuration entitlement is absent; global toggle is `SYSTEM_RESTRICTED` |
| Bluetooth | CoreBluetooth for permitted BLE discovery/connection | Global toggle is `SYSTEM_RESTRICTED` |
| Settings | `UIApplication.openSettingsURLString` for this app | No private `App-Prefs:` routes |
| Maps/navigation | MapKit route/search; exact Google Maps URL where policy selects Google | Location only for explicit task |
| Weather/audio/camera/translation | WeatherKit, public media/capture/Translation paths | Existing privacy and authorization gates retained |

## Cost and credential state

- Google Maps URLs: no key and no charge. Active fallback.
- Google Places API/SDK: API key plus billing required. Disabled until explicit
  owner approval; field-mask/SKU quota boundary is required before activation.
- Google web-search API: not enabled. Current API is closed to new customers;
  exact `google.com/search?q=` handoff is the zero-cost fallback.
- No provider secrets were found in the source or environment inspected for
  this migration. Tokens remain Keychain/backend-only.
- No paid API, billing account, subscription or silent overage is activated.

## Physical evidence state

Physical diagnostics inventoried: Build 40 (260 requests), Build 41 (49),
Build 42 (166), Build 43 (57), Build 47 (3), Build 48 (3), Build 49 (4),
Build 50 (4), Build 51 (20), plus Build 39 baseline. Build 40 had 75
clarifications, 43 errors and 40 provider-required terminal states; Build 41
had 7 clarifications and 3 errors. Terminal `SUCCESS` is not physical proof.
Build 52 has no owner physical routing result yet. All changed journeys remain
`DEVICE_TEST_REQUIRED` after the consolidated build.

## Acceptance and owner actions

The migration is accepted internally only when explicit provider requests
produce one exact same-provider destination, brands use official routes,
nearby results are distance-bounded and open one exact map destination,
KARABAS never silently defaults another city, Apple commands never reach web,
contact lookup presents the system contact card, Jobs does not fan out, and no
handoff/booking/API claim becomes success without its acceptance evidence.

Consolidated owner actions (none blocks zero-cost engineering):

| Priority | Provider | Exact action | Cost | Works before | Unlocks after |
|---|---|---|---:|---|---|
| P1 | Google Maps Platform | Explicitly approve a billing-enabled project and restricted credential only if live Places API is desired | potentially paid; not approved | MapKit discovery + exact free Maps URL | live Place ID/details/field-masked nearby search |
| P1 | Booking.com | Partner approval, Affiliate ID and granted Demand API token/scope | 0 program access | exact Booking search | attributed API depth granted by Booking |
| P1 | KARABAS | Partner agreement, current API documentation, Partner ID and credentials | 0 unless contract says otherwise | exact city catalog | event/session inventory, attributed checkout/reporting |
| P1 | Admitad/individual affiliate programs | Publisher enrollment, approvals, IDs and payout/tax details | 0 | exact non-attributed provider routes | legitimate attributed routes |
| P2 | eBay | EPN campaign; OAuth client only for user-account capabilities | 0 | exact public search | attribution/account-scoped actions |
| P2 | ChoiceQR/RestOn | Confirm aggregate consumer inventory and obtain partner/API scope | unknown | exact restaurant/provider links where available | verified reservation API if granted |
| P2 | Nova Poshta / Meest / Ukrposhta | Provider-issued API key or contract token | 0 integration; provider contract terms apply | exact tracking handoff | authorized account shipment operations |
| P2 | Google personal services | OAuth client and approved minimum scopes | 0 subject to provider quotas | public Maps/search unaffected | Gmail/Calendar/Drive personal data |

## Internal verification evidence

- Provider-first/Apple-first targeted routing: 45/45 passed.
- Provider/commerce policy regression: 170/170 passed.
- Build 35 systemic regression: 16/16 passed.
- Full iOS regression: 1012/1012 passed, 0 skipped.
- Backend/Jobs/Business/partner/privacy/cost regression: 115/115 passed.
- `git diff --check`: passed.

These are internal engineering gates, not physical verification. Every changed
device/provider journey remains `DEVICE_TEST_REQUIRED` until the consolidated
TestFlight build is exercised on a real iPhone.
