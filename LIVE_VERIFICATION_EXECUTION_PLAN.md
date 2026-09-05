# Практичний порядок виконання 64 live-перевірок

Позначення категорій:

- **DEVICE** — можна перевірити на доступному реальному iPhone/iPad зі signed build.
- **APPLE** — потрібні Apple capability, entitlement, provisioning або спеціальне обладнання.
- **PROVIDER** — потрібен зовнішній provider account, OAuth/API key або sandbox.
- **PARTNER/LEGAL** — потрібні договір, партнерське схвалення, production infrastructure або юридичне рішення.
- **STORE** — потрібна TestFlight/App Store Connect/App Review стадія.

## Хвиля 1 — перевірки на фізичних пристроях без нових зовнішніх інтеграцій

1. **MS-800-LIVE-VOICE-QA — Voice QA**
   **Перевірити:** реальне розпізнавання змішаної української/російської мови, власних назв, адрес, брендів; уточнення і text fallback.
   **Потрібно:** signed build, iPhone, microphone, доступне системне speech recognition.
   **Категорія:** DEVICE. **Залежності:** немає.
   **Дії:** надати microphone/speech permission; продиктувати контрольний набір фраз; повторити з відмовою в permission і вимкненим voice.
   **PASS evidence:** відео/скринкаст, transcript і журнал результатів показують правильні сутності або рівно одне уточнення; текстовий режим працює без microphone.

2. **MS-227-MS-228-MS-229-MS-230-MS-231-MS-234-LIVE-EVENTKIT — Calendar/Reminders**
   **Перевірити:** create/query/reschedule/complete/delete через EventKit і natural dates п’ятьма мовами.
   **Потрібно:** iPhone, signed build, контрольний календар і список нагадувань.
   **Категорія:** DEVICE. **Залежності:** немає.
   **Дії:** надати доступ; створити й змінити disposable records; після кожної операції звірити exact ID у системному застосунку; потім заборонити доступ.
   **PASS evidence:** EventKit IDs, screenshots/read-back, правильний timezone; denial/ambiguity не створюють записів і не повертають fake success.

3. **MS-913-LIVE-PHOTOS — Photos search**
   **Перевірити:** пошук реальних фото за датою, альбомом, георадіусом і локальною Vision-міткою.
   **Потрібно:** контрольні несекретні фото з відомими metadata; full/limited/denied Photos states.
   **Категорія:** DEVICE. **Залежності:** немає.
   **Дії:** виконати однакові запити з full, limited, changed і denied access; відкрити знайдений asset за exact PhotoKit ID.
   **PASS evidence:** з’являються лише дозволені assets; відкривається точний asset; revoked/limited/no-match відображаються правдиво.

4. **MS-914-LIVE-FILES — Files/document providers**
   **Перевірити:** вибір, пошук і відкриття security-scoped files.
   **Потрібно:** контрольні файли в On My iPhone та одному document provider.
   **Категорія:** DEVICE. **Залежності:** немає.
   **Дії:** вибрати файли через system picker, знайти й відкрити; видалити файл або відкликати доступ і повторити.
   **PASS evidence:** доступні лише явно вибрані файли, URL відкривається точно, scope збалансований, missing/revoked file не дає stale success.

5. **MS-943-947-LIVE-MESSAGING — Messaging handoffs**
   **Перевірити:** SMS/iMessage composer і публічні handoff-механізми WhatsApp, Telegram, Viber, Signal.
   **Потрібно:** iPhone, контрольні отримувачі, встановлені representative apps.
   **Категорія:** DEVICE. **Залежності:** частково MS-915.
   **Дії:** відкрити кожен composer із контрольним контекстом, не надсилати або надіслати тільки дозволене disposable повідомлення; повторити без цільового app.
   **PASS evidence:** відкривається точний public composer/context; final send залишається під контролем користувача; відсутній app дає truthful fallback.

6. **MS-859-869-LIVE-INSTALLED-APP-ACTIONS — Telegram/Viber/Google Maps**
   **Перевірити:** exact app launch, Telegram username, Viber, Google Maps search, ambiguity й missing-app fallback.
   **Потрібно:** iPhone із відповідними apps; варіант тесту з видаленим одним app.
   **Категорія:** DEVICE. **Залежності:** немає.
   **Дії:** виконати точні й неоднозначні команди; відкрити публічного Telegram user і Maps search; видалити app та повторити.
   **PASS evidence:** найглибший дозволений context відкривається без narration; неоднозначність дає одне питання; missing app не симулює успіх.

7. **MS-915-LIVE-APP-ACTIONS — Representative public app actions**
   **Перевірити:** public App Intents, App Shortcuts, Universal Links і URL schemes.
   **Потрібно:** representative system/third-party apps на фізичному iPhone.
   **Категорія:** DEVICE. **Залежності:** немає.
   **Дії:** виконати exact launch/contextual actions; повторити з відсутнім app.
   **PASS evidence:** exact public target відкривається без narration; unsupported case повертає задокументований fallback без fake success.

8. **MS-841-842-LIVE-AUDIO-ROUTING — Audio interruptions/routes**
   **Перевірити:** built-in/Bluetooth HFP routing, call/Siri/alarm interruption, connect/disconnect.
   **Потрібно:** iPhone, Bluetooth headset або car HFP.
   **Категорія:** DEVICE. **Залежності:** бажано після MS-800.
   **Дії:** запустити listening/recording; перемикати routes; викликати дзвінок, Siri й alarm interruption.
   **PASS evidence:** audio безпечно pause/stop, UI не залишається у stale listening, microphone звільняється, typed UI продовжує працювати.

9. **MS-327-MS-328-MS-329-MS-330-QUICK-LAUNCH-LIVE-PHYSICAL-ACCESS — Quick Launch**
   **Перевірити:** Action Button, Back Tap, Siri/App Shortcut і Home Screen Shortcut.
   **Потрібно:** iPhone з Action Button та модель без нього; доступ до Shortcuts/Accessibility settings.
   **Категорія:** DEVICE. **Залежності:** MS-800 для voice path.
   **Дії:** налаштувати лише показані пристроєм способи; запускати з granted/missing voice permission і unavailable voice.
   **PASS evidence:** офіційний запуск одразу переходить у Listening або мінімальний permission/text fallback, без додаткового tap, narration чи private API.

10. **MS-916-LIVE-LOCAL-SEARCH-LATENCY — Local search performance**
    **Перевірити:** cold/warm latency локального пошуку online/offline.
    **Потрібно:** release-like build, representative Contacts/Calendar/Reminders/Photos/Files corpus.
    **Категорія:** DEVICE. **Залежності:** MS-227…, MS-913, MS-914.
    **Дії:** записати model/OS/corpus size; виміряти cold/warm percentiles online й offline.
    **PASS evidence:** коректні результати offline та latency в canonical budget; збережені фактичні percentiles, а не simulator timing.

11. **MS-917-LIVE-REGION-VERSION-CAPABILITY — Region/version capability matrix**
    **Перевірити:** фактичні capabilities за різних iOS/app version, region та account combinations.
    **Потрібно:** доступні representative devices/accounts/regions.
    **Категорія:** DEVICE. **Залежності:** MS-915 та relevant provider checks.
    **Дії:** виконати capability discovery/routing у кожній доступній комбінації.
    **PASS evidence:** registry вмикає лише реально exposed actions; fallback збігається з device reality; немає глобальних припущень.

12. **MS-409…MS-422-LIVE-DEVICE-MATRIX — Full physical-device matrix**
    **Перевірити:** permissions, voice, GPS, system actions, notifications, deep links і network transitions.
    **Потрібно:** signed iPhone, контрольні device records/apps, Wi‑Fi/cellular/offline.
    **Категорія:** DEVICE. **Залежності:** консолідує MS-800, EventKit, messaging, app actions і quick launch.
    **Дії:** пройти всі рядки `REAL_DEVICE_TEST_MATRIX.md`, включно з grant/deny/restrict і network transitions.
    **PASS evidence:** кожен рядок має actual result; denial не loop/crash; handoff не рахується completion; simulator evidence не підміняє device evidence.

13. **MS-1589-LIVE-IPHONE-SE-PERFORMANCE — Oldest supported device**
    **Перевірити:** cold launch, fast paths, provider fanout, memory pressure.
    **Потрібно:** найстаріший підтримуваний iPhone, release-like build, Instruments.
    **Категорія:** DEVICE. **Залежності:** стабільний signed release candidate.
    **Дії:** зняти startup, TTFR, peak memory, CPU, battery і responsiveness.
    **PASS evidence:** фактичні Instruments traces відповідають owner-approved thresholds; немає freeze чи unbounded work.

14. **JOBS-026-LIVE-INTERVIEW-DEVICE — Jobs interview scheduling**
    **Перевірити:** employer proposal → candidate confirmation → Calendar/navigation/notification → update/cancel.
    **Потрібно:** signed iPhone, controlled employer/candidate accounts, Calendar/location permissions.
    **Категорія:** DEVICE. **Залежності:** MS-227… EventKit.
    **Дії:** запропонувати interview; підтвердити; звірити event/link/location; оновити й скасувати.
    **PASS evidence:** до confirmation нічого не створено; після confirmation exact system references відповідають контрольній співбесіді.

15. **VISUAL-ADDENDUM-LIVE-OWNER-REVIEW — Owner visual review**
    **Перевірити:** Home, orb, cards/details, booking, scanner, themes, accessibility, motion і haptics.
    **Потрібно:** signed build із завершеною local visual implementation; representative iPhone sizes.
    **Категорія:** DEVICE. **Залежності:** усі локальні visual/snapshot gates та потрібні domain flows.
    **Дії:** owner проходить canonical visual flows у dark/light, Dynamic Type і Reduce Motion.
    **PASS evidence:** owner review checklist/screenshots підтверджують textual visual canon, accessibility й відсутність browser/provider/AI chrome.

## Хвиля 2 — Apple capabilities, entitlements і provisioning

16. **MS-253…MS-276-LIVE-SYSTEM-ACTIONS — Apple system actions**
    **Перевірити:** emergency handoff, fresh location, camera, call/message/calendar/reminder/navigation, MusicKit і recorder.
    **Потрібно:** signed iPhone, permissions, representative apps, MusicKit entitlement/account.
    **Категорія:** APPLE. **Залежності:** EventKit, messaging, audio routing.
    **Дії:** виконати й скасувати контрольні handoffs; протестувати grant/deny; перевірити Music playback/recorder.
    **PASS evidence:** використовуються лише public user-visible mechanisms, consequential completion не вигадується, denial/absence правдиві.

17. **MS-953-955-LIVE-APPLE-SYSTEM-DOMAINS — Camera/MusicKit/Podcasts**
    **Перевірити:** camera capture, Apple Music catalog/playback, Podcasts search/open, Clock availability.
    **Потрібно:** MusicKit entitlement, Apple Music account/subscription, signed device.
    **Категорія:** APPLE. **Залежності:** audio routing.
    **Дії:** capture/cancel; grant/deny Music; search і керувати playback; відкрити exact podcast episode.
    **PASS evidence:** actual account/catalog/playback state; exact podcast handoff; denied/unsupported Clock/private action не оголошується виконаною.

18. **MS-223-225-LIVE-WEATHERKIT — WeatherKit**
    **Перевірити:** current/hourly/daily weather для device і manual locations.
    **Потрібно:** Apple signing team, WeatherKit entitlement і network access.
    **Категорія:** APPLE. **Залежності:** немає.
    **Дії:** зробити контрольні запити; звірити source/time/location; повторити offline/denied/timeout.
    **PASS evidence:** усі значення походять із WeatherKit із правильним provenance; unavailable не перетворюється на вигадану погоду.

19. **MS-1005-1009-LIVE-SHARE — Share Extension**
    **Перевірити:** share URL/text/image/document/vCard із Files і Photos.
    **Потрібно:** App Group у provisioning обох targets, signed device.
    **Категорія:** APPLE. **Залежності:** коректне provisioning App Group.
    **Дії:** поділитися кожним типом; перевірити one-time host consumption; cancel/unsupported.
    **PASS evidence:** extension присутній і bounded; exact selected context потрапляє в host рівно один раз.

20. **MS-1013-1014-LIVE-SAFARI-SHARE — Safari Share Sheet**
    **Перевірити:** передача URL/title контрольної сторінки з Safari.
    **Потрібно:** той самий App Group/signed build.
    **Категорія:** APPLE. **Залежності:** MS-1005-1009.
    **Дії:** share webpage; перевірити structured host context; cancel і unsupported data.
    **PASS evidence:** точний URL/title оброблено один раз; немає заяв про browser history/control.

21. **MS-1015-1022-LIVE-SCANNERS-VCARD — QR/barcode/document/vCard**
    **Перевірити:** physical scan, OCR, routing, contact confirmation і denied permission.
    **Потрібно:** camera-capable signed iPhone, App Group, контрольні коди/документ/vCard.
    **Категорія:** APPLE. **Залежності:** Share integration.
    **Дії:** сканувати QR, known/unknown barcode, paper document, vCard; перевірити cancel/deny.
    **PASS evidence:** повертається тільки observed payload/OCR; unknown/payment code не виконується; contact import підтверджується користувачем.

22. **MS-1625…MS-1634-LIVE-SYSTEM-CAMERA-EMERGENCY — System/camera/emergency**
    **Перевірити:** public system paths, capture/save, OCR/translation/barcode/QR/visual similarity, emergency confirmation.
    **Потрібно:** signed iPhone й permissions; plate lookup окремо потребує licensed provider.
    **Категорія:** APPLE; plate lookup — PROVIDER. **Залежності:** scanner і system actions.
    **Дії:** пройти дозволені camera/system flows; emergency handoff скасувати до дзвінка; plate lookup виконувати лише після provider approval.
    **PASS evidence:** actual system read-back; dangerous QR/emergency paths мають confirmation; plate owner PII не показується; unsupported правдивий.

23. **MS-305…MS-313-LIVE-CLOUDKIT — CloudKit sync**
    **Перевірити:** private-database sync, conflict/tombstone, offline і reinstall restore.
    **Потрібно:** production CloudKit container, signed builds на двох пристроях з одним контрольним iCloud account.
    **Категорія:** APPLE. **Залежності:** Apple Developer configuration.
    **Дії:** create/edit/delete preferences, aliases, saved places, proactive rules на різних devices; offline/reinstall.
    **PASS evidence:** синхронізуються лише дозволені records; deterministic newest/tombstone wins; actions не replay; reinstall відновлює exact data.

24. **MS-704-LIVE-SIGN-IN-WITH-APPLE — Sign in with Apple**
    **Перевірити:** authorization, server token validation, session restoration і revocation.
    **Потрібно:** enabled App ID capability, server key/audience, signed iPhone, controlled Apple ID.
    **Категорія:** APPLE. **Залежності:** deployed verification endpoint.
    **Дії:** sign in; перевірити nonce/code/token; relaunch; revoke й повторити.
    **PASS evidence:** лише authentic Apple authorization створює session; revocation очищає її; local-first режим залишається доступним.

25. **MS-1598-MS-1615-LIVE-ACCOUNT-DATA-RIGHTS — Account export/deletion**
    **Перевірити:** real account creation, sync/server state, export, deletion і revocation.
    **Потрібно:** завершений Sign in with Apple і deployed backend.
    **Категорія:** APPLE. **Залежності:** MS-704, CloudKit/backend deployment.
    **Дії:** sign in; створити контрольні дані; export; initiate deletion; перевірити backend cleanup і residual audit expiry.
    **PASS evidence:** export точний; scoped data видалено; token revoked; lawful residual audit має правильний строк; fake success відсутній.

26. **MS-729…MS-732-LIVE-STOREKIT — Subscription lifecycle**
    **Перевірити:** purchase, cancel, expire, retry/grace, refund/revoke, product change, restore, cross-device entitlement.
    **Потрібно:** App Store Connect products/agreements, sandbox tester, server notifications endpoint.
    **Категорія:** APPLE. **Залежності:** backend deployment та signed build.
    **Дії:** пройти StoreKit sandbox lifecycle і звірити signed transactions/server notifications.
    **PASS evidence:** Premium змінюється лише verified transactions; ціна/період із StoreKit; restore працює; invalid verification нічого не надає.

27. **MS-1618-MS-1619-LIVE-MEDIA-PROVIDERS — Media providers**
    **Перевірити:** supported search/play/pause/resume/next/previous/exact-open.
    **Потрібно:** physical device, provider subscriptions/credentials, доступні public integrations.
    **Категорія:** APPLE/PROVIDER. **Залежності:** Apple system domains й audio routing.
    **Дії:** для кожного configured provider виконати supported actions і unsupported case.
    **PASS evidence:** тільки офіційно підтримані actions мають success; actual playback read-back; provider-owned state збережено.

28. **MS-978-979-LIVE-CARPLAY — CarPlay**
    **Перевірити:** approved category, managed entitlement, minimal CarPlay scene і driving-safe UX.
    **Потрібно:** owner category decision, Apple CarPlay approval, entitlement/profile, vehicle/test environment.
    **Категорія:** APPLE. **Залежності:** owner decision та Apple approval.
    **Дії:** після approval додати лише granted entitlement; перевірити simulator і physical CarPlay.
    **PASS evidence:** тільки схвалена категорія, system templates, мінімальна взаємодія, жодного general phone UI; signed profile містить exact entitlement.

## Хвиля 3 — provider accounts, OAuth та API credentials

29. **MS-174-LIVE-SILPO-CURRENT-SOURCE — Silpo MCP**
    **Перевірити:** official MCP session, tool discovery, current product price/availability.
    **Потрібно:** authorized guest OAuth token і reachable `mcp.silpo.ua`.
    **Категорія:** PROVIDER. **Залежності:** немає.
    **Дії:** inject token server-side; initialize session; discover read tools; search контрольний товар/branch.
    **PASS evidence:** adapter parses authoritative facts із freshness; token відсутній у logs/repo; auth/schema/rate-limit failure повертає unavailable.

30. **MS-927-934-LIVE-GMAIL — Gmail provider contract**
    **Перевірити:** search/raw/attachment/draft/reply/label/archive/trash/revoke.
    **Потрібно:** Google OAuth client, approved test user, controlled Gmail account.
    **Категорія:** PROVIDER. **Залежності:** Google consent configuration.
    **Дії:** authorize minimum scopes; виконати контрольні reads і confirmed mutations; disconnect.
    **PASS evidence:** actual Gmail IDs/content/state збігаються з read-back; unconfirmed mutation не викликає API; tokens/content відсутні в logs.

31. **MS-937-940-LIVE-GMAIL-JOURNEYS — Gmail journeys**
    **Перевірити:** universal email search, email→action, travel ticket attachment, July invoice.
    **Потрібно:** той самий Gmail fixture account.
    **Категорія:** PROVIDER. **Залежності:** MS-927-934.
    **Дії:** виконати чотири journeys на контрольних повідомленнях.
    **PASS evidence:** повертаються exact IDs/content/attachments із Gmail provenance; missing data залишається unknown.

32. **MS-783-786-LIVE-PROVIDER-CONTRACTS — Provider sandbox contract suites**
    **Перевірити:** schema, capability, auth expiry, rate limiting.
    **Потрібно:** sandbox accounts, credentials і reachable endpoints для вибраних providers.
    **Категорія:** PROVIDER. **Залежності:** provider selection.
    **Дії:** inject staging secrets; запустити non-destructive contract suites; rotate/remove secrets.
    **PASS evidence:** responses відповідають validated schemas; жодної purchase/booking mutation; credentials не потрапляють у logs/source.

33. **MS-217-LIVE-AUTHENTICATED-AVAILABILITY — Protected availability**
    **Перевірити:** OAuth scopes, protected availability fetch, revoke/reauth.
    **Потрібно:** registered OAuth client і controlled provider account.
    **Категорія:** PROVIDER. **Залежності:** конкретний provider contract.
    **Дії:** authorize minimum scopes; отримати одну availability; revoke/disconnect.
    **PASS evidence:** password не збирається; facts збігаються з provider; expiry/revoke fail closed.

34. **GENERIC-RETAIL-WEB-LIVE-DISCOVERY-EXTRACTION — Generic retail web**
    **Перевірити:** unknown merchant discovery → retrieval → structured extraction → native card.
    **Потрібно:** lawful web-search API credential і pages, де automated retrieval дозволений.
    **Категорія:** PROVIDER. **Залежності:** вибір search provider.
    **Дії:** знайти unknown merchant; звірити identity/variant/price/stock/timestamp; перевірити blocked/dynamic/stale/API duplicate.
    **PASS evidence:** truthful native card і Open handoff; no invented affiliate; restricted page ≠ no stock; API evidence перемагає duplicate без variant merge.

35. **GENERAL-UNKNOWN-INTENT-LIVE-WEB-DISCOVERY — Generic unknown intent**
    **Перевірити:** unknown-domain jobs/service/course/event discovery та failure semantics.
    **Потрібно:** production search endpoint, server bearer credential, controlled pages.
    **Категорія:** PROVIDER. **Залежності:** generic search provider; може reuse попередній пункт.
    **Дії:** виконати representative queries; перевірити authoritative/stale/blocked/dynamic pages і partial failure.
    **PASS evidence:** native verified results; privacy-minimized queries; blocked facts unknown; лише Open action там, де немає глибшої capability.

36. **MS-222-LIVE-HOTEL-PRICE-AVAILABILITY — Hotel provider**
    **Перевірити:** mandatory-fee total, currency, availability і exact booking URL.
    **Потрібно:** approved hotel account/API credential.
    **Категорія:** PROVIDER. **Залежності:** provider contract.
    **Дії:** query controlled stay/guests/rooms; звірити provider UI/API; перевірити auth/rate-limit failure.
    **PASS evidence:** тільки current matching rows; stale/unknown лишається unknown; handoff не називається booking.

37. **MS-185-186-LIVE-RESTAURANT-RESERVATION — Restaurant booking**
    **Перевірити:** live slots і confirmed booking.
    **Потрібно:** approved booking provider, endpoints, credential.
    **Категорія:** PROVIDER. **Залежності:** provider contract.
    **Дії:** request controlled slot; звірити UI; після explicit confirmation створити booking і read-back.
    **PASS evidence:** лише fresh authoritative slots; success тільки з nonempty provider reference і CONFIRMED state.

38. **MS-208-211-LIVE-TICKET-SCHEDULE-INVENTORY-FARE-ACTION — Tickets**
    **Перевірити:** schedule, current fare, inventory, exact itinerary handoff і optional controlled transaction.
    **Потрібно:** provider account/API/credential і controlled itinerary.
    **Категорія:** PROVIDER. **Залежності:** owner approval для transaction.
    **Дії:** search route/date; звірити provider; відкрити exact action; купівлю виконувати лише окремо дозволену.
    **PASS evidence:** schedule/fare/inventory відповідають provider; stale/auth/rate-limit fail closed; purchase лише після real confirmation.

39. **MS-1031-1033-LIVE-PARCEL-ADAPTERS — Parcel adapters**
    **Перевірити:** Nova Poshta/Ukrposhta/Meest auth, tracking, branches і error handling.
    **Потрібно:** provider-issued credentials, active/delivered shipment IDs, test locations.
    **Категорія:** PROVIDER. **Залежності:** окремі carrier accounts.
    **Дії:** query active/delivered/unknown IDs і nearby branches; перевірити rate limits/failures.
    **PASS evidence:** status/events/coordinates відповідають official carrier; secret не збережений; provider failure не блокує інші.

40. **MS-1035-1037-LIVE-PARCEL-TRACK-WATCH — Parcel watch**
    **Перевірити:** durable watch після restart та actual carrier transition.
    **Потрібно:** ті самі carrier credentials і shipment зі зміною стану.
    **Категорія:** PROVIDER. **Залежності:** MS-1031-1033 та operational notifications.
    **Дії:** створити watch; restart; дочекатися реальної зміни; перевірити notification dedup.
    **PASS evidence:** рівно одна notification на verified transition; durable state survives restart; unavailable data не вигадується.

41. **MS-1052-1056-LIVE-APPOINTMENTS — Appointment provider**
    **Перевірити:** slot search, book, read-back, reschedule, cancel і linked Calendar/departure state.
    **Потрібно:** lawful provider API, sandbox/account, credential.
    **Категорія:** PROVIDER. **Залежності:** EventKit для linked artifacts.
    **Дії:** знайти slot; explicitly book; read-back; reschedule; cancel.
    **PASS evidence:** actual provider IDs/states; stale slot не пропонується; fallback не називається booking; Calendar змінюється лише після confirmed state.

42. **MS-1044-1045-LIVE-FOOD-PROVIDERS — Food provider adapters**
    **Перевірити:** menu, price, fees, availability, ETA і provider failure.
    **Потрібно:** approved scopes, credentials, test stores.
    **Категорія:** PROVIDER. **Залежності:** provider agreements may be required.
    **Дії:** реалізований adapter підключити до approved API; query same dish/address у providers.
    **PASS evidence:** provider totals/ETA збігаються; missing facts неповні, а не fabricated; failed provider не блокує alternatives.

43. **MS-1047-1049-LIVE-FOOD-COMPARE-ORDER — Food order lifecycle**
    **Перевірити:** comparison, confirmed disposable order, cancellation/refund.
    **Потрібно:** ті самі credentials і дозвіл на controlled order.
    **Категорія:** PROVIDER. **Залежності:** MS-1044-1045.
    **Дії:** explicitly confirm один order; read-back; cancel/refund.
    **PASS evidence:** unconfirmed order не виконується; confirmed/cancelled/refunded states лише з provider evidence.

44. **MS-1479…MS-1485-LIVE-BOOKABLE-PROVIDERS — Multi-category booking**
    **Перевірити:** restaurants, hotels, tickets, appointments у normalized bookable layer.
    **Потрібно:** credentials і inventory для кожної available category.
    **Категорія:** PROVIDER. **Залежності:** restaurant, hotel, ticket, appointment checks.
    **Дії:** retrieve live availability; exact handoff або confirmed booking; supported reschedule/cancel; timeout/partial failure.
    **PASS evidence:** category semantics і provider state збігаються; unavailable category truthful; одна помилка не блокує решту.

45. **BUSINESS-OPERATIONS-LIVE-PARTNER-CONNECTORS — Partner connectors**
    **Перевірити:** catalog price/stock/delete, inquiry, order/booking status, cancel/refund, health recovery.
    **Потрібно:** approved partner sandbox/production account, endpoints/webhook keys.
    **Категорія:** PROVIDER/PARTNER. **Залежності:** executed connector agreement.
    **Дії:** inject secrets server-side; виконати по одній supported operation; перевірити tenant isolation/idempotency/audit.
    **PASS evidence:** тільки advertised capabilities; authoritative event persists once; stale/duplicate/unsupported fail closed; commission adjustments правильні.

46. **MS-237…MS-245-LIVE-PROACTIVE — Proactive Engine**
    **Перевірити:** authoritative traffic/weather/hours/product/ticket changes, geofence і notification suppression.
    **Потрібно:** device permissions плюс approved live providers.
    **Категорія:** PROVIDER. **Залежності:** EventKit, WeatherKit, route/product/ticket providers.
    **Дії:** створити future events/watches; спричинити або дочекатися controlled changes; вимкнути category.
    **PASS evidence:** meaningful fresh change повідомляється один раз; disabled category мовчить; stale/unavailable provider нічого не вигадує.

47. **MCA-10-LIVE-CAMERA-COMMERCE — Scan-to-commerce**
    **Перевірити:** barcode/text/image → normalized identity → current offers.
    **Потрібно:** camera iPhone і live product source.
    **Категорія:** PROVIDER. **Залежності:** scanner та commerce provider.
    **Дії:** scan controlled product identifiers; retrieve current offers; перевірити unresolved variant.
    **PASS evidence:** exact normalized identity; лише fresh sourced facts; unknown variant залишається unknown.

48. **MCA-18-LIVE-POST-PURCHASE — Post-purchase**
    **Перевірити:** order/tracking/cancel/refund/delivery read-back.
    **Потрібно:** merchant order API/account і real carrier event.
    **Категорія:** PROVIDER. **Залежності:** attributed handoff та parcel adapters.
    **Дії:** створити controlled provider order; отримати official states; скасувати/refund за дозволом.
    **PASS evidence:** click не стає purchase; lifecycle змінюється лише official evidence.

49. **JOBS-014-JOBS-025-JOBS-029-JOBS-030-LIVE-PROVIDERS — Jobs providers/ATS**
    **Перевірити:** vacancy ingest/update/close, application callback і attribution.
    **Потрібно:** provider-approved credentials/schemas та commercial agreement, якщо потрібний.
    **Категорія:** PROVIDER/PARTNER. **Залежності:** provider approval.
    **Дії:** inject credentials; search/ingest/update/close controlled vacancy; перевірити callback.
    **PASS evidence:** truthful idempotent isolated operations; handoff не називається submission; revenue лише за contract evidence.

50. **LOYALTY-PERSONAL-PRICE-ATTRIBUTION-LIVE-MERCHANT — Merchant loyalty core**
    **Перевірити:** OAuth loyalty data, public/personal price, coupons/rewards, attributed login/handoff і reversals.
    **Потрібно:** merchant OAuth/API, controlled loyalty account/card і affiliate contract.
    **Категорія:** PROVIDER/PARTNER. **Залежності:** partner policy evidence.
    **Дії:** connect account; compare quotes; perform official tracking/login/voucher flows; test eligible/incompatible/expired/competing/refund cases.
    **PASS evidence:** passwords не потрапляють у UA; prices separated; attribution/eligibility відповідають versioned contract; reversal auditable.

51. **LOYALTY-012-115-LIVE-PARTNER-INTEGRITY — Loyalty/commission integrity**
    **Перевірити:** provider-specific stacking, commission basis/state, same/cross-device attribution і full/partial refund.
    **Потрібно:** реальні accounts, terms/contracts, checkout і refund capability.
    **Категорія:** PROVIDER/PARTNER. **Залежності:** попередній loyalty merchant flow.
    **Дії:** записати versioned policy; link account; compare benefit paths; same/cross-device checkout; commission confirmation; partial/full refund.
    **PASS evidence:** payable price, stacking, attribution і reversals точно відповідають provider evidence; UNKNOWN/INCOMPATIBLE не трактуються як success.

52. **PRIVACY-016-157-LIVE-DATA-FLOW — External privacy data flow**
    **Перевірити:** actual outbound domains/payloads/logs, consent/revocation і provider retention controls.
    **Потрібно:** signed build, configured provider accounts, observable network environment.
    **Категорія:** PROVIDER; App Store validation окремо STORE. **Залежності:** representative providers із попередніх пунктів.
    **Дії:** пройти permissions/consents/revocations; inspect traffic і logs; перевірити retention configuration.
    **PASS evidence:** лише classified, minimized, consented fields ідуть intended HTTPS recipient; secrets ніколи не йдуть AI/logs; revocation негайно блокує access.

## Хвиля 4 — infrastructure, commercial, partner та legal

53. **MS-741-742-745-747-LIVE-DEPLOY — Deployment/rollback**
    **Перевірити:** CI promotion, immutable deploy, health і rollback.
    **Потрібно:** protected GitHub Environments, deployment identity, hosting target.
    **Категорія:** PARTNER/LEGAL — production infrastructure. **Залежності:** owner hosting decision.
    **Дії:** run CI; approve staging; deploy immutable artifact; health check; config/code rollback drills.
    **PASS evidence:** critical failures block promotion; artifact/log identity retained; known-good rollback відновлює service без destructive data rollback.

54. **MS-748-754-LIVE-DRILL — Backup/disaster recovery**
    **Перевірити:** encrypted production snapshot і isolated restore з RPO/RTO.
    **Потрібно:** selected storage, service identity, KMS, durable DB і restore environment.
    **Категорія:** PARTNER/LEGAL — production infrastructure. **Залежності:** deployment.
    **Дії:** snapshot; restore; integrity, tenant, monetary й queue checks; заміряти RPO/RTO.
    **PASS evidence:** authenticated restore без tenant/financial drift; RPO ≤1 год, RTO ≤4 год або точний failure record.

55. **MS-773-780-LIVE-OPERATIONS — Operations/support channels**
    **Перевірити:** paging, public status, recovery й privacy-safe feedback correlation.
    **Потрібно:** paging destination, on-call schedule, support/status accounts.
    **Категорія:** PARTNER/LEGAL — operations. **Залежності:** deployed backend.
    **Дії:** trigger synthetic critical і threshold incidents; recovery; submit feedback.
    **PASS evidence:** deduplicated alerts/status/recovery; diagnostic ID корелюється без raw command, secrets чи provider payloads.

56. **MS-769-772-LIVE-RETENTION — Production retention/deletion**
    **Перевірити:** retention у всіх deployed stores, logs, analytics і backups.
    **Потрібно:** selected regions/subprocessors та jurisdiction-approved overrides.
    **Категорія:** PARTNER/LEGAL. **Залежності:** deployment і backup.
    **Дії:** задокументувати actual regions/processors; expire records; delete test account; перевірити propagation.
    **PASS evidence:** expired/account data видалено в межах policy; lawful financial records збережені; residency відповідає disclosure.

57. **MS-1039-LIVE-DIIA-PARTNER-INTEGRATION — Diia partner flow**
    **Перевірити:** approved identity/document sharing/signature scenario та signed callback.
    **Потрібно:** owner lawful use case, Diia approval/credentials, controlled consenting identity.
    **Категорія:** PARTNER/LEGAL. **Залежності:** explicit owner scenario decision.
    **Дії:** configure exact contract; execute one confirmed flow; validate callback; test denial; verify retention/deletion.
    **PASS evidence:** запитуються лише approved data/actions; Diia показує requester/consent; denial не повертає data; callback matches transaction.

58. **MS-1572…MS-1577-LIVE-PARTNER-PROGRAMS — Affiliate/partner programs**
    **Перевірити:** application, approval, tracking, controlled conversion і reconciliation.
    **Потрібно:** approved legal/business identity, public URLs, selected programs/accounts.
    **Категорія:** PARTNER/LEGAL. **Залежності:** published privacy/terms/support assets.
    **Дії:** submit selected programs; record states; execute supported test conversion; reconcile.
    **PASS evidence:** application/approval auditable; exact tracking preserved; click не стає commission; `EARNING_VERIFIED` лише після proven attribution.

59. **JOBS-006-LIVE-EMPLOYER-PAYMENT — Jobs prepaid entitlement**
    **Перевірити:** real employer payment → entitlement credit → single publication consumption.
    **Потрібно:** production payment account, signed employer account, approved Jobs products.
    **Категорія:** PARTNER/LEGAL/PROVIDER. **Залежності:** payment configuration.
    **Дії:** купити один entitlement; publish once; replay callback.
    **PASS evidence:** рівно один credit і одне consumption; replay нічого не змінює; audit trail повний.

60. **MS-764…MS-782-LIVE-PRIVACY-LEGAL — Privacy/legal publication**
    **Перевірити:** final policy/terms URLs, privacy report і App Privacy answers.
    **Потрібно:** owner/legal approval, public HTTPS URLs, archived build, App Store Connect record.
    **Категорія:** PARTNER/LEGAL, потім STORE. **Залежності:** retention/processor inventory та release archive.
    **Дії:** approve/publish docs; configure URLs; generate Xcode privacy report; complete App Privacy disclosure.
    **PASS evidence:** archived binary, manifest, processor inventory й disclosures збігаються; немає undeclared tracking/SDK/Required Reason API.

## Хвиля 5 — повний corpus, TestFlight та App Store

61. **MS-1078-LIVE-GOLDEN-JOURNEY-COUNT — 100 journey completion**
    **Перевірити:** усі 65 live/provider-classified journeys на додачу до 35 local.
    **Потрібно:** результати відповідних device/provider/partner checks.
    **Категорія:** STORE/pre-release aggregate. **Залежності:** практично всі попередні domain live-items.
    **Дії:** виконати кожен distinct live journey і додати його PASS або exact truthful failure evidence.
    **PASS evidence:** 100/100 distinct journeys мають execution evidence; catalog presence не рахується виконанням.

62. **MS-1080-LIVE-GOLDEN-REAL-ACTIONS — Golden real actions**
    **Перевірити:** recognized text → intent/entities → real source/result/action → confirmation/failure для 65 live journeys.
    **Потрібно:** той самий controlled build/accounts/credentials/entitlements.
    **Категорія:** STORE/pre-release aggregate. **Залежності:** усі relevant domain items та MS-1078.
    **Дії:** пройти corpus; записати latency, taps, confirmation, fallback і exact error; consequential actions лише disposable/approved.
    **PASS evidence:** кожен journey доходить до найглибшого legitimate result або чесного actionable failure; збережені aggregate metrics; mocks не враховані.

63. **MS-820-LIVE-RELEASE — Signed release/TestFlight**
    **Перевірити:** archive, validation, physical install, TestFlight processing і smoke/device matrix на exact build.
    **Потрібно:** Apple Developer team, distribution certificate/profile, registered device, App Store Connect/TestFlight.
    **Категорія:** STORE. **Залежності:** signing/entitlements, privacy/legal, critical device checks.
    **Дії:** inject team without committing credentials; archive/validate; install; upload; пройти smoke matrix.
    **PASS evidence:** immutable signed build запускається; TestFlight processing без signing/privacy errors; device evidence прив’язане до exact build.

64. **MCA-40-LIVE-APP-STORE-LEGAL — App Review/legal outcome**
    **Перевірити:** актуальні App Review, referral/external purchase, affiliate disclosure і privacy requirements.
    **Потрібно:** App Store Connect, signed release, jurisdiction-specific legal/commercial approval.
    **Категорія:** STORE/LEGAL. **Залежності:** MS-764… privacy/legal і MS-820 release.
    **Дії:** фінально звірити metadata/disclosures; submit exact build; зафіксувати App Review та legal outcome.
    **PASS evidence:** metadata й in-app disclosures відповідають реальній referral model; немає неузгодженого merchant-of-record claim; App Review outcome прив’язаний до exact submitted build.

## Перший пункт

**Почати з `MS-800-LIVE-VOICE-QA` — Voice QA на фізичному iPhone.**


## Consolidated current-HEAD voice/text/routing physical batch (pending Apple 90382 clearance)

Run this batch only from the next single TestFlight build produced from the then-current authoritative HEAD. Build 22 is stale and must not be uploaded.

1. Voice quality: dictate one natural Ukrainian request, one semantically different Russian request, one longer conversational request, and one request containing a proper name or brand. Confirm stable final punctuation/capitalization, automatic stop, editable visible text, and no unexplained “Find” prefix.
2. Composer: type a short request; then type/paste a multiline long request with the keyboard visible. Confirm wrapping, adaptive growth, bounded scrolling, caret visibility, reachable send/microphone controls, dismissal/restoration, and edit a dictated request before submitting.
3. Routing: submit one place/local-discovery request, one clothing/footwear commerce request, one grocery/store-price request, and one broad informational request. Confirm the specific canonical capability is selected before general web fallback and that truthful provider-unavailable states do not claim success.
4. Pending system classes: verify the Russian informational path; create/query/update/delete one disposable Calendar event; create/query/complete/delete one disposable Reminder; then cover the smallest representative already-queued physical classes (installed-app/system handoff, Contacts/MessageUI, Photos/Files/camera, Maps/navigation, media, share extension) using their existing queue criteria.

PASS evidence: exact-build physical UI/system results plus automatically uploaded privacy-safe VPS sessions showing speech API/locale/configuration, lifecycle, semantic capability, selected mechanism, and result stage, with no transcript/audio/private content. Each capability remains separately PASS/FAIL; this batch never converts external-provider absence into success.
