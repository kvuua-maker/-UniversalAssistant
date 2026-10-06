# KILO REPAIR CHECKPOINT

Repair branch checkpoint. Read this first when resuming work. It records the
verified starting state, what was actually changed, how it was verified, and
what is still open. Nothing in this file substitutes for a physical test.

## Продовження 2026-10-06 — актуальний локальний результат

Цей розділ доповнює, а не переписує історичний checkpoint нижче.

- Робоча гілка: `fix/canonical-repair-20261006`, база
  `39bdd03e8a3b83a3a98eb31000057e0ba2d4bcbd`.
- Окреме дерево: `/private/tmp/ua-canonical-repair-20261006`.
  Початковий локальний `active-universalassistant` лишився чистим на
  `experiment/ios27-speech-probe`, `7d0c0724add242be0e7497419b7e8f54c3703997`.
- Повторний read-only `ls-remote` підтвердив: main/checkpoint = `89b5a07`,
  experiment = `ef54b25`, canonical-repair = `39bdd03`. Ці гілки не змінювалися.
  Push, CI, номер білда, archive, IPA та TestFlight у цьому ремонті не виконувалися.

### Підтверджені зміни A–D

**A — диктування.** Звичайні xcconfig не активували `IOS27_SPEECH_PROBE`;
додано умови лише для SDK27 у Development/Staging/Production. Первинний
Apple transcript не переписується й непорожній final передається ViewModel
один раз. Справжні `DictationTranscriber.Result.alternatives` та атрибут
confidence тепер доходять до чинного evidence-aware parser; невідомий
confidence залишається nil. Перевірено публічний Speech SDK26.5 та документацію
[Result](https://developer.apple.com/documentation/speech/dictationtranscriber/result).
Контекст містить обмежений кеш користувацьких фраз і назви застосунків;
запуск не очікує оновлення словника, legacy permission або Groq. Додано
session ownership після await, щоб старі start/stop/final не зачіпали нове
диктування. Groq/legacy fallback не вилучено. Втрату конкретної назви саме
Apple ASR на телефоні не доведено: фізичних transcript немає.

**B — Telegram/Viber.** Усунуто обхід строгих правил коротких app names
через parser і вибір першої суперечливої ASR-альтернативи. Пороги resolver
не знижені. Перевірено українські/російські/англійські назви й відмінки,
parser → executor → `tg://`/`viber://`, а також production ViewModel з
контрольованими true/false результатами системного open. Чинне оброблення
невдалого open вже було правдивим і збережено; false не доводить, що app
відсутній. Слабкий/неоднозначний збіг не відкриває застосунок.

**C — Photos.** «За минулий рік» тепер означає попередній календарний рік
у PhotoKit predicate; дата зберігається і для змішаного запиту документів.
Документи мають справжній локальний `VNRecognizeTextRequest`, а не сценовий
label. OCR-текст не журналюється/не зберігається; кеш містить лише агрегований
document evidence, окремий namespace та modificationDate. Обмеження:
200 metadata-filtered кандидатів, 2 паралельні Vision операції, 2 с + 20 мс
semantic deadline, 1.2 с network-disabled thumbnail deadline; metadata 750 мс.
Результати, отримані до timeout, не губляться й позначаються неповними.
Limited/full/denied перевірені контрольованими assets; після await повторно
перевіряються дозвіл і доступність точних asset IDs перед публікацією.
Реальний Vision OCR перевірено на згенерованому текстовому PNG та порожньому PNG.
Це не доказ індексації всієї бібліотеки або швидкодії OCR на SE 2.

**D — історичні маршрути.** Наявний автомобільний repair не переписувався;
тести BMW/сьомої серії, Rolls-Royce та загального авто-запиту проходять.
Прибрано підтверджене перетворення неповного booking на nearby Maps;
збережено уточнення → availability → вибір → підтвердження, без раннього book.
Виправлено продовження «о 19:30 для 3 гостей»: нормалізація раніше стирала
двокрапку й не дозволяла розпізнати час. Додано bare-address navigation
«Проклади маршрут Урлівська 4А Київ». Messenger recipient/channel/body
більше не обрізаються через «через», службові слова, пунктуацію чи HH:MM;
альтернативні канали вимагають уточнення. Звичайний дзвінок мамі вже мав
telephone default: uk/ru/en regression та реальний Contacts framework із
синтетичним контактом підтверджують `tel:`, не WhatsApp. Усі зовнішні
відкриття в цих тестах перехоплені, реальні дзвінки/повідомлення не відправлялись.

### Фактичні перевірки

MacinCloud FF146-I, Xcode **26.6 (17F113)**, SDK **26.5**, iPhone 17 Pro
Simulator **iOS 26.5 (23F77)**; sequential test runner.

- Перший цільовий набір: **169 Swift Testing tests / 13 suites PASS**.
- Додатковий цільовий набір після booking/Photos access-race виправлень:
  **72 tests / 5 suites PASS**. Попередній booking-only запуск виявив
  проблему `19:30`; вона виправлена й перевірена, а не вилучена з тесту.
- Перший повний набір виявив 2 інфраструктурні FAIL: відсутній Contacts
  дозвіл у Simulator; помилкове віднімання `/tmp` від `/private/tmp` у
  license-content тесті. Дозвіл надано лише тестовому Simulator; тест
  канонізує шляхи й зберігає точну перевірку єдиного дозволеного asset.
  Їхній цільовий повтор: **3 tests / 2 suites PASS**.
- Фінальний повний iOS набір: **1111/1111 PASS, 0 failed, 0 skipped**
  (`1102` Swift Testing + `9` XCTest; `1248` виконань з параметрами).
  Звіт: `/private/tmp/ua-canonical-full-final-20261006.xcresult`;
  лог: `/private/tmp/ua-canonical-full-final-20261006.log`.
- Generic arm64 iOS Development app + ShareExtension: **BUILD SUCCEEDED**,
  без підпису, без archive/upload. Лог:
  `/private/tmp/ua-canonical-device-build-20261006.log`.
- `git diff --check`: PASS. Backend не змінювався; його тести не запускалися.
- SDK27 backend: syntax parse з прапорцем PASS, але **compile/runtime UNKNOWN**.
  На Mac немає SDK27, а SDK26.5 не містить `CaptureInputSequenceProvider`.
  Generic SDK26.5 build та fake-backend tests не підміняють цей шлюз.

### Лише фізично непідтверджене

Після справжньої SDK27 збірки на SE 2 потрібні: перевірка встановленого
номера білда; диктування Telegram/Viber із зіставленням видимого Apple text
і результату open; дві Photos-фрази на відомих датах/документах із limited,
full і denied; історичні auto/booking/address/message/mama сценарії.
Реальний ASR, встановлені apps, Photos дозвіл/контент, зовнішнє бронювання,
відкриття адреси та фізичні системні дії — **UNKNOWN**. Статуси
DEVICE_TEST_REQUIRED/READY_FOR_LIVE_VERIFICATION не підвищувалися до PASS.

## Історичний checkpoint до цього локального продовження

- Branch: `kilo/universalassistant-canonical-repair`
- START HEAD: `ef54b25a1c0632b3ce5cf13da3ccc174e490eeb9` (== `origin/experiment/ios27-speech-probe`)
- Merge-base with `origin/main`: `89b5a07d38a19c54b58a88285a5b9903314810db`
- `origin/main` and `origin/checkpoint/build59-pre-ios27-speech-probe`: untouched at `89b5a07`
- The experiment branch is strictly ahead of `main` (18 commits, no divergence).
  The repair branch therefore keeps the existing iOS 27 dictation work intact.

## Environment constraint that bounds every status below

This session runs on Linux with **no Swift toolchain**: no `swift`, `swiftc`,
`xcodebuild`, `xcrun`, no Xcode, no simulator, no Apple signing identity, no
CircleCI runner.

Therefore, in this checkpoint:

- No Swift file was compiled.
- No iOS or backend test suite was executed.
- No archive, export, IPA, codesign or TestFlight upload was produced.
- The CircleCI `ios27-dictation-probe-build64` job was **not** run and its
  branch/diff/build guards were **not** exercised.

Source-level correctness evidence only. Any "PASS" for compilation, archiving or
device behaviour would be fabricated.

## Cohort 1 — automotive domain ownership (production repair)

### Confirmed root cause at HEAD

`CanonicalDomainIntegrityPolicy.apply` decided automotive domain ownership from
`CanonicalAutomotiveEntityExtractor.brandAndModel`, which matched exactly three
marques via regex (BMW, Mercedes-Benz, Rolls-Royce). Consequences, all
reproducible from the source at `ef54b25`:

1. A purchase carrying a marque but no `офіційно` fell into the
   `product_catalog` branch — the generic commerce path that produced the
   historical Zara / Fozzy / Ukrposhta results.
2. A brandless vehicle purchase matched no marque at all, so it also reached
   `product_catalog` — the historical Prom.ua result for «Купити авто».
3. No open-world vehicle semantics existed, so a correct request for a sedan,
   crossover, EV or hybrid could not own the automotive domain.

Separately, `hasAmbiguousVehicleServiceGoal`
(`LanguageUnderstandingBlock.swift:217`) lists ordering roots
`["замов","закаж","book","order","request"]` and does **not** include `куп`.
That is why «Купити авто» never reached the existing typed vehicle-service
ambiguity and fell through to generic commerce instead.

### Repair

`UniversalAssistant/Core/CanonicalDomainRegistries.swift`

- Domain ownership now follows the meaning of the request, not a marque list:
  vehicle object semantics (авто / автомобіль / машина / body types /
  powertrain) plus ownership or dealer evidence.
- The brand/model is carried as data on `DomainEvidence`, never as the reason
  the domain was selected.
- The `product_catalog` automotive branch was removed entirely. An automotive
  request can no longer degrade into generic commerce.
- The pre-existing three verified marques remain trusted evidence on their own,
  so already verified marque-plus-official behaviour is preserved exactly.
- Guards keep the repair from displacing verified capabilities: public transport,
  parts/consumables/servicing, and any request already owned by `car_rental`,
  `vehicle_service` or `current_safety`.
- Open-world brand data is read as residual text only after vehicle semantics
  are established, with function words and vehicle vocabulary stripped and a
  length floor on the first token.

### Regressions added

`UniversalAssistantTests/LanguageUnderstandingBlockTests.swift`

- `automotiveDomainOwnershipFollowsRequestMeaningNotAMarqueList`
- `automotiveOwnershipIsOpenWorldOverVehicleObjectSemantics`
- `automotiveDomainOwnershipNeverDisplacesVerifiedCommerceOrCarRental`
- `automotiveDealerRequestsUseTheFreeGoogleMapsHandoff`

These assert the exact historical physical phrases plus unseen variants, and
they also assert that verified commerce and car-rental requests are *not*
captured. The pre-existing `build59AutomotiveEntitiesRemainOpenWorldPhysicalDealerQueries`
test is retained unchanged.

### How this was verified, and what that is worth

A faithful Python transcription of `CanonicalMorphology.forms(for:)` and the new
`domainEvidence` logic was executed over 31 cases: 3 preserved verified cases,
6 historical failure phrases, 6 open-world vehicle-type phrases, and 16
regression guards (sneakers, slippers, boots, bare vehicle ambiguity, car
rental, explicit rental, public transport, motor oil, consumables, tyres, car
service, car wash, spare parts, books, phone model token, verified marque plus
body type). All 31 passed.

That validates the **algorithm and its regression behaviour**. It is not a Swift
compile and not a substitute for one. Two defects were found and fixed this way
before committing: `vehiclePartsRoots` missed the Ukrainian «олія», and a
preposition («в») plus «салоні» leaked into the brand as `в салоні`.

## Cohort 2 — accepted-source content integrity

`docs/owner_sources/README_PROVENANCE.md` records that the `docs/` copies of the
Privacy, Loyalty, Audio and Live-Diagnostic addenda are one-line stubs: complete
ID sequences, lost requirement bodies. Reproducible SHA-256 values and worked
per-ID before/after proof are included. `docs/SPEC_SOURCE_OF_TRUTH.md` gained a
notice pointing auditors at the recovered text and at the IDs that remain
unverifiable.

`AUDIO-109…147` and `LIVE-DIAG-001…078` are marked `SOURCE_TEXT_REQUIRED`. The
owner instruction supplied Appendix A and B in full but ended Appendix C
mid-requirement at AUDIO-108 and contained no Appendix D body at all. No canon
was generated to fill either gap, and the historical stubs were left untouched
so their true hashes remain evidence.

## Still open — not attempted or not completed

- **Apple iOS 27 voice on iPhone SE 2 / iOS 27.** Requires the physical device
  and an Xcode 27 toolchain. Untouched. The contextual-bias question raised in
  the instruction (does `AnalysisContext.setContext` still bias the iOS 27 path
  via `ios27ApplicationContextualVocabulary`?) was **not** investigated.
- **Restaurant reservation.** `CanonicalDomainIntegrityPolicy` still rewrites a
  bare reservation into `placeSearch` (nearby restaurant in Maps). The instruction
  requires reservation to stay a booking flow. Confirmed present at HEAD, **not
  repaired** — changing it interacts with existing reservation/clarification
  tests that must be read before editing.
- **Route/address, Photos date, Photos semantic, apps/communications, safety**
  domains. Not audited to root cause in this session.
- **All provider integrations and their live/commercial verification.** Not
  audited. No provider adapter, credential, endpoint or partner status was
  touched or asserted.
- **Privacy, Loyalty, Audio, Jobs, Business, Finance, Diagnostics, Performance**
  audits. Not started. No data-flow map, capability registry entry or evidence
  matrix row was produced.
- No merge to `main`, no public release, no provider enrolment, no billing.

## Next step for the owner

One action, not a list: run the existing internal TestFlight candidate (or a
build from this branch once it can be compiled on Xcode 27) on the **iPhone SE 2
on iOS 27** and speak, in this order: «Відкрий Telegram», «Купити BMW сьомої
серії», «Купити авто». Record for each the Apple final transcript, the submitted
text, and the visible result. That single run is the only evidence that can
close either the voice cohort or the automotive cohort.
