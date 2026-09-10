# UniversalAssistant Build 32 — аудит наявної diagnostics architecture

Дата аудиту: 2026-09-10
Вихідний HEAD: `55d6e634cacf38078a3d96793f21b9c22e50f9b5`
Версія/build до змін: `0.1.0 (31)`
Scope: лише повторне використання та розширення наявної production diagnostics; без функціональних ремонтів.

## Фактична production architecture

| Компонент | Статус | Фактична реалізація | Висновок для Build 32 |
|---|---|---|---|
| Shipped composition root | ALREADY_EXISTS | `UniversalAssistantApp` створює `AssistantViewModel` через `ProductionAssistantComposition.makeModel()`; launch викликає recovered-session enqueue та `PhysicalDiagnosticDelivery.flush()` | Розширювати цей шлях; test-only або parallel pipeline не створювати |
| Request breadcrumbs | NEEDS_EXTENSION | `LocalVoiceDiagnosticReport` отримує markers від `VoiceInputController`, `AssistantViewModel`, Contacts і Weather | Зробити always-on для кожної typed/voice команди та повного canonical pipeline |
| Diagnostic session identity | NEEDS_EXTENSION | Є `PhysicalDiagnosticSession.sessionID`; немає окремих `diagnosticSessionID`, `requestID`, `requestGeneration` у transport schema | Додати versioned typed identity без зламу schema v1 |
| Request generation ownership | ALREADY_EXISTS | `AssistantViewModel.activeRequestGeneration`, Speech `activeSessionID`, stale callback guards | Diagnostics повинна записувати generation, не змінюючи ownership/behavior |
| Voice lifecycle markers | ALREADY_EXISTS | Speech permission, request/task, AVAudioSession, tap, buffers, partial/final state, interruption, route change, cancellation і stale suppression markers | Зберегти й відобразити у спільному event vocabulary |
| Full canonical trace | MISSING | Є ingress/router/execution/result markers, але немає повного normalization/language/morphology/numbers/entities/frame/candidates/system-first/context/dependency/permission/renderer contract | Додати observation hooks у реальний production path |
| Critical PRE/POST boundaries | MISSING | Окремого durable PRE/POST contract немає | Додати boundary enum і парні durable markers для всіх визначених Apple/provider operations |
| Active request persistence | BROKEN | `LocalVoiceDiagnosticReport.Persisted` пишеться в `UserDefaults`; durable copy навмисно видаляє details; terminal визначається евристикою markers | Перенести малий snapshot у Application Support, з last PRE/POST/capability/terminal і atomic write |
| Bounded event log | MISSING | In-memory entries bounded до 1000; delivery payload до 250; локального file-backed ring/append log немає | Додати JSONL ring із rotation, serial/atomic writes і tolerance до corrupted tail |
| Relaunch recovery | NEEDS_EXTENSION | `recoveredIncompleteSession()` одноразово створює failure `ProcessTerminatedBeforeTerminalResult` із last marker | Створювати `UNCLEAN_TERMINATION_DETECTED`, last durable stage, last PRE/POST і missing expected POST; висновок лише probable |
| Apple crash/hang diagnostics | MISSING | MetricKit subscriber/`MXDiagnosticPayload` ingest відсутній | Додати availability-guarded MetricKit до існуючого diagnostics lifecycle без підняття minimum OS |
| Final/normalized transcript | BROKEN | Markers зберігають лише `length`; backend schema навмисно забороняє ключі з `transcript` | Для owner-enabled detailed diagnostics дозволити bounded/redacted final і normalized transcript; raw audio заборонено |
| Privacy/redaction | NEEDS_EXTENSION | Client allowlist фільтрує attributes; server забороняє transcript/audio/contact/message/photo/document/location; App Attest metadata bounded | Зберегти fail-closed policy, додати typed privacy classes/hashes/redaction і окрему consent boundary для detailed transcripts |
| Local pending queue | BROKEN | `PhysicalDiagnosticDelivery` тримає до 20 sessions у `UserDefaults`; 24h; максимум 3 спроби | Перенести queue в Application Support; не видаляти server-rejected/offline records; bounded retention |
| Retry/backoff | BROKEN | Кожний enqueue/flush одразу пробує upload; attempts++ до 3; backoff/nextAttempt/idempotency status відсутні | Додати bounded exponential backoff, next attempt, durable states та session-based idempotency |
| Delivery states | NEEDS_EXTENSION | `queued/sending/delivered/failedRetryable/expired` лише in-memory actor state | Persist `LOCAL_EVENTS/PENDING_UPLOAD/UPLOADED/SERVER_REJECTED/RETRYING` з HTTP/schema error category |
| Duplicate prevention | ALREADY_EXISTS | Client не додає duplicate `sessionID`; server `DiagnosticSessionStore.put` idempotently приймає identical payload і відхиляє conflicting duplicate | Зберегти та додати durable receipt/idempotency tests |
| VPS transport | ALREADY_EXISTS | HTTPS pinning до `https://178.105.32.46`; `/v1/app-attest/challenge`, `/register`, `/v1/diagnostics`; per-request App Attest assertion | Розширити той самий endpoint/schema; новий diagnostics provider не створювати |
| App Attest bootstrap | ALREADY_EXISTS | Key generation/registration, production AAGUID verification, assertion counter/replay protection, bounded bootstrap-failure endpoint | Зберегти незмінним, окрім сумісної schema plumbing |
| Backend schema | BROKEN | `PhysicalDiagnosticSession.schemaVersion = 1`; дозволено тільки feature voice/request, два liveTestID та вузький marker allowlist; schema 2 відхиляється | Додати backward-compatible schema v2 для Build 32 та суворий typed validator |
| VPS persistent storage | ALREADY_EXISTS | `/mnt/HC_Volume_106589590/universalassistant-diagnostics/data/sessions`; atomic complete-protection JSON; 7 днів/500 records; окремі attestation/bootstrap stores | Зберегти, розширити reader/status/analysis даними schema v2 |
| Codex VPS reader | ALREADY_EXISTS | `Scripts/live_diagnostics.py`, локальний або strict SSH read-only lookup latest/session/failures/since | Розширити для requestID/sessionID/status/anomaly/Apple diagnostics read-back |
| Automatic analyzer | MISSING | Автоматичної evidence-based first-anomalous-stage classification немає | Додати deterministic analyzer з заданими класами й confirmed/probable/unknown certainty |
| Diagnostics UI | BROKEN | `AssistantSettingsView` має лише кнопку `Скопіювати діагностику`; status/session/pending/upload/anomaly/consent/export відсутні | Розширити існуючий settings diagnostics section; окремий parallel screen не створювати |
| Export fallback | MISSING | Є текстовий clipboard snapshot; ZIP package contract відсутній | Додати один bounded ZIP-compatible diagnostics package через існуючий UI лише як emergency fallback |
| Always-on behavior | BROKEN | У TestFlight enablement залежить від `AppTransaction` sandbox для upload, але request journal reset/terminal delivery не гарантують кожну typed/voice команду; detailed consent відсутній | Basic breadcrumbs always-on у Build 32; upload лишається internal-TestFlight fail-closed; detailed transcript — persistent owner consent |
| Logger isolation | NEEDS_EXTENSION | `record()` синхронно пише `UserDefaults` і `OSLog`; помилки encode/write поглинаються | File logger має бути non-throwing назовні, bounded і не змінювати branch/result/fallback; критичний PRE durable |
| Tests | NEEDS_EXTENSION | Є unit tests enablement, bounded queue, dedupe, bootstrap privacy, relaunch recovery, server schema/security/retention | Додати production-root trace, relaunch/file corruption, PRE-without-POST, transcript consent/redaction, offline retry/ACK/dedupe, analyzer, MetricKit mapping, UI status/export, real VPS round-trip |
| Raw microphone audio | NOT_APPLICABLE | Не записується | Не додавати |
| Full contacts/messages/photos/files/GPS payloads | NOT_APPLICABLE | Поточний backend відхиляє такі поля | Не додавати; лише hash/type/count/coarse role/status |
| Custom signal/exception crash handler | NOT_APPLICABLE | Відсутній | Не створювати; використовувати pre-crash durable state + MetricKit |

## Точні існуючі точки повторного використання

- Client model/uploader: `UniversalAssistant/Diagnostics/PhysicalDiagnosticDelivery.swift` — `PhysicalDiagnosticSession`, `PhysicalDiagnosticEvent`, `PhysicalDiagnosticDelivery`, `URLSessionDiagnosticTransport`, App Attest flow.
- Active voice/request trace: `UniversalAssistant/Voice/VoiceInputController.swift` — `LocalVoiceDiagnosticReport` та Speech/audio marker call sites.
- Shipped request path: `UniversalAssistant/Core/AssistantViewModel.swift` — `submit()`, `executeCanonicalCapability`, confirmation/continuation/result delivery.
- Shipped composition/launch recovery: `UniversalAssistant/App/UniversalAssistantApp.swift` — `ProductionAssistantComposition`, launch enqueue/flush.
- Existing UI: `UniversalAssistant/App/AssistantSettingsView.swift` — `settings.copy-voice-diagnostics`.
- Additional production boundaries already emitting markers: `UniversalAssistant/Contacts/LocalContactResolver.swift`, `UniversalAssistant/Weather/WeatherKitProvider.swift`.
- Backend: `Backend/Sources/UniversalAssistantServer/PhysicalDiagnostics.swift` — `DiagnosticSessionStore`, `ProductionAppAttestVerifier`, `configurePhysicalDiagnostics`.
- Read-only VPS reader: `Scripts/live_diagnostics.py`.
- Existing client/server tests: `UniversalAssistantTests/PhysicalDiagnosticDeliveryTests.swift`, `Backend/Tests/UniversalAssistantServerTests/PhysicalDiagnosticsTests.swift`.
- Canonical prior requirements: `docs/UniversalAssistant_Physical_Device_Live_Diagnostic_Loop_FINAL_NUMBERED.md` and `docs/PHYSICAL_DIAGNOSTIC_LOOP_EVIDENCE.md`.

## Confirmed endpoint і storage

- Production endpoint: `https://178.105.32.46/v1/diagnostics`.
- Authentication: App Attest key registration + one-time challenge + assertion counter/replay protection.
- VPS storage root configured by deployment: `/mnt/HC_Volume_106589590/universalassistant-diagnostics/data`.
- Session files: `.../sessions/<session-id>.json`; bootstrap failures: `.../bootstrap/<report-id>.json`; attestation registration: `.../attestation/app-attest-keys.json`.

## Порядок material extension

1. Розширити наявну client/server schema до backward-compatible v2 з typed request identity, terminal state, transcript consent/redaction, delivery/anomaly metadata.
2. Замінити `UserDefaults` event/queue persistence на існуючій delivery path file-backed Application Support snapshot + bounded JSONL/queue, з migration v1.
3. Підключити full production pipeline і durable PRE/POST до `LocalVoiceDiagnosticReport`/`AssistantViewModel` та реальних executor boundaries, не змінюючи поведінку команд.
4. Додати MetricKit ingest, analyzer, існуючий Settings UI status/consent/export.
5. Розгорнути backward-compatible backend, довести real VPS round-trip/read-back, потім усі 20 acceptance criteria.

## Поточний статус acceptance gate

Жоден із 20 критеріїв не позначається GREEN лише на підставі цього аудиту. Existing evidence дає часткове покриття composition root, voice markers, App Attest, bounded VPS storage та deduplication, але повний Build-32 black-box contract ще не реалізований і не перевірений.






## Firebase Crashlytics integration checkpoint — 2026-09-10

Цей розділ є актуальним continuation для diagnostics-only Build 32. Попередній план розширення VPS schema/backend вище зберігається як історичний audit evidence, але для поточного task шлях VPS/Linux **CLOSED**: Build 30/31 payloads відхилялися HTTP 400 через schema incompatibility, і новий VPS backend не розробляється та не розгортається.

### Реалізовано через повторне використання existing diagnostics

- Official Firebase Apple SDK `12.19.0` зафіксований у SwiftPM; application target напряму використовує лише `FirebaseCore` і `FirebaseCrashlytics`. Share Extension Firebase не лінкує.
- `GoogleService-Info.plist` належить application target і відповідає bundle ID `com.universalassistant.app` та Firebase app ID `1:209684650216:ios:1fdab1606235f9a758915d`.
- `FirebaseApp.configure()` виконується у реальному `Production` startup path `UniversalAssistantApp.init()` до створення `ProductionAssistantComposition`.
- `CrashlyticsDiagnosticBridge` є side-car adapter над existing `LocalVoiceDiagnosticReport`: зберігає існуючі session/request/generation identities, ordered markers, PRE/POST, full final/normalized transcripts за existing detailed-diagnostics consent, semantic/capability/route/executor/result metadata і максимум один terminal non-fatal `UA_DIAGNOSTIC_COMMAND_TRACE` на request.
- Secret-like values redacted; provider-size truncation фіксується length/hash/truncated marker. Raw microphone audio не записується.
- Official Crashlytics build phase використано для dSYM upload у `Production`; власний symbol uploader не створено.

### Реальний Firebase ingestion/read-back evidence

Firebase Console фактично показав trace для request `49C8F2CC-582E-4AD2-BF53-0946BDDCEF98`, diagnostics session `F69B2B03-CC88-471C-9AAB-F4225D28F332`, generation `2`:

- full normalized input: `який зараз рівень заряду акумулятора пристрою?`, `ua_normalized_truncated=0`, плюс length і SHA-256;
- selected capability `deviceAction`, `ua_system_first_decision=true`, `ua_generic_web=false`, reason `canonical_non_web_intent`;
- executor `deviceAction`, `EXECUTOR_PRE` і `EXECUTOR_POST`;
- result `execution_failed`, terminal state `ERROR`, elapsed `106 ms`;
- ordered Firebase logs містять capability selection, system-first/router decision, execution/permission, PRE/POST, failure та terminal sequence.

Це є **REAL FIREBASE INGESTION + READ-BACK PASS** для typed production trace. Скріншот не показує issue title/type, тому сам по собі не є доказом server-side fatal classification. Full spoken transcript також ще не може бути фізично доведений на цьому Mac: відсутній microphone input, а `simctl` не має legitimate audio-injection path. Його verification належить фізичному TestFlight Build 32, без synthetic/fake evidence.

### dSYM, archive і signing evidence

- Preflight archive: `/tmp/UniversalAssistantFirebasePreflight31.xcarchive`.
- Main binary/dSYM UUID match: `1BA740EF-B706-3D51-BF9C-575D6587C776` (`arm64`).
- Share Extension binary/dSYM UUID match: `F4253DBD-FFBB-32C2-ABB9-C3990F1C1BF3`.
- Official `upload-symbols` completed: `Successfully submitted symbols for architecture arm64 with UUID 1ba740ef...` and `Successfully uploaded Crashlytics symbols`.
- Main app and Share Extension signatures pass strict verification; Apple Distribution Team `9V5XXDXF3N`; `get-task-allow=false`; production entitlements/profile evidence remains intact.

### Automated validation

- Crashlytics focused integration: `5/5 PASS` — `/tmp/ua-firebase-focused-isolated-dd/Logs/Test/Test-UniversalAssistant-2026.09.10_18-52-07-+0200.xcresult`.
- Voice ownership + dependency/license targeted protection: `7/7 PASS`.
- Strengthened exact dependency/license allowlist after final assertions: `2/2 PASS` — `/tmp/ua-firebase-full-ios-arm64-dd/Logs/Test/Test-UniversalAssistant-2026.09.10_20-40-31-+0200.xcresult`.
- Full iOS arm64 Simulator: `891/891 PASS` in 154 suites — `/tmp/ua-firebase-full-ios-arm64-dd/Logs/Test/Test-UniversalAssistant-2026.09.10_20-37-09-+0200.xcresult`.
- Development compile: PASS. Production Simulator compile: PASS.
- First full multi-architecture Simulator attempt failed before assertions because Firebase static SwiftPM products were arm64 while Xcode also attempted x86_64. Це classified test-infrastructure mismatch; production source не змінювався. Materially different arm64-only run reached assertions and passed 891/891.

### Точний continuation

1. Зафіксувати Firebase/local diagnostics source checkpoint, не включаючи CLOSED VPS/Linux deployment work у Build 32.
2. Increment build `31 → 32`, без функціональних змін.
3. Production archive, signing/Share Extension/entitlements verification, official dSYM upload, IPA export/SHA-256 і TestFlight upload.
4. Після встановлення Build 32 власник фізично перевіряє voice transcript і crash/non-fatal collection; **AUTOMATED VERIFIED ≠ PHYSICAL IPHONE VERIFIED**.
