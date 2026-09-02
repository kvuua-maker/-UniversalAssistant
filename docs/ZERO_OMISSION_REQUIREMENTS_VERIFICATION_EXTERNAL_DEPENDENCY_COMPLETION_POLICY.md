# MANDATORY CANONICAL ADDENDUM
## ZERO-OMISSION REQUIREMENTS VERIFICATION + EXTERNAL DEPENDENCY COMPLETION POLICY

Це обов'язкове доповнення до Master Spec v13.2 та ВСІХ уже прийнятих canonical addendum UniversalAssistant.

НЕ перезапускай і НЕ повторюй завершені milestones.
НЕ зупиняй поточний roadmap.
Збережи це правило в docs/ і canonical state та застосовуй до всіх поточних і майбутніх блоків.

## 1. ZERO-OMISSION RULE

ЖОДНА canonical requirement не може бути:
- пропущена;
- забута;
- мовчки відкладена;
- визнана виконаною лише через наявність документації;
- визнана виконаною лише через interface/protocol/type;
- визнана виконаною лише через placeholder/stub/mock;
- визнана виконаною лише через запис у roadmap;
- закрита фразою "architecturally supported";
- закрита фразою "future integration";
- закрита external blocker, якщо будь-яку частину можна реалізувати зараз.

Кожна вимога повинна мати фактичний доказ стану.

## 2. CANONICAL REQUIREMENT INVENTORY

Побудуй єдиний requirement inventory для:

- Master Spec v13.2;
- Marketplace Commerce & Affiliate Hub Addendum;
- Deterministic Multi-Step Coordination + Bounded AI Fallback Addendum;
- Business Partner Platform Addendum;
- усіх інших canonical addendum/docs, прийнятих owner.

Кожна окрема requirement повинна мати стабільний ID.

Жодна вимога не може зникнути при переході між milestones.

## 3. ДОЗВОЛЕНІ СТАТУСИ

Для implementation/compliance використовуй тільки чіткі стани:

NOT_IMPLEMENTED

IMPLEMENTED_UNVERIFIED

VERIFIED_LOCAL

READY_FOR_LIVE_VERIFICATION

VERIFIED_LIVE

NOT_APPLICABLE_VERIFIED

Не використовуй розмиті фінальні статуси:
PARTIAL
MOSTLY_DONE
ARCHITECTURALLY_READY
PLANNED
DOCUMENTED
FUTURE
BLOCKED
або аналогічні як заміну фактичному стану.

## 4. VERIFIED_LOCAL

VERIFIED_LOCAL дозволено тільки якщо завершено ВСЕ, що технічно можливо зробити без відсутнього зовнішнього ресурсу.

Це включає, де застосовно:

- production implementation;
- domain contracts;
- provider/client implementation;
- authentication/OAuth flow implementation;
- request/response parsing;
- validation;
- security;
- error handling;
- timeout;
- retries;
- cancellation;
- idempotency;
- fallback;
- UI;
- state handling;
- persistence;
- configuration;
- secret injection boundary;
- mocks/fakes;
- unit tests;
- integration tests;
- sandbox tests, якщо sandbox доступний;
- observability;
- privacy handling;
- accessibility where applicable.

Якщо щось із цього можна зробити зараз, але воно не зроблено:
статус НЕ може бути VERIFIED_LOCAL.

## 5. EXTERNAL DEPENDENCY НЕ Є ДОЗВОЛОМ НЕ РОБИТИ

Відсутність:

- API key;
- OAuth client credential;
- partner approval;
- production account;
- real provider account;
- paid account;
- external sandbox access;
- real iPhone/device;
- Apple entitlement;
- business contract;
- production endpoint;
- legal approval;
- іншого зовнішнього ресурсу

НЕ дозволяє відкласти всю requirement.

Codex зобов'язаний завершити всю реалізацію, яка можлива без цього ресурсу.

## 6. READY_FOR_LIVE_VERIFICATION

Цей статус дозволено тільки коли:

1. реалізація завершена настільки, наскільки це можливо локально;
2. automated/local tests проходять;
3. integration boundary готовий;
4. немає відомої локальної незавершеної роботи;
5. залишився тільки конкретний зовнішній verification step.

Для кожного такого пункту записати:

- requirement ID;
- provider/service;
- що вже реалізовано;
- що вже протестовано;
- точний відсутній external dependency;
- хто повинен його надати;
- точний live test, який треба виконати після отримання;
- expected verified result.

Не писати просто:
"Needs API key".

Писати конкретно:
"Implementation complete locally; requires X credential solely to execute Y live verification."

## 7. EXTERNAL DEPENDENCY НЕ БЛОКУЄ ROADMAP

READY_FOR_LIVE_VERIFICATION ніколи не зупиняє інші незалежні requirements/milestones.

Якщо live verification зараз неможлива:

→ додай requirement до LIVE VERIFICATION QUEUE;
→ зафіксуй dependency;
→ продовжуй наступну незалежну роботу.

Не чекай credential/account/device, якщо є інша робота.

## 8. LIVE VERIFICATION QUEUE

Створи persistent Live Verification Queue.

Для кожного item:

requirement_id
service/provider
current_status
missing_dependency
local_evidence
required_live_action
expected_result
created_at
last_checked
completion_evidence

Queue повинна переживати restart/resume і не губитися між milestones.

## 9. КОЛИ EXTERNAL RESOURCE З'ЯВЛЯЄТЬСЯ

Коли owner надає потрібний:

API key / account / credential / device / entitlement / approval / інший dependency,

Codex повинен:

1. знайти відповідні items у Live Verification Queue;
2. НЕ переписувати вже готовий модуль з нуля;
3. виконати тільки необхідне configuration/injection;
4. виконати real live test;
5. перевірити фактичний результат;
6. виправити implementation, якщо live test знайшов реальний defect;
7. повторити test;
8. змінити status на VERIFIED_LIVE тільки після доказу;
9. commit/push evidence/state update.

## 10. REAL INTEGRATION RULE

Якщо Master Spec вимагає REAL execution, mock test не може замінити live verification.

Наприклад Gmail:

без Google credentials потрібно завершити всю можливу Gmail implementation та local/integration testing.

Статус:
READY_FOR_LIVE_VERIFICATION.

Після отримання credentials:
реальний authorized Gmail operation → перевірка фактичного результату → тільки тоді VERIFIED_LIVE.

## 11. EVIDENCE CONTRACT

Кожен VERIFIED_LOCAL / VERIFIED_LIVE повинен мати evidence.

Мінімально:

requirement ID
→ implementation file/component
→ relevant test(s)
→ test result
→ commit
→ verification type.

Для VERIFIED_LIVE додатково:
→ provider/device/account execution evidence.

Не приймати self-declaration "done" без evidence.

## 12. REQUIREMENT-TO-TEST TRACEABILITY

Кожна testable canonical requirement повинна мати test coverage або documented reason, чому automated test фізично непридатний.

Тест повинен перевіряти поведінку requirement, а не лише існування type/function.

## 13. NO PLACEHOLDER COMPLETION

Placeholder, stub, mock-only provider, TODO, fake success, hardcoded demo response або documentation-only implementation НЕ є completion.

Mocks дозволені для local verification, але production path також повинен бути реалізований настільки, наскільки це можливо без external dependency.

## 14. NO FAKE SUCCESS

Ніколи не симулюй успішне:

- надсилання email/message;
- booking;
- purchase;
- payment;
- calendar mutation;
- provider action;
- API response;
- live availability;
- authentication;
- іншу зовнішню дію

для того, щоб закрити requirement.

Якщо live execution не перевірена:
позначити READY_FOR_LIVE_VERIFICATION.

## 15. FINAL ZERO-OMISSION AUDIT

Після завершення основного implementation roadmap виконай повний незалежний requirement-by-requirement audit.

Перевір КОЖНУ requirement Master Spec v13.2 + ВСІХ canonical addendum.

Для кожної покажи:

ID
status
implementation evidence
test evidence
commit evidence
live evidence where required
remaining dependency if any.

## 16. NOT_IMPLEMENTED MUST REACH ZERO

Після першого audit:

для кожного NOT_IMPLEMENTED або IMPLEMENTED_UNVERIFIED, який не потребує недоступного зовнішнього ресурсу:

→ реалізуй;
→ протестуй;
→ verify;
→ commit/push;
→ повтори audit.

Повторюй до:

NOT_IMPLEMENTED = 0
IMPLEMENTED_UNVERIFIED = 0

за винятком тільки тих конкретних live verification operations, які законно знаходяться у READY_FOR_LIVE_VERIFICATION.

## 17. READY_FOR_LIVE_VERIFICATION НЕ ОЗНАЧАЄ COMPLETE PRODUCT

Фінальний звіт повинен окремо показувати:

LOCAL IMPLEMENTATION COMPLETE

та

LIVE VERIFICATION REMAINING.

Не називай external integration VERIFIED_LIVE, доки вона реально не перевірена.

Але відсутність live credential не повинна залишати доступну локальну реалізацію недоробленою.

## 18. NO SILENT DE-SCOPING

Codex не має права самостійно вирішити, що requirement:
- занадто складна;
- неважлива;
- не потрібна V1;
- краще зробити пізніше;
- потребує забагато роботи

якщо вона canonical.

Зміна scope дозволена тільки explicit owner decision або доведена технічна/юридична неможливість.

## 19. TECHNICAL IMPOSSIBILITY

Якщо requirement реально заборонена або неможлива через iOS/provider/public API:

не вигадувати implementation.

Задокументувати:

- точну requirement;
- перевірений technical/legal limitation;
- evidence/source;
- максимально глибоку legitimate alternative;
- що саме реалізовано замість недоступної частини.

Реалізувати максимально можливу legitimate depth.

## 20. FINAL COMPLETION CONDITION

UniversalAssistant implementation не може бути оголошена повністю завершеною, доки:

NOT_IMPLEMENTED = 0
IMPLEMENTED_UNVERIFIED = 0

і кожна canonical requirement має один із допустимих доказових статусів:

VERIFIED_LOCAL
VERIFIED_LIVE
READY_FOR_LIVE_VERIFICATION
NOT_APPLICABLE_VERIFIED.

READY_FOR_LIVE_VERIFICATION допускається тільки через конкретний реально відсутній external dependency після завершення всієї можливої локальної роботи.

## 21. CONTINUATION RULE

Прийми це як canonical addendum.

Збережи в docs/.
Зафіксуй source/hash у canonical state.
Не переривай поточний незавершений блок.
Не повторюй завершені milestones.

Після прийняття продовжуй поточний canonical roadmap:

inspect
→ implement
→ build
→ test
→ fix
→ verify
→ state/docs
→ commit
→ push
→ next unfinished block.

External dependency ніколи не є причиною просто зупинити загальний roadmap.

Усі повідомлення owner — тільки українською.
