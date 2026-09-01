# Owner Test Queue

Current recommended build: not issued yet. Pending tests: 2. These tests can wait until a stable signed Owner Test Build is available.

| Test ID | Build/commit | Prerequisites | Action | Expected result | Status |
|---|---|---|---|---|---|
| VOICE-001 | Build 1 / `948e5bd` | Microphone and Speech permissions | Tap the central microphone, allow permissions, say “Відкрий Telegram”, tap again | Listening state is visible; recognized text appears in input; microphone stops | NOT_TESTED |
| VOICE-002 | Build 1 / `948e5bd` | Add the UniversalAssistant shortcut to an available system invocation surface | Run “Start UniversalAssistant” | App opens directly to its command screen | NOT_TESTED |
