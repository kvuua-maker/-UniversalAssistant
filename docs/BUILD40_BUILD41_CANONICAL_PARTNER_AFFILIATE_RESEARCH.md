# Build 40/41 canonical partner and affiliate verification

Verified: 2026-09-13. This is the pre-implementation evidence gate required by the
full master specification and the Marketplace Commerce Affiliate addendum.
Only provider or partner-owned documentation was accepted. A click or prepared
destination is not conversion evidence, and no commission is treated as earned
until the partner reports an eligible conversion.

## Decision rules applied

- `AFFILIATE_ACTIVE` requires configured, approved credentials plus production
  attribution evidence. There are currently no such credentials in the repo or
  build environment, so the active count is zero.
- `AFFILIATE_READY_OWNER_ACTION` means a current, zero-cost publisher program and
  an exact/deep-link mechanism were verified, but registration, a publisher ID,
  approval, terms, payout/tax details, or credentials are still required.
- `FUNCTIONAL_NO_AFFILIATE_PROGRAM` is reserved for a provider whose official
  material identifies another kind of integration and no publisher commission
  mechanism.
- `UNKNOWN` is retained where official research did not establish a current
  publisher program. Production must not invent attribution for these records.
- `UNSUPPORTED` is used where the provider says the relevant publisher/referral
  program is closed.

## Audited provider inventory (64)

| # | Provider | Consumer capability / Ukraine | Official monetization finding | Exact attribution | Decision |
|---:|---|---|---|---|---|
| 1 | Amazon | marketplace; usable from Ukraine through non-UA stores | Associates exists; mobile apps require an account/store ID and express approval; Special Links require user activation | product/search Special Links; Universal Links subject to program rules | AFFILIATE_READY_OWNER_ACTION |
| 2 | eBay | marketplace; buyer route available | eBay Partner Network requires enrollment and campaign ID; custom ID supported | listing/category/search links | AFFILIATE_READY_OWNER_ACTION |
| 3 | AliExpress | marketplace available in Ukraine | Portals publisher enrollment and affiliate links/API are current | product/search affiliate links | AFFILIATE_READY_OWNER_ACTION |
| 4 | Temu | marketplace available in Ukraine | Partner platform requires account/app key/secret/OAuth | partner links/API | AFFILIATE_READY_OWNER_ACTION |
| 5 | Prom.ua | Ukrainian marketplace | no current public publisher commission mechanism established in official material | none verified | UNKNOWN |
| 6 | Silpo | Ukrainian grocery catalogue/delivery | no current public publisher commission mechanism established | none verified | UNKNOWN |
| 7 | ATB | Ukrainian grocery catalogue/delivery | current ATB UA offer in Admitad; registration required | deeplink/product feed | AFFILIATE_READY_OWNER_ACTION |
| 8 | Fora | Ukrainian grocery catalogue | no current public publisher commission mechanism established | none verified | UNKNOWN |
| 9 | Fozzy | Ukrainian grocery catalogue | no current public publisher commission mechanism established | none verified | UNKNOWN |
| 10 | Booking.com | lodging in Ukraine/worldwide | official affiliate program via partner networks; free application | trackable property/search links | AFFILIATE_READY_OWNER_ACTION |
| 11 | Dobovo | Ukrainian apartments | official agent/affiliate program; registration required | any internal destination can be referral-linked | AFFILIATE_READY_OWNER_ACTION |
| 12 | Getmancar | Ukrainian car sharing/rental | official cooperation channel exists; no publisher commission program established | none verified | UNKNOWN |
| 13 | KARABAS | Ukrainian events/tickets | official partner/affiliate network and API require agreement | event/ticket links/API | AFFILIATE_READY_OWNER_ACTION |
| 14 | Multiplex | Ukrainian cinema | official cooperation/advertising and customer loyalty only; no publisher commission established | none verified | UNKNOWN |
| 15 | Planeta Kino | Ukrainian cinema | official cooperation/advertising and customer discounts only; no publisher commission established | none verified | UNKNOWN |
| 16 | Work.ua | Ukrainian jobs | no official publisher commission mechanism established | none verified | UNKNOWN |
| 17 | robota.ua | Ukrainian jobs | no official publisher commission mechanism established | none verified | UNKNOWN |
| 18 | Jobs.ua | Ukrainian jobs | no official publisher commission mechanism established | none verified | UNKNOWN |
| 19 | State Employment Service | public employment service | non-commercial public service | not applicable | FUNCTIONAL_NO_AFFILIATE_PROGRAM |
| 20 | Djinni | Ukrainian jobs | no official publisher commission mechanism established | none verified | UNKNOWN |
| 21 | DOU Jobs | Ukrainian jobs | no official publisher commission mechanism established | none verified | UNKNOWN |
| 22 | Happy Monday | Ukrainian jobs | no official publisher commission mechanism established | none verified | UNKNOWN |
| 23 | Ukrzaliznytsia | official rail booking | public transport seller; no official publisher commission program established | none verified | FUNCTIONAL_NO_AFFILIATE_PROGRAM |
| 24 | Nova Poshta | parcel/logistics | official API requires business account/key; referral material is not an app-publisher commission program | none verified | FUNCTIONAL_NO_AFFILIATE_PROGRAM |
| 25 | Ukrposhta | parcel/logistics | official API requires contract/token; no publisher commission program | none verified | FUNCTIONAL_NO_AFFILIATE_PROGRAM |
| 26 | Meest | parcel/logistics | official shop integration requires account/contract; no publisher commission program | none verified | FUNCTIONAL_NO_AFFILIATE_PROGRAM |
| 27 | National Bank of Ukraine | official reference FX data | public authority/reference data, not commerce | not applicable | FUNCTIONAL_NO_AFFILIATE_PROGRAM |
| 28 | Expirenza | restaurant booking | restaurant-side booking product; no public publisher commission program | none verified | FUNCTIONAL_NO_AFFILIATE_PROGRAM |
| 29 | Table | restaurant booking/POS | paid restaurant-side service; no consumer publisher commission program | none verified | FUNCTIONAL_NO_AFFILIATE_PROGRAM |
| 30 | Bolt Drive | car sharing | no current app-publisher consumer commission program established | none verified | UNKNOWN |
| 31 | Uklon | taxi | user referral is not a publisher program | none verified | FUNCTIONAL_NO_AFFILIATE_PROGRAM |
| 32 | Bolt | taxi/transport | Bolt for Business referral is B2B, not consumer ride attribution | none for consumer ride | FUNCTIONAL_NO_AFFILIATE_PROGRAM |
| 33 | Uber | taxi/transport | no current Ukraine app-publisher program established | none verified | UNKNOWN |
| 34 | Glovo | food delivery | courier/referral material is not publisher buyer attribution | none verified | FUNCTIONAL_NO_AFFILIATE_PROGRAM |
| 35 | Bolt Food | food delivery | no consumer publisher commission program established | none verified | FUNCTIONAL_NO_AFFILIATE_PROGRAM |
| 36 | Altegio | appointments | official partner/developer program and API require developer account/tokens/approval | API and B2B partner attribution | AFFILIATE_READY_OWNER_ACTION |
| 37 | Expedia | hotels/travel | free Travel Creator Program; account/application required | trackable deep links to exact pages | AFFILIATE_READY_OWNER_ACTION |
| 38 | Hotels.com | hotels | Expedia Group Travel Creator account required | exact trackable links | AFFILIATE_READY_OWNER_ACTION |
| 39 | Vrbo | apartments | Expedia Group Travel Creator account required | exact trackable links | AFFILIATE_READY_OWNER_ACTION |
| 40 | Agoda | hotels | official affiliate registration/review required | affiliate site/app links | AFFILIATE_READY_OWNER_ACTION |
| 41 | Viator | activities | official affiliate account; API access has qualification/key gate | exact product/destination links and campaign parameter | AFFILIATE_READY_OWNER_ACTION |
| 42 | GetYourGuide | activities | free partner registration required | exact deep link with partner ID | AFFILIATE_READY_OWNER_ACTION |
| 43 | DiscoverCars | car rental | official affiliate registration required | deeplink/landing generator/API | AFFILIATE_READY_OWNER_ACTION |
| 44 | Airbnb | lodging | official publisher program is not accepting applications; guest referral ended | unavailable | UNSUPPORTED |
| 45 | VARUS | Ukrainian groceries | current Admitad publisher offer; registration/approval required | mobile tracking/deeplink | AFFILIATE_READY_OWNER_ACTION |
| 46 | Foxtrot | Ukrainian electronics | current Admitad publisher offer; registration/approval required | product feed/deeplink | AFFILIATE_READY_OWNER_ACTION |
| 47 | Answear | Ukrainian fashion | current Admitad publisher offer; registration required | product feed/mobile tracking/deeplink | AFFILIATE_READY_OWNER_ACTION |
| 48 | Citrus | Ukrainian electronics | listed in current official Admitad Ukraine catalogue | network tracking/deeplink after approval | AFFILIATE_READY_OWNER_ACTION |
| 49 | MOYO | Ukrainian electronics | listed in current official Admitad Ukraine catalogue | network tracking/deeplink after approval | AFFILIATE_READY_OWNER_ACTION |
| 50 | Telemart | Ukrainian electronics | current Admitad publisher offer | network tracking/deeplink after approval | AFFILIATE_READY_OWNER_ACTION |
| 51 | INTERTOP | Ukrainian fashion | listed in current official Admitad Ukraine catalogue | network tracking/deeplink after approval | AFFILIATE_READY_OWNER_ACTION |
| 52 | Master Zoo | Ukrainian pet retail | listed in current official Admitad Ukraine catalogue | network tracking/deeplink after approval | AFFILIATE_READY_OWNER_ACTION |
| 53 | ANC | Ukrainian pharmacy retail | listed in current official Admitad Ukraine catalogue; only lawful retail intents apply | network tracking/deeplink after approval | AFFILIATE_READY_OWNER_ACTION |
| 54 | Agromarket | Ukrainian home/garden | listed in current official Admitad Ukraine catalogue | network tracking/deeplink after approval | AFFILIATE_READY_OWNER_ACTION |
| 55 | Vivat | Ukrainian books | listed in current official Admitad Ukraine catalogue | network tracking/deeplink after approval | AFFILIATE_READY_OWNER_ACTION |
| 56 | Budynok Igrashok | Ukrainian toys | listed in current official Admitad Ukraine catalogue | network tracking/deeplink after approval | AFFILIATE_READY_OWNER_ACTION |
| 57 | Knyharnia Ye | Ukrainian books | listed in current official Admitad Ukraine catalogue | network tracking/deeplink after approval | AFFILIATE_READY_OWNER_ACTION |
| 58 | Duna | Ukrainian fashion | current Admitad publisher offer | product feed/deeplink after approval | AFFILIATE_READY_OWNER_ACTION |
| 59 | Brocard | Ukrainian beauty retail | listed in current official Admitad Ukraine catalogue | network tracking/deeplink after approval | AFFILIATE_READY_OWNER_ACTION |
| 60 | Samsung Ukraine | Ukrainian electronics | listed in current official Admitad Ukraine catalogue | network tracking/deeplink after approval | AFFILIATE_READY_OWNER_ACTION |
| 61 | Hotline.Finance | Ukrainian insurance/reference service | current Admitad CPS offer; regulated scope applies | network tracking after approval | AFFILIATE_READY_OWNER_ACTION |
| 62 | Pokupon | Ukrainian activities/services | listed in current official Admitad Ukraine catalogue | network tracking/deeplink after approval | AFFILIATE_READY_OWNER_ACTION |
| 63 | Kontramarka | Ukrainian events | listed in current official Admitad Ukraine catalogue | event deeplink after approval | AFFILIATE_READY_OWNER_ACTION |
| 64 | Tickets.ua | Ukrainian travel tickets | listed in current official Admitad Ukraine catalogue | network tracking/deeplink after approval | AFFILIATE_READY_OWNER_ACTION |

## Primary official sources

- eBay Partner Network: https://partnernetwork.ebay.com/solutions/creating-affiliate-links
- Amazon Associates mobile application policy and Special Links:
  https://affiliate-program.amazon.com/help/node/topic/GCE3F2NCVZLDFM6A and
  https://affiliate-program.amazon.com/help/operating/agreement
- AliExpress Portals terms: https://cdn.contract.alibaba.com/terms/b_platform_service_agreement/20250305142526766/20250305142526766.html?lng=en
- Temu Partner Platform: https://partner-eu.temu.com/documentation?menu_code=633a8618bf544adabf411a1a07ac7b69
- Booking.com affiliate program: https://www.booking.com/affiliate-program/v2/index.en-gb.html
- Dobovo affiliate program: https://www.dobovo.com/agents/
- KARABAS partners: https://all.karabas.com/en/promoter/
- Expedia Group Travel Creator Program: https://partner.expediagroup.com/en-us/solutions/explore-our-affiliate-program
- Agoda partners: https://partners.agoda.com/
- Viator partner resources: https://partnerresources.viator.com/travel-content/links/create-links/
- GetYourGuide partner program: https://partner.getyourguide.support/hc/en-us/articles/13981068165917-Our-partner-program
- DiscoverCars affiliate program: https://www.discovercars.com/affiliate
- Airbnb program availability: https://www.airbnb.com/help/article/4236
- Admitad Ukraine current catalogue: https://www.admitad.com/ua/store/
- ATB UA program: https://www.admitad.com/ua/store/offers/atb-ua/
- Answear UA program: https://www.admitad.com/ua/store/offers/answear-ua/
- Altegio public developer/partner boundary: https://developer.alteg.io/en/partners
- Nova Poshta integration boundary: https://novaposhta.ua/for-business/cooperation/integration/
- Ukrposhta developer boundary: https://dev.ukrposhta.ua/documentation
- Meest integration boundary: https://ua.meest.com/services/shop/integration
- Expirenza booking product: https://docs.expirenza.com/features/booking
- Table restaurant platform: https://www.table.in.ua/

## Engineering decision

The existing provider-neutral attribution router and loyalty/commission ledger
are reused. The production provider handoff receives an injectable, verified
configuration boundary for exact-link parameters or an official redirector.
With no approved configuration it must preserve the exact functional provider
destination and report `MONETIZATION_PENDING_OWNER_ACTION`; it must never invent
a partner ID, commission, or conversion. Ranking remains independent of
commission and existing user discounts/attribution take priority.
