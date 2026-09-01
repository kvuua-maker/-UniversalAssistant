# M2 Audio Recorder

- Internal recorder uses public `AVAudioRecorder`/`AVAudioPlayer` and a `playAndRecord` audio session.
- Explicit permission gate; recording never starts after denial.
- Start, pause, resume, stop, play, stop playback, rename, delete, and share-URL operations have a tested state machine.
- Recording/paused state is always visibly exposed in the native UI and accessibility tree.
- Files live in app support, use UUID names, validate rename paths, restrict deletion to the recordings directory, and apply complete file protection after stop.

Official API evidence verified 2026-09-01: https://developer.apple.com/documentation/avfaudio/avaudiorecorder

Verification: Development simulator suite passed 37 tests in 10 suites. Real microphone, interruption, route, playback, share, and protection checks remain `DEVICE_TEST_REQUIRED`.
