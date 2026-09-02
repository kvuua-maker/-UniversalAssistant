# M12 Messaging Core

Requirements MS-941–948. Local implementation status: VERIFIED_LOCAL. Installed-app/system composer observation: READY_FOR_LIVE_VERIFICATION.

`SystemMessageComposer` is the public MessageUI production surface for SMS/iMessage drafts; the user remains the sender and UniversalAssistant never claims inbox/history access. `MessengerHandoffPlanner` validates recipients and produces encoded, exact public handoffs for WhatsApp click-to-chat, Telegram username context and Viber share. Signal returns the shortest legitimate system-share alternative because no verified public consumer automation/history contract is claimed.

The typed capability evidence explicitly distinguishes FIND, OPEN_CHAT, COMPOSE, SEND, CALL, SEARCH_HISTORY, APP_INTENT, DEEPLINK and API. No messenger is marked SEND because every implemented path leaves final sending under user control. Four behavioral tests cover MessageUI planning/no history claim, exact encoded contexts, invalid recipients/Signal fallback and confirmation integrity.

Full regression on 2026-09-02: 255 iOS tests across 65 suites and 78 backend tests across 22 suites passed; canonical JSON and diff checks passed.
