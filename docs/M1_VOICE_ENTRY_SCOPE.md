# M1 Voice Entry Scope Pack

- Task: M1-VOICE-ENTRY
- Requirements: 38–43, 58, 274–276, 320, 327–330, 409–410, 570, 592, 596, 840–842, 1144–1154, 1470–1472, 1505
- Path: public Speech + AVFoundation APIs and App Intents
- Acceptance: contextual authorization, live partial transcript, one active recognition task, explicit stop/cancel, concise denied state, App Intent opens the app
- Evidence: E2 build plus deterministic state tests; physical microphone/permission/audio route remains E5 `DEVICE_TEST_REQUIRED`
- Stop condition: build/tests pass and exact owner-device test is queued
