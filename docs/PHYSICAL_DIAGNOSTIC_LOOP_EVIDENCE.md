# Physical Diagnostic Loop Evidence

Date: 2026-09-05. Canonical IDs: LIVE-DIAG-001…078. Canonical artifact SHA-256: `595edc4f61990fd97330883a79223505da8e115254ac273272628d5b4b8b1f63`.

## Reused architecture and production path

The implementation reuses `UniversalAssistantServer`, `VoiceInputEvent`/`LocalVoiceDiagnosticReport`, the existing voice controller/view model, privacy-safe marker policy, TestFlight Production configuration, and the owner-authorized VPS. It adds no analytics provider, public read API, product capability, voice semantic change, or AI dependency.

Internal TestFlight app → trusted HTTPS `178.105.32.46` → nginx exact-route proxy → `127.0.0.1:8787` existing server → App Attest validation → bounded files on the existing data volume. Codex reads the store through owner-authorized SSH with `Scripts/live_diagnostics.py`; no Internet read endpoint exists.

## Allowed and forbidden data

Allowed: schema/session/live-test IDs, build/app/OS/device class, timestamps/duration/result/failure stage, safe state markers, counts, boolean/configuration state, safe route types, and error domain/code. Forbidden by client construction and server allowlist: transcript text, raw audio, passwords, credentials/tokens/cookies, payment/signing/cryptographic secrets, contacts/messages/photos/documents, precise location, arbitrary fields, and unrestricted JSON/files.

## App Attest and transport

`PhysicalDiagnosticDelivery` uses official `DCAppAttestService`: supported-state check, device-protected key generation, one-time server challenge, key attestation, and body-bound request assertion. TestFlight is configured for production App Attest. Server verification binds Team ID `9V5XXDXF3N`, bundle `com.universalassistant.app`, RP ID, production AAGUID, public key, challenge, request body, and monotonic counter. Unsupported/failure has no static-secret fallback and cannot break voice behavior.

Public routes are only `POST /v1/app-attest/challenge`, `POST /v1/app-attest/register`, `POST /v1/app-attest/bootstrap-failure`, and `POST /v1/diagnostics`. The bootstrap-failure route is observational and pre-attestation only: it accepts an exact, versioned allowlist of App Attest bootstrap markers for Internal TestFlight build 12+, rejects arbitrary/unknown/sensitive fields, is limited to 8 KiB and three requests per minute with a bounded burst, and exposes no read operation. It does not weaken or bypass normal App Attest registration or authenticated diagnostic ingest. Application port 8787 is localhost-only. Deployed probes confirm typed challenge issuance (200), malformed bootstrap schema rejection (400), and unknown route rejection (404); the existing authenticated endpoint remains unchanged.

## Storage, retry, and operations

Client queue: maximum 20 sessions, 24-hour expiry, three attempts, session-ID deduplication, asynchronous/nonblocking upload. Server: schema version 1, marker/attribute allowlist, 96 KiB transport bound, seven-day retention, maximum 500 authenticated records, deterministic session-ID deduplication, indexed filesystem identity. Pre-attestation bootstrap failures use a separate seven-day/100-record bounded store. Daily retention timer is enabled. Diagnostic delivery state is separate from product result.

VPS storage is `/mnt/HC_Volume_106589590/universalassistant-diagnostics/data` mode 0700. Service runs as `universalassistant`, is systemd-hardened, capped at 256 MiB/50% CPU/128 tasks, and consumed about 5 MiB after deployment. Ports: 22, 80 (ACME only), 443; 8787 localhost only. No trading container/image/database was changed.

## HTTPS and renewal

Let's Encrypt IP certificate SAN is `IP Address:178.105.32.46`, issued 2026-09-04 and expiring 2026-09-11. Certbot 5.8.0 uses the `shortlived` profile. Automatic Certbot timer, deploy-hook nginx config test/reload, six-hour expiry monitor, and a successful renewal dry-run are verified. ATS exception and certificate pinning are not used.

## Reader

Commands: `python3 Scripts/live_diagnostics.py --ssh root@178.105.32.46 latest`; add `--feature voice`, `--build N`, or use `session UUID`, `failures`, `since TIMESTAMP`, and `--json`. SSH host key is pinned to the owner-verified ED25519 fingerprint `SHA256:Xvlnjrl+17kn7tHhvG910vGjj2pTC6sQGWZjokpXcho`. Reader is read-only.

## Verification status

Build 11 physical evidence proved that `POST /v1/app-attest/challenge` reached the VPS and returned 200, while registration and authenticated diagnostic ingest were never reached. This bounds the unresolved failure to the device-side bootstrap interval after challenge receipt and before registration, but does not identify or justify changing App Attest behavior. Build 12 adds only privacy-safe observation for support state, key-generation/persistence outcome, challenge correlation, attestation invocation/outcome, registration construction/attempt/HTTP outcome, environment, and exact failure stage. It never reports key/private/attestation material, transcript, audio, user content, or secrets.

Build 12 physical bootstrap evidence reached the VPS, but was rejected before storage with the exact server error `Value was not of type String at path startedAt; expected String but found number`. The confirmed implementation defect was a diagnostic-only date-decoding mismatch: iOS `JSONEncoder.diagnostic` emits numeric `Date` values while Vapor Content expected ISO-8601. The minimum fix retains strict raw-schema validation and decodes the typed bootstrap payload with the matching numeric Foundation decoder; no App Attest, voice, product, UX, routing, permission, or privacy semantics changed. A production HTTPS probe using the exact numeric wire format returned `200 stored-unverified-bootstrap`; its explicitly synthetic record was removed immediately.

Build 13 physical evidence was delivered and stored automatically. Its ordered markers show production App Attest supported, an existing key loaded and persisted, then `NSCocoaErrorDomain/4864` before `challenge_received`; VPS access logs independently show challenge HTTP 200 and no registration request. The production challenge response encodes `expiresAt` as ISO-8601 while the client transport used the numeric Foundation date decoder. The minimum fix gives server HTTP responses a dedicated ISO-8601 decoder while leaving the numeric local queue decoder unchanged; App Attest operations and all product/voice behavior remain unchanged.

Build 14 completed App Attest registration/assertion and authenticated automatic diagnostic delivery to the owner VPS. Codex independently retrieved session `7258D6C6-3A4A-4F50-81F5-D7ED1539E890` through the SSH-only reader without owner log relay. The privacy-safe report contains no transcript text or audio. It proves audio capture and recognition remained healthy through four partial callbacks, but no final callback occurred because the open continuous recognition request had no end-of-speech finalization; therefore no submit/router/result marker could occur. The minimum implementation correction closes and finishes that same request after a bounded quiet interval following the latest non-empty partial result. Manual stop still preserves the editable transcript, genuine input loss still stops safely, and no router, UX, permission, privacy, or AI behavior changed.

Current local evidence: focused voice tests green; iOS full regression 556/556; backend 113/113; production Distribution Archive/export and successful App Store Connect upload. UniversalAssistant 0.1.0 Build 15 entered Apple processing.

The physical App Attest registration/assertion and automatic iPhone→VPS→reader delivery gates are `VERIFIED_LIVE` from Build 14 evidence. MS-800 remains `BLOCKED_BY_CONFIRMED_DEFECT` until Build 15 physically proves the full voice → recognition → final transcript → submit → router → visible-result chain.

Build 15 physically verified the complete MS-800 chain without manual stop or diagnostic copying. Authenticated VPS session `BEB97BDB-8978-443B-8A95-A935AB64AED7` records bounded end-of-speech finalization, a final Ukrainian transcript marker, delivery to ViewModel and router, router acceptance, execution start, visible result, and automatic idle transition. The owner independently observed “Команда розпізнана”. MS-800 is therefore `VERIFIED_LIVE`.

The same session exposed one diagnostic-only classification defect: a successful callback carrying `error_domain=none error_code=0` was treated as failure merely because the field existed. Build 16 corrects only this classifier: nonzero code or a domain other than `none` remains failure, while a chain containing `visible_result` becomes success. Focused diagnostic tests and full iOS regression 558/558 pass; the Production archive succeeds. App Store Connect export/upload currently requires Xcode account reauthentication and has not been claimed successful.
