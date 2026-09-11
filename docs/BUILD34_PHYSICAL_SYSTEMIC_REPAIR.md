# UniversalAssistant Build 34 physical systemic repair

Date: `2026-09-11`

Authoritative physical baseline: TestFlight `0.1.0 (34)` on the owner's
`iPhone12,8` (iPhone SE, 2nd generation), iOS `26.6.2`. Starting repository
HEAD: `7032bd2a00979dd9e472d7f93b46306f90ed6191`.

This artifact records repair evidence. It does not claim physical success for
the repaired source. `AUTOMATED VERIFIED` is not `PHYSICAL IPHONE VERIFIED`.

## Physical Crashlytics evidence

- Fatal issue `62da7fe5f9324f7f559c6122e3baf7e1` contains two Build-34 events from
  `iPhone12,8` / iOS `26.6.2`: `2262678734288841813` and
  `2262661353858513552`.
- Both are symbolicated to
  `AppleVoiceAudioCaptureBackend.installTap(_:)`, historical source
  `VoiceInputController.swift:593`.
- Firebase reports the AVFAudio exception `Failed to create tap due to format
  mismatch` for a one-channel, 44.1 kHz Float32 format. The durable trace shows
  the active `AVAudioSession` at 48 kHz followed by an explicitly installed
  44.1 kHz tap. The next request stops at `contacts_context_vocabulary` before
  `SPEECH_START_PRE`; no semantic/contact executor ran for that crash.
- A preceding complete physical command proves normal Speech delivery order:
  six growing partials, `end_audio_called`, then one final transcript and the
  shared semantic/router/executor pipeline. Detailed transcript consent was off
  in that captured event, so absent raw words are not inferred.
- The Build-34 non-fatal issue contains production route evidence for typed
  capability/executor/terminal states, but does not provide a separate
  symbolicated Contacts crash. Functional family repairs below therefore use
  physical symptoms plus shipped-root targeted reproduction; this distinction
  is preserved rather than inventing missing crash evidence.

## First wrong stages and general mechanism repairs

| Family | First wrong production stage / root cause | General in-place repair |
|---|---|---|
| Speech capture crash | `AVAudioSession` negotiated a new hardware rate while a reused `AVAudioEngine` graph supplied its stale explicit tap format; AVFAudio raises an Objective-C exception before Swift can catch it | Activate the session first, materialize a fresh engine for that route, validate the live input format and install the input tap with `format:nil` so AVFAudio uses the negotiated hardware format; bounded teardown removes tap, resets and discards the graph |
| Speech clipping/end point | A fixed delay after a partial could call `endAudio` while quieter speech buffers were still arriving | Thread-safe buffer RMS activity tracks real recent speech and boundedly defers end-of-speech finalization; ownership/cancellation and final-result semantics remain unchanged |
| Ukrainian normalization | `.diacriticInsensitive` folding changed Cyrillic lexical letters, including Ukrainian `й`, before morphology/action analysis | Preserve Cyrillic orthography; use diacritic folding only for Latin proper names; voice and typed input continue through the same `LanguageUnderstandingBlock` |
| App/service entities | Truncated/mixed-script candidates could reach the generic ambiguity gate before the verified APP/SERVICE domain had a safe unique winner | Keep recovery constrained to typed candidate domains and confidence margin; retain verified app/service registries and fail closed for genuinely ambiguous or unavailable apps; no physical-word substitution table was added |
| Contacts | `CNContact` name predicates were treated as identity evidence, and a sole fuzzy predicate result could be selected even when its name did not safely match the query | Treat predicate output only as candidates, validate normalized name/nickname/organization/relation aliases with the canonical scoped resolver, and fall back to the bounded privacy-authorized domain; unsafe fuzzy results become no-result/clarification, never another person |
| Contact/email payload | The shared contact representation omitted email and relation aliases | Fetch public `CNContact` nickname, relations and email keys once in the same resolver; email composition uses the resolved address or returns a truthful missing/ambiguous state |
| Clarification continuation | UI choices did not durably retain the originating typed command, semantic role and request generation | Store one generation-owned typed selection continuation; the chosen app/contact/phone/channel/vehicle role resumes the same canonical executor, and stale/superseded selections are ignored |
| Timer/alarm/calendar/reminder | Quantified time words and payload nouns could steal ACTION/OBJECT ownership; calendar meeting text could collide with reminders | Preserve typed duration/clock/date roles before selection, give explicit reminder imperatives structural ownership, and keep calendar event creation distinct from reminder creation and global Clock limitations |
| Photos | Latest-photo behavior was overloaded for all photo queries; metadata/content queries lacked distinct bounded execution and all-photos presentation | Split recent/all/metadata/semantic query kinds; use bounded PhotoKit metadata search for dates/locations, public photo picker for all photos, and bounded Vision/Core ML classification for content with confidence/no-result |
| Files/PDF | File-type search words could fall into generic clarification although the source/type were sufficient | Keep `fileSearch` structural ownership for find/open PDF and preserve the public UIDocumentPicker/PDF workflow boundary |
| Audio routes | Local iPhone audio-route intents lacked a public system presentation and escaped to web | Route the typed system action to `AVRoutePickerView`; unsupported programmatic device selection remains a truthful Apple boundary, never Google |
| Products/grocery/taxi | Missing commercial providers were converted to generic browser success | Preserve provider-neutral typed constraints and return `PROVIDER_REQUIRED`; deliberate browser continuation remains only for canonically allowed informational domains |
| Car service | Bare vehicle ordering and explicit rental were conflated with product/web search | Require separate VEHICLE + RENTAL + service-goal evidence for typed car rental; bare ordering yields one typed taxi-vs-rental clarification; explicit rental uses MapKit/local service handoffs |
| Restaurant | Complete slot payloads still inherited generic clarification, and cancel confirmation could resume the EventKit branch | Preserve date/time/party/restaurant roles, ask only for actually missing slots, and resume booking/modify/cancel through the verified reservation executor/provider state; no booking reference means truthful provider-required, never fake success |

## Generalization and production reachability evidence

New tests intentionally use contacts, places, dates, applications, objects,
vehicles, message channels and formulations outside the owner's physical phrase
list. They cover inflections, reordered commands, noisy/mixed-script entities,
typed Release-root execution, negative examples and real ambiguity.

- Final affected confirmation/provider/Contacts verification: `9/9 PASS`,
  xcresult `Test-UniversalAssistant-2026.09.11_15-41-10-+0200.xcresult`.
- Full arm64 iOS Simulator gate on installed UUID
  `76E180BA-1F99-4E7E-A9B1-3B907D09F76D`: official xcresult summary
  `936/936 PASS`, zero failures/skips, including dynamic parameterized cases;
  `157` suites. Result:
  `/tmp/ua-build34-full-dd/Logs/Test/Test-UniversalAssistant-2026.09.11_15-42-30-+0200.xcresult`.
- Affected suites inside that immutable result include: Build-34 systemic
  semantics `10/10`, voice capture lifecycle `16/16`, voice input ownership
  `6/6`, voice/text quality `13/13`, Contacts lifecycle `14/14`, Contacts
  framework Release integration `1/1`, Production messaging `5/5`, restaurant
  Release root `3/3`, Crashlytics side-car `5/5`, and all Build-29 shipped
  Release-root inventory suites PASS.
- Production device compile, including main app and Share Extension:
  `** BUILD SUCCEEDED **` at `/tmp/ua-build35-production-dd`.
- `git diff --check`: PASS.

The Simulator evidence is device-agnostic automated verification. It is not a
physical result from the owner's `iPhone12,8`.

## Preserved boundaries

- Protected Build-34 working paths remain covered: reminders, timer executor,
  latest photos, Spotify/Apple Music, Files/PDF open, navigation, current
  location/city/weather, translation, arithmetic, battery/storage and contact
  lookup.
- Live commerce, grocery, ride, restaurant-booking and other commercial data
  remain at their documented credential/contract/provider boundaries. No price,
  availability or booking was fabricated.
- ShazamKit remains an Apple/App-ID/profile owner boundary.
- Crashlytics request IDs, PRE/POST breadcrumbs, semantic/capability/executor
  decisions and terminal traces remain instrumented.

Status: **GENERAL MECHANISM REPAIR IMPLEMENTED + AUTOMATED VERIFIED; BUILD-35
PHYSICAL TESTFLIGHT VERIFICATION REQUIRED**.
