# UniversalAssistant Build 26 capability reachability inventory

All rows enter through `LocalCommandEngine` from typed Home input or finalized,
normalized Speech transcript, then `AssistantViewModel` and the named production
executor. “External” means a real configured provider is required; it is not a
mock-success claim. iOS minimum is 18 unless noted.

| Intent | Semantic variants / reachability | Public mechanism or real dependency | Permission / availability / bound | Class and fallback | Context, renderer, evidence |
|---|---|---|---|---|---|
| placeSearch | nearby/cafe/pharmacy/fuel/store; typed+voice | MapKit `MKLocalSearch` + CoreLocation | when-in-use; provider bound | direct structured; no web when Maps applies | result list/place; Places tests |
| productSearch | product/model/constraints; typed+voice | no configured catalog provider | external provider | controlled current-web handoff | constraints retained; canonical/multi-step tests |
| fashionDiscovery | collection/brand/size; typed+voice | no configured retail provider | external provider | controlled web, no fabricated offers | query retained; voice tests |
| groceryBasket | grocery/basket; typed+voice | Silpo adapter exists server-side, not app production-wired | external config | provider-required | commerce suites |
| serviceSearch | local service; typed+voice | configured provider absent; MapKit for place-like classes | location/provider bound | structured where place, else external | result context; parser tests |
| restaurantSearch | restaurant/dining; typed+voice | MapKit for discovery; booking provider absent | location | structured discovery; provider-required booking | Places tests |
| reservation | reserve/table; typed+voice | no configured reservation provider | external | truthful unavailable/provider-required | restaurant engine tests |
| taxiSearch | taxi/ride; typed+voice | researched provider registry, credentials absent | external | official handoff only when configured | ride registry tests |
| taxiCompare | compare rides; typed+voice | provider adapters require live access | external, bounded fanout | no invented comparison | ride tests |
| navigation | lead/navigate/route-to; typed+voice | MapKit + documented Apple Maps HTTPS | location as needed | structured resolve then handoff | active route; navigation tests |
| routeSearch | build/show route; typed+voice | MapKit | location | direct/handoff | route context; route tests |
| routeAwareSearch | “по дорозі”; typed+voice | MapKit search + directions | fresh route context, bounded | context-dependent structured | route retained; route-aware tests |
| calendarCreate | create event; typed+voice | EventKit | full calendar access; post-grant refresh | direct | event context; EventKit tests |
| calendarQuery | schedule/tomorrow/open calendar; typed+voice | EventKit in-app list | calendar access | direct; no Google | results context; EventKit tests |
| calendarUpdate | move/reschedule selected; typed+voice | EventKit | access + selected context | context-dependent direct | selected event; context tests |
| calendarDelete | delete event; typed+voice | EventKit | access + confirmation policy | reversible direct | EventKit tests |
| reminderCreate | absolute/relative reminder; typed+voice | EventKit Reminders | reminder access; refresh | direct | reminder result; EventKit/date tests |
| reminderQuery | show reminders; typed+voice | EventKit | reminder access | direct | result context; EventKit tests |
| reminderComplete | complete selected; typed+voice | EventKit | selection + access | context-required | EventKit tests |
| reminderDelete | delete selected; typed+voice | EventKit | selection + access | context-required | EventKit tests |
| noteCreate | create/new note; typed+voice | public `UIActivityViewController` handoff | foreground/user chooses Notes | handoff; no private Notes scheme/API | share presentation; Notes tests |
| noteQuery | show notes; typed+voice | document picker is only public generic handoff | foreground/user selection | handoff, no fabricated Notes database | documents presentation; router tests |
| shoppingList | shopping list; typed+voice | EventKit Reminders | reminder access | direct | reminder context; EventKit tests |
| contactLookup | find contact; typed+voice | Contacts `CNContactStore` | contacts; dedicated queue, 3 s deadline/cancel | direct/no-result/ambiguity | contact context; lifecycle tests |
| contactCall | call/dial/number/WhatsApp explicit; typed+voice | Contacts + documented `tel:`; explicit HTTPS wa.me | contacts for name; 3 s; user OS confirmation | system handoff; never implicit WhatsApp | selected contact; call tests |
| messageCompose | write/message; typed+voice | public `MFMessageComposeViewController` presentation | device capability/user sends | handoff | typed message; canonical tests |
| photoSearch | latest/newest/semantic; typed+voice | PhotoKit, in-app asset sheet | full/limited; post-grant continuation | direct; semantic fail-closed | photo context; Photos tests |
| fileSearch | find file/document; typed+voice | security-scoped document metadata | user-selected scope; 3 s/cancel | direct/no-result | file context; Files tests |
| cameraCapture | camera/photo/QR/OCR; typed+voice | AVFoundation camera, VisionKit scanner, Vision OCR | camera; foreground | public presentation; no fake shutter | captured/shared image; OCR/QR tests |
| translation | translate/follow-up; typed+voice | Apple Translation | language assets/system UI | direct in-app | original source retained; translation context tests |
| mediaSearch | Apple Music/music; typed+voice | MusicKit | Apple Music authorization | direct search + official URL action | result context; media tests |
| podcastSearch | podcast; typed+voice | public iTunes/Apple Podcasts search adapter | network, bounded | structured + exact URL | results; podcast tests |
| parcelTrack | tracking number; typed+voice | official configured parcel adapter where available | provider credential/network | external/provider-specific | parcel tests |
| weather | weather/location; typed+voice | WeatherKit | location for current position | direct in-app | weather context; weather tests |
| publicTransport | transit; typed+voice | MapKit transit where supported | location | route/provider semantics | transport tests |
| transportRoute | travel time/route; typed+voice | MapKit directions | location | structured route | route context; navigation tests |
| ticketSearch | ticket; typed+voice | official provider contract, no live app provider configured | external | provider-required | ticket tests |
| ticketPurchaseHandoff | buy ticket; typed+voice | exact verified HTTPS offer only | fresh provider offer/user confirmation | handoff; never claims purchase | ticket tests |
| hotelSearch | hotel; typed+voice | official provider contract, no live config | external/bounded fanout | provider-required | hotel tests |
| travelPlan | plan trip; typed+voice | typed coordinator/providers | configured providers required | partial/truthful | travel tests |
| emergency | emergency/112; typed+voice | documented `tel:112` | user confirmation by OS | system handoff | no stored context; parser tests |
| webSearch | explicit web/current info; typed+voice | controlled HTTPS search handoff | network/user opens | late fallback only | no false in-app answer; generic tests |
| deviceAction | timer/alarm/torch/battery/storage/clipboard; typed+voice | AlarmKit iOS 26+, AVFoundation, UIDevice, URL resource values, UIPasteboard | capability-specific; AlarmKit auth | direct; unsupported controls fail locally | typed native result; system suites |
| appAction | app-specific action; typed+voice | verified public app URL/universal link only | installed app/user OS confirmation | handoff or truthful unsupported | no generic URL guessing; app tests |
| audioRecord | record/pause/resume/stop; typed+voice | AVFoundation recorder | microphone | direct state machine | recording state; audio tests |
| show | show/open selection; typed+voice | CurrentContext selected action | fresh context, one-shot consumption | context-dependent | selected result; context tests |
| open | Files/Camera/Calendar/verified apps; typed+voice | typed public presentation/handoff | target-specific | direct presentation/handoff/unsupported | clean handoff UI; parser tests |
| cancel | cancel; typed+voice | local request lifecycle | active request | deterministic local | clears active work; state tests |
| undo | undo selected mutation; typed+voice | typed action history | reversible context | context-required | history tests |
| localUtility | arithmetic/percent/fixed units/date/day/time; typed+voice | deterministic local engine | none; timezone-aware | direct, web unreachable | native result; utility tests |
| currencyConversion | currency/rate; typed+voice | no configured live FX source | external `current_fx_rate` | truthful provider-required | provider audit/utility tests |
| multiStep | composed clauses; typed+voice | concrete dependency coordinator | per-step permissions/bounds | no abstract executable nodes | aggregate result/context; multi-step tests |
| settings | app settings only; typed+voice | public `UIApplication.openSettingsURLString` equivalent route | foreground | handoff; never Wi-Fi/Bluetooth page | system limitation tests |
| help | help; typed+voice | local content | none | direct | clean local result |
| contextualSelection | ordinal/follow-up; typed+voice | CurrentContext | five-minute freshness/one-shot action | context-dependent/clarify | lifecycle tests |
| unknown | unclassified informational; typed+voice | production coordinator absent | external | controlled web or clarification | no parser success claim; result-state tests |

Publicly unavailable third-party controls are handled locally and truthfully: Wi-Fi
page selection, Bluetooth toggle, Low Power Mode toggle, arbitrary system brightness
or volume, missed-call history, direct Calculator/Phone app launch, Contacts-app list,
and unrestricted alarms-list access. No private scheme is used and none routes to
Google as a pretend device control.
