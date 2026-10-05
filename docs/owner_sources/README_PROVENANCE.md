# OWNER SOURCES — RESTORATION PROVENANCE AND CONTENT-LOSS RECORD

Scope: the four canonical addenda whose GitHub copies were found to be
one-line stubs rather than the accepted requirement text, plus the two
appendices supplied in full inside the owner instruction.

This record exists so no future reader mistakes a stub for canon. Nothing here
changes any requirement. Requirement text was never edited, renumbered,
summarised or weakened to make behaviour look correct.

---

## 1. VERIFIED FACT: THE REPOSITORY COPIES ARE STUBS

Every one of the four addenda in `docs/` carries the correct, complete ID
sequence and a section tag per requirement, but replaces the operative body with
a one-line paraphrase. The ID inventory is therefore real while the requirement
text is lost. Provenance below is reproducible with `sha256sum` and `grep`.

| Repository file | Bytes | IDs | SHA-256 of repository copy |
| --- | --- | --- | --- |
| `docs/UniversalAssistant_Privacy_AI_Data_Flow_Hardening_FINAL_NUMBERED.txt` | 15980 | PRIVACY-001…168 | `2cd2094900eb086a176ba85a84f22555d9ba9d167132b8b5bfb33422dffe10ea` |
| `docs/UniversalAssistant_Loyalty_Discount_Attribution_Commission_Integrity_FINAL_NUMBERED.txt` | 7383 | LOYALTY-001…127 | `d08375c5fabc74cc493ebb2fd5f6a25cd48a857fb117504ab82240e21e005dc4` |
| `docs/UniversalAssistant_Universal_Audio_Device_Control_FINAL_NUMBERED.txt` | 20452 | AUDIO-001…147 | `50b594e3027f9b1f6ed446f9222e534430e33566b8ad3cd2b0d45f13d4708a50` |
| `docs/UniversalAssistant_Physical_Device_Live_Diagnostic_Loop_FINAL_NUMBERED.md` | 4809 | LIVE-DIAG-001…078 | `595edc4f61990fd97330883a79223505da8e115254ac273272628d5b4b8b1f63` |

### Worked proof of content loss (body text, not summary)

Repository copy versus accepted original:

| ID | Repository stub body | Accepted original body |
| --- | --- | --- |
| PRIVACY-001 | `mandatory canonical privacy authority` | «Цей файл є mandatory canonical source-of-truth для Privacy / AI Data-Flow Hardening scope UniversalAssistant. Не трактуй його як рекомендацію або brainstorming.» |
| PRIVACY-023 | `absolute NEVER_AI gate` | «Створи/перевір абсолютний NEVER_AI_PAYLOAD gate для AUTH_SECRET, PAYMENT_SECRET і CRYPTOGRAPHIC_SECRET.» |
| PRIVACY-025 | `AI never receives credentials or payment secrets` | «AI не повинен отримувати raw passwords, passkeys, refresh tokens, bearer/API secrets, private keys, signing keys, payment authorization secrets або equivalent credentials.» |
| PRIVACY-158 | `full privacy completion gate` | the full sixteen-clause completion condition of PRIVACY-158 |
| LOYALTY-001 | `mandatory canonical authority; preserve existing Core` | «Цей файл є mandatory canonical source-of-truth … Не змінюй owner-approved business model і не ламай вже реалізований Loyalty / Personal Price / Attribution Core.» |
| LOYALTY-126 | `never hide better price` | «FINAL RULE: NEVER HIDE A BETTER VALID USER PRICE SOLELY TO MAXIMIZE OUR COMMISSION.» |

The loss is not cosmetic. `PRIVACY-023` names the three payload classes that
make the NEVER_AI gate enforceable; the stub drops them, leaving a rule with no
identifiable subject.

### Consequence for the requirement inventory

`docs/SPEC_SOURCE_OF_TRUTH.md` presents these four files as the accepted
addenda with 168 / 127 / 147 independently tracked requirements. The ID counts
are accurate. The *text* behind those IDs was not present in the repository, so
no evidence matrix could have been audited against the real requirement wording
before this restoration. That is the specific gap this directory closes for
Appendices A and B.

---

## 2. RESTORED IN FULL FROM THE OWNER INSTRUCTION

These two sources were embedded verbatim in the owner instruction and are
restored without paraphrase, translation, omission or renumbering.

| Restored file | Source | IDs restored |
| --- | --- | --- |
| `PRIVACY_AI_DATA_FLOW_HARDENING_FINAL_NUMBERED.original.txt` | Appendix A of the owner instruction | PRIVACY-001…168, all 168 |
| `LOYALTY_DISCOUNT_ATTRIBUTION_COMMISSION_INTEGRITY_FINAL_NUMBERED.original.txt` | Appendix B of the owner instruction | LOYALTY-001…127, all 127 |

These files are **not** byte-identical to the historical stub copies, and are
not presented as such. They are the recovered originals; the stubs remain in
`docs/` untouched so their true hashes are preserved as evidence.

---

## 3. SOURCE_TEXT_REQUIRED — NOT RECOVERABLE FROM ANYTHING AVAILABLE

The owner instruction itself is incomplete for these two sources. No true
original was available anywhere, so no canon was generated.

### Appendix C — Universal Audio Device Control

- Instruction content ends **mid-requirement at AUDIO-108**, terminated by the
  bare fragment `AUDIO` with no tag and no body.
- Recovered: AUDIO-001…108.
- **Missing: AUDIO-109…147 — 39 requirements with no text at all.**
- The instruction's scope line and AUDIO-001…108 are recoverable and consistent
  with the repository stub, but the remaining 39 requirements cannot be
  reconstructed. Do not infer AUDIO-109…147 from the stub paraphrases: the stub
  bodies are lost content, not abbreviated canon.
- The repository copy (`docs/UniversalAssistant_Universal_Audio_Device_Control_FINAL_NUMBERED.txt`)
  retains all 147 IDs as stubs. Its AUDIO-109…147 entries are placeholders.
- Required to close: the accepted original text for AUDIO-109…147, including the
  end of AUDIO-108. Cannot be derived from this repository.

### Appendix D — Physical Device Live Diagnostic Loop

- The instruction references "APPENDIX D — Physical Device Live Diagnostic Loop,
  повний знайдений оригінал із секціями 0–41", but **the appendix body was not
  present in the received instruction at all**. No sections 0–41 were supplied.
- The repository holds `docs/UniversalAssistant_Physical_Device_Live_Diagnostic_Loop_FINAL_NUMBERED.md`
  with 78 stub requirements (LIVE-DIAG-001…078), including the VPS, SSL and App
  Attest requirements (for example LIVE-DIAG-050 `App Attest registration`,
  LIVE-DIAG-070 `Server-only deployment secrets`).
- **Every one of those 78 requirement bodies is lost.** Section numbering 0–41
  of the original does not correspond to the 78 ID entries.
- No IP, port, storage path, TLS or authentication design, deployment
  authorisation, or per-item semantics has been invented from a heading.
- Required to close: the accepted original text for LIVE-DIAG-001…078 with its
  sections 0–41. Cannot be derived from this repository.

---

## 4. WHAT THIS DOES NOT ESTABLISH

- Restoring a source is not permission to change a rule. No requirement wording
  was altered anywhere in this work.
- A stub ID inventory does not prove implementation. AUDIO-109…147 and
  LIVE-DIAG-001…078 remain unauditable against their real text until the
  originals are supplied.
- Until then, any status asserted for those IDs would be unverifiable and must
  be recorded as SOURCE_TEXT_REQUIRED rather than PASS, NOT_APPLICABLE, or
  ALREADY_IMPLEMENTED.
