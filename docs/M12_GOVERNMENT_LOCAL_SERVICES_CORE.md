# M12 Government and Local Services Core

Requirements MS-1038–1042. Status: VERIFIED_LOCAL for every capability available without a government partnership; approved Diia partner execution is READY_FOR_LIVE_VERIFICATION.

The audit used current official sources only. The official Diia integration portal documents validation, document sharing/multisharing, Diia.Signature and authorization as partner integrations that require organizational technical setup and explicit user approval. It does not expose general private-document access to an unrelated client. The Kyiv city portal documents parking and Kyiv Digital transport, administrative and utility capabilities.

`GovernmentLocalServicesEngine` therefore exposes deterministic confirmed HTTPS handoffs to official Diia services, the Diia integration portal, Kyiv parking and Kyiv Digital. It labels the integration path `partnerApprovalRequired`, explicitly rejects private Diia document access, rejects third-party hosts for consequential actions, and extends the official-host policy through configuration rather than hardcoding every municipality. Utility payments reuse `BillsReceiptsDocumentsEngine` and remain confirmation-gated; only a configured official provider host is accepted.

Official evidence:

- `https://integration.diia.gov.ua/` and `https://integration.diia.gov.ua/sharing.html`
- `https://diia.gov.ua/services`
- `https://kyivcity.gov.ua/dorohy_transport_ta_parkovky/parkuvannia.html`
- `https://kyivcity.gov.ua/dorohy_transport_ta_parkovky/servisi_mobilnogo_zastosunku_kiv_tsifroviy.html`

Behavioral evidence in `GovernmentLocalServicesEngineTests`: official HTTPS and confirmation enforcement; third-party rejection; private-data denial; partner-depth labeling; and end-to-end official utility bill handoff. Full regression on 2026-09-02 passed 295 iOS tests across 74 suites and 79 backend tests across 22 suites. Commit evidence is the atomic commit containing this document and the referenced implementation/tests.
