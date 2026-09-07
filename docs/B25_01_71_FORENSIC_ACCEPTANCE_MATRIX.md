# Build 25 physical forensic and Build 26 acceptance matrix

Evidence key: **P** = owner physical report; **V** = privacy-safe VPS time-window
aggregate, not transcript-authoritative. No row is claimed physically fixed.

| ID | Physical observation | Build-25 route/divergence | General source correction / coverage | Build-26 status |
|---|---|---|---|---|
| B25-01 | Timer 2 min passed | AlarmKit timer | Preserve availability-gated AlarmKit; `AlarmKitProductionTests` | PRESERVED BUILD-25 PASS |
| B25-02 | 14:00 alarm clarified | Alarm time variants diverged | canonical alarm parser; `NaturalDateTimeResolverTests` | SOURCE REPAIRED — PHYSICAL RETEST REQUIRED |
| B25-03 | Spotify required extra UA step | `open` handoff narration | verified app handoff; renderer narration removed | SOURCE REPAIRED — PHYSICAL RETEST REQUIRED |
| B25-04 | Apple Music required extra UA step | `open` handoff narration | MusicKit/verified handoff; renderer cleanup tests | SOURCE REPAIRED — PHYSICAL RETEST REQUIRED |
| B25-05 | Files unavailable | open family missed Files | public document picker; system quick-action tests | SOURCE REPAIRED — PHYSICAL RETEST REQUIRED |
| B25-06 | Three photos; Open failed | non-newest list and `ph://` | newest PhotoKit asset + in-app sheet; `ApplePersonalSearchSourcesTests` | SOURCE REPAIRED — PHYSICAL RETEST REQUIRED |
| B25-07 | “найновіше” diverged | synonym missed | semantic photo intent convergence tests | SOURCE REPAIRED — PHYSICAL RETEST REQUIRED |
| B25-08 | Calendar list, not app | EventKit query selected | public EventKit in-app presentation; direct Calendar-app open unsupported | PUBLIC IOS LIMITATION — RETEST IN-APP PATH |
| B25-09 | Calendar-app synonym unavailable | open synonym missed | semantic open normalization; public EventKit fallback | SOURCE REPAIRED — PHYSICAL RETEST REQUIRED |
| B25-10 | Imperative first word often lost | Speech task/buffer race | task before capture + contextual vocabulary; `VoiceInputControllerTests` | SOURCE REPAIRED — PHYSICAL RETEST REQUIRED |
| B25-11 | Calendar create passed | EventKit create | preserve permission continuation; EventKit suites | PRESERVED BUILD-25 PASS |
| B25-12 | Oleg contact hung | synchronous Contacts query | async 3 s boundary/cancellation; `ContactsRequestLifecycleTests` | SOURCE REPAIRED — PHYSICAL RETEST REQUIRED |
| B25-13 | Sasha contact hung | same | same production-boundary coverage | SOURCE REPAIRED — PHYSICAL RETEST REQUIRED |
| B25-14 | QR corrupted then Google | ASR/entity + wrong fallback | contextual QR recovery + VisionKit scanner; OCR/voice suites | SOURCE REPAIRED — PHYSICAL RETEST REQUIRED |
| B25-15 | OCR went Google | OCR intent disconnected | public Vision/VisionKit typed presentation; `ProductionOCRTests` | SOURCE REPAIRED — PHYSICAL RETEST REQUIRED |
| B25-16 | Cafe not truly nearest | relevance outranked distance | nearest-only distance ordering; Places tests | SOURCE REPAIRED — PHYSICAL RETEST REQUIRED |
| B25-17 | Nike 0/3 and planner IDs | abstract executable nodes | concrete place→navigation lowering; multi-step suites | SOURCE REPAIRED — PHYSICAL RETEST REQUIRED |
| B25-18 | Product leaked planner then Google | bad compound plan/provider absent | simple concrete product intent; provider-required truthful handoff | EXTERNAL PROVIDER LIMITATION |
| B25-19 | Translation passed | public Translation | preserve source stripping; translation tests | PRESERVED BUILD-25 PASS |
| B25-20 | Apple site unavailable | official-site intent missed | verified official HTTPS handoff normalization | SOURCE REPAIRED — PHYSICAL RETEST REQUIRED |
| B25-21 | Baldinini entity changed | mixed-language entity loss | bounded contextual vocabulary/entity preservation tests | SOURCE REPAIRED — PHYSICAL RETEST REQUIRED |
| B25-22 | Apple stock manual Google | no live stock provider | typed current-info handoff; live provider required | EXTERNAL PROVIDER LIMITATION |
| B25-23 | President query manual Google | no production current-info coordinator | controlled sourced web handoff; provider audit | EXTERNAL PROVIDER LIMITATION |
| B25-24 | Natural dining went Google | constraints not mapped to Places | restaurant/place semantic normalization; Places tests | SOURCE REPAIRED — PHYSICAL RETEST REQUIRED |
| B25-25 | Natural navigation unavailable | route synonym missed | navigation convergence + MapKit handoff tests | SOURCE REPAIRED — PHYSICAL RETEST REQUIRED |
| B25-26 | Relative reminder clarified | relative time absent | minute/second relative resolver; EventKit tests | SOURCE REPAIRED — PHYSICAL RETEST REQUIRED |
| B25-27 | Tomorrow calendar went Google | personal query priority missed | EventKit calendarQuery normalization/tests | SOURCE REPAIRED — PHYSICAL RETEST REQUIRED |
| B25-28 | Voice-note save unclear | recorder UI lifecycle | typed AVFoundation recorder state; audio suites | SOURCE REPAIRED — PHYSICAL RETEST REQUIRED |
| B25-29 | Shopping constraints to Google | no live retail provider | constraints preserved in controlled handoff | EXTERNAL PROVIDER LIMITATION |
| B25-30 | Unrelated car photos/Open failed | semantic search guessed | fail-closed semantic matching + PhotoKit open | SOURCE REPAIRED — PHYSICAL RETEST REQUIRED |
| B25-31 | 15% of 2400 went Google | no local utility route | deterministic percentage engine; `LocalUtilityEngineTests` | SOURCE REPAIRED — PHYSICAL RETEST REQUIRED |
| B25-32 | Call mother unavailable | Contacts/call disconnected | bounded Contacts + public `tel:` | SOURCE REPAIRED — PHYSICAL RETEST REQUIRED |
| B25-33 | Dial synonym went Google | call synonym missed | call semantic convergence; call routing tests | SOURCE REPAIRED — PHYSICAL RETEST REQUIRED |
| B25-34 | Shared image follow-up ignored image | untyped context | typed image context + local Vision OCR tests | SOURCE REPAIRED — PHYSICAL RETEST REQUIRED |
| B25-35 | Translation follow-up went Google | source context lost | original-source translation context tests | SOURCE REPAIRED — PHYSICAL RETEST REQUIRED |
| B25-36 | Timer 30 sec passed | AlarmKit timer | preserve | PRESERVED BUILD-25 PASS |
| B25-37 | Alarm worked but said timer | result kind mislabeled | alarm/timer typed result separation tests | SOURCE REPAIRED — PHYSICAL RETEST REQUIRED |
| B25-38 | Note saved via Share Sheet | no public Notes creation API | shortest public Share Sheet handoff; Notes tests | PUBLIC IOS HANDOFF — RETEST UX |
| B25-39 | Railway route unavailable | destination synonym missed | canonical navigation extraction | SOURCE REPAIRED — PHYSICAL RETEST REQUIRED |
| B25-40 | Reminder title retained residue | payload sanitation incomplete | relative/day-period residue sanitizer; EventKit tests | SOURCE REPAIRED — PHYSICAL RETEST REQUIRED |
| B25-41 | Pharmacy clarified | category intent missed | MapKit pharmacy category tests | SOURCE REPAIRED — PHYSICAL RETEST REQUIRED |
| B25-42 | Drive time clarified/web | route duration family missed | MapKit route intent normalization | SOURCE REPAIRED — PHYSICAL RETEST REQUIRED |
| B25-43 | Gas station web | category priority missed | MapKit fuel category tests | SOURCE REPAIRED — PHYSICAL RETEST REQUIRED |
| B25-44 | Flashlight on clarified | system family missed | public AVFoundation torch | SOURCE REPAIRED — PHYSICAL RETEST REQUIRED |
| B25-45 | Flashlight off Google | same | local typed torch off | SOURCE REPAIRED — PHYSICAL RETEST REQUIRED |
| B25-46 | Brightness went Google | unsupported control fell through | truthful local unsupported result | PUBLIC IOS LIMITATION |
| B25-47 | Low Power Mode web | unsupported control fell through | truthful local unsupported result | PUBLIC IOS LIMITATION |
| B25-48 | Take photo opened Camera | third-party cannot silently press shutter | public in-app camera, user capture | PUBLIC IOS USER INTERACTION REQUIRED |
| B25-49 | Show alarms clarified | unsupported query fell through | AlarmKit capability-gated truthful handling | PUBLIC IOS LIMITATION — RETEST |
| B25-50 | 07:15 alarm inconsistent | time parser divergence | canonical 24-hour extraction tests | SOURCE REPAIRED — PHYSICAL RETEST REQUIRED |
| B25-51 | Explicit Wi-Fi settings unavailable | unsupported page request | truthful local limitation, no private scheme | PUBLIC IOS LIMITATION |
| B25-52 | Short Wi-Fi opened app settings | generic settings conflation | specific system-control intent precedes app settings | SOURCE REPAIRED — PHYSICAL RETEST REQUIRED |
| B25-53 | Bluetooth went Google | unsupported toggle fell through | truthful local limitation | PUBLIC IOS LIMITATION |
| B25-54 | Translation passed | public Translation | preserve | PRESERVED BUILD-25 PASS |
| B25-55 | 347×28 went Google | arithmetic family absent | deterministic multiplication E2E | SOURCE REPAIRED — PHYSICAL RETEST REQUIRED |
| B25-56 | FX clarified | currency intent absent | local intent; real current FX dependency | EXTERNAL PROVIDER LIMITATION |
| B25-57 | km→miles went Google | unit family absent | deterministic fixed-ratio units | SOURCE REPAIRED — PHYSICAL RETEST REQUIRED |
| B25-58 | day-of-week went Google | local temporal family absent | timezone-aware local utility | SOURCE REPAIRED — PHYSICAL RETEST REQUIRED |
| B25-59 | 125×8 went Google | arithmetic family absent | deterministic multiplication | SOURCE REPAIRED — PHYSICAL RETEST REQUIRED |
| B25-60 | Clipboard went Google | local action missed | public UIPasteboard typed action; NotesClipboard tests | SOURCE REPAIRED — PHYSICAL RETEST REQUIRED |
| B25-61 | File PDF search hung | synchronous security-scope metadata | async 3 s boundary/cancellation | SOURCE REPAIRED — PHYSICAL RETEST REQUIRED |
| B25-62 | USD/UAH clarified | currency family absent | typed FX intent; live source required | EXTERNAL PROVIDER LIMITATION |
| B25-63 | Free storage web | local read family missed | public volume capacity read | SOURCE REPAIRED — PHYSICAL RETEST REQUIRED |
| B25-64 | Missed calls clarified | forbidden call-history access | truthful local limitation | PUBLIC IOS LIMITATION |
| B25-65 | Battery clarified | local read family missed | public UIDevice battery read | SOURCE REPAIRED — PHYSICAL RETEST REQUIRED |
| B25-66 | Explicit number went Google | direct-number call not parsed | public `tel:` bypasses Contacts | SOURCE REPAIRED — PHYSICAL RETEST REQUIRED |
| B25-67 | Calculator app unavailable | no public reliable app-open route | truthful local limitation | PUBLIC IOS LIMITATION |
| B25-68 | Show contacts clarified | no public Contacts-app presentation route | truthful local limitation/search-by-name | PUBLIC IOS LIMITATION |
| B25-69 | Phone app unavailable | no public reliable Phone-app open route | truthful local limitation; `tel:` for calls | PUBLIC IOS LIMITATION |
| B25-70 | Volume control web | third-party system-volume control unavailable | truthful local limitation | PUBLIC IOS LIMITATION |
| B25-71 | New-note synonym went Google | synonym missed/payload residue | semantic note convergence + Share Sheet tests | SOURCE REPAIRED — PHYSICAL RETEST REQUIRED |

Matrix count: **71/71**. Evidence for exact observations is **P**; VPS **V**
supports only aggregate stage/route divergence described in
`B25_VPS_DIAGNOSTIC_CORRELATION.md`.
