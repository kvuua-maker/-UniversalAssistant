# M11 Accessibility, Audio and Contextual Permissions Core

Requirements MS-838–MS-845.

| ID | Status | Evidence |
| --- | --- | --- |
| MS-838 | VERIFIED_LOCAL | Every voice submission has the always-visible `assistant.input` TextField path; UI and view-model behavior tested |
| MS-839 | VERIFIED_LOCAL | Localized voice-input toggle disables microphone startup while typed commands remain functional |
| MS-840 | VERIFIED_LOCAL | Voice and recorder activate/deactivate AVAudioSession explicitly and stop/pause deterministically |
| MS-841 | READY_FOR_LIVE_VERIFICATION | Production AVAudioSession interruption notification bridge is implemented; state recovery tested locally; physical call/Siri/alarm verification queued |
| MS-842 | READY_FOR_LIVE_VERIFICATION | `.allowBluetoothHFP` and production route-change bridge are implemented; route-change pause tested; physical headsets queued |
| MS-843 | VERIFIED_LOCAL | Context policy distinguishes reduced accuracy and requests temporary precision only for navigation/emergency; engine otherwise uses task-specific when-in-use accuracy |
| MS-844 | VERIFIED_LOCAL | Product requests only when-in-use/single-location access and declares no background-location mode |
| MS-845 | VERIFIED_LOCAL | Policy returns no permission at app launch and notification permission only after explicit proactive enablement |

Verification: 7 targeted accessibility/audio/localization tests passed; full iOS regression passed 230 tests in 58 suites; backend regression passed 76 tests in 21 suites. The only remaining work is the exact physical-device behavior listed in `LIVE_VERIFICATION_QUEUE.json`.
