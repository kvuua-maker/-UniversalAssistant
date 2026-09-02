# MANDATORY CANONICAL QUICK LAUNCH / PHYSICAL ACCESS ADDENDUM

This supplements the canonical Visual/UI/UX Addendum and Master Spec without interrupting global ZERO-OMISSION reconciliation.

UniversalAssistant must provide the shortest legitimate system launch directly into voice listening mode. On a device with Action Button, recommend the user-configured Action Button → UniversalAssistant Voice Mode as primary and Back Tap as an alternative/additional launch. Without Action Button, recommend only supported options from Back Tap, Siri/App Shortcut, Home Screen Widget/Shortcut, with AssistiveTouch as an accessibility fallback. Never claim a capability unsupported by the device/iOS.

Provide a clear in-app “Швидкий запуск” screen driven by typed system capabilities and showing only legitimate available options. Where iOS requires manual assignment, provide the minimum steps and never claim the app can reassign a physical button itself.

Canonical configured path: Action Button / Back Tap / Siri-App Shortcut / Widget or Home Screen Shortcut → app launch → voice listening. If microphone and speech permissions are already granted, enter “Слухаю…” with no intermediate screen or extra tap. If missing, show only the required permission flow. If voice is unavailable, fall back truthfully to text input.

Strict DO, DON'T NARRATE: no “Відкриваю помічника”, “Готовий слухати” or similar pre-listening narration.

Use only official Apple mechanisms: App Intents, App Shortcuts, Shortcuts and system-supported launch paths, widgets and available accessibility mechanisms. No private APIs, physical-button interception or false ownership of Action Button/Back Tap.

Capability detection, routing and configuration must be typed and testable. Behavioral evidence must cover Action Button available/unavailable, Back Tap, Siri/App Shortcut, Home Screen Widget/Shortcut fallback, missing voice permission, unsupported capability and direct launch-to-listening.

After implementation: build, test, evidence, state/docs, atomic commit/push, then continue MS-117+ and global ZERO-OMISSION reconciliation.
