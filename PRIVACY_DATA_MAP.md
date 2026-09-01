# Privacy Data Map

| Data | Storage | Purpose | Leaves device | Retention/deletion |
|---|---|---|---|---|
| Typed command (transient) | Memory | Parse current task | No at M0 | Cleared after routing |
| Structured preferences (planned) | App Support | Local personalization | No at M0 | User-clearable |
| Confirmed contact aliases | App Support | Map user-confirmed alias to exact local Contacts identifier | No | Replaceable/user-clearable |
| Action history | App Support | Undo assistant-created reversible actions | No | Bounded to 100 records |
| Audio recordings | App Support/Recordings with complete file protection | User-requested recording | No unless user explicitly shares | Renameable and deletable by user |

No production provider credentials or analytics are collected. System Contacts, Calendar, and Reminders records remain in their Apple-owned stores; only minimal exact identifiers/snapshots required for explicit undo are retained locally.
