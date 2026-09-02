# Owner Test Queue

Current recommended build: none; no current immutable signed build has been issued through `OwnerTestBuildRegistry`. Pending historical tests: 2. Estimated session: 5 minutes after a delivery channel, signing, and physical device are verified. Critical blocker: no verified delivery configuration. These tests can wait and do not block independent engineering work.

| Test ID | Feature/block | Build/commit | Prerequisites | Action | Expected result | Retest linkage | Status |
|---|---|---|---|---|---|---|---|
| VOICE-001 | M1 voice capture | Historical Build 1 / `948e5bd` | Microphone and Speech permissions | Tap the central microphone, allow permissions, say “Відкрий Telegram”, tap again | Listening state is visible; recognized text appears in input; microphone stops | Issue a new immutable build after delivery configuration is verified | NOT_TESTED |
| VOICE-002 | M1 system invocation | Historical Build 1 / `948e5bd` | Add the UniversalAssistant shortcut to an available system invocation surface | Run “Start UniversalAssistant” | App opens directly to its command screen | Issue a new immutable build after delivery configuration is verified | NOT_TESTED |
