# Voice Output Policy Addendum

Status: mandatory canonical addendum to Master Spec v13.2 and all accepted addenda. Accepted from the owner on 2026-09-02.

1. UniversalAssistant does not automatically speak long answers by default.
2. Voice output is used only when natural for the scenario: voice interaction, hands-free use, navigation, an explicit “say/read” request, a short critical warning, or when the screen is not the primary channel.
3. Ordinary informational results are shown on screen without automatic speech.
4. Do not unnecessarily duplicate the complete answer in speech and text.
5. Clear permitted actions follow DO, DON'T NARRATE: perform the action without phrases equivalent to “found it”, “opening”, or “doing it now”.
6. The policy is typed and configurable, has a persistent user preference, and is covered by behavioral tests.
7. This addendum augments and does not weaken MS-24, MS-25, MS-31 or the language/voice requirements beginning at MS-61.

Implementation evidence: `SpeechOutputPolicy`, `VoiceOutputPreferenceStore`, and `RuntimeExperiencePolicyTests`.
