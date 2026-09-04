# Physical Diagnostic Loop Evidence

Date: 2026-09-05. Canonical IDs: LIVE-DIAG-001…078. Canonical artifact SHA-256: `09384fa6a61dcbc15532ab8eca12f85ace63d470562c14d155a56da6a671327c`.

## Reused architecture and production path

The implementation reuses `UniversalAssistantServer`, `VoiceInputEvent`/`LocalVoiceDiagnosticReport`, the existing voice controller/view model, privacy-safe marker policy, TestFlight Production configuration, and the owner-authorized VPS. It adds no analytics provider, public read API, product capability, voice semantic change, or AI dependency.

Internal TestFlight app → trusted HTTPS `178.105.32.46` → nginx exact-route proxy → `127.0.0.1:8787` existing server → App Attest validation → bounded files on the existing data volume. Codex reads the store through owner-authorized SSH with `Scripts/live_diagnostics.py`; no Internet read endpoint exists.

## Allowed and forbidden data

Allowed: schema/session/live-test IDs, build/app/OS/device class, timestamps/duration/result/failure stage, safe state markers, counts, boolean/configuration state, safe route types, and error domain/code. Forbidden by client construction and server allowlist: transcript text, raw audio, passwords, credentials/tokens/cookies, payment/signing/cryptographic secrets, contacts/messages/photos/documents, precise location, arbitrary fields, and unrestricted JSON/files.

## App Attest and transport

`PhysicalDiagnosticDelivery` uses official `DCAppAttestService`: supported-state check, device-protected key generation, one-time server challenge, key attestation, and body-bound request assertion. TestFlight is configured for production App Attest. Server verification binds Team ID `9V5XXDXF3N`, bundle `com.universalassistant.app`, RP ID, production AAGUID, public key, challenge, request body, and monotonic counter. Unsupported/failure has no static-secret fallback and cannot break voice behavior.

Public routes are only `POST /v1/app-attest/challenge`, `POST /v1/app-attest/register`, and `POST /v1/diagnostics`. Application port 8787 is localhost-only. Deployed probes: malformed attestation 401; replayed challenge 401; unauthenticated ingest 401; HTTP diagnostic POST 404; oversized body 413; unknown/admin route 404.

## Storage, retry, and operations

Client queue: maximum 20 sessions, 24-hour expiry, three attempts, session-ID deduplication, asynchronous/nonblocking upload. Server: schema version 1, marker/attribute allowlist, 96 KiB transport bound, seven-day retention, maximum 500 records, deterministic session-ID deduplication, indexed filesystem identity. Daily retention timer is enabled. Diagnostic delivery state is separate from product result.

VPS storage is `/mnt/HC_Volume_106589590/universalassistant-diagnostics/data` mode 0700. Service runs as `universalassistant`, is systemd-hardened, capped at 256 MiB/50% CPU/128 tasks, and consumed about 5 MiB after deployment. Ports: 22, 80 (ACME only), 443; 8787 localhost only. No trading container/image/database was changed.

## HTTPS and renewal

Let's Encrypt IP certificate SAN is `IP Address:178.105.32.46`, issued 2026-09-04 and expiring 2026-09-11. Certbot 5.8.0 uses the `shortlived` profile. Automatic Certbot timer, deploy-hook nginx config test/reload, six-hour expiry monitor, and a successful renewal dry-run are verified. ATS exception and certificate pinning are not used.

## Reader

Commands: `python3 Scripts/live_diagnostics.py --ssh root@178.105.32.46 latest`; add `--feature voice`, `--build N`, or use `session UUID`, `failures`, `since TIMESTAMP`, and `--json`. SSH host key is pinned to the owner-verified ED25519 fingerprint `SHA256:Xvlnjrl+17kn7tHhvG910vGjj2pTC6sQGWZjokpXcho`. Reader is read-only.

## Verification status

Local: backend targeted/full, iOS targeted/full, reader, Linux release build, HTTPS/security probes, certificate renewal dry-run, production build/archive/signing, diff and preservation audit. Physical App Attest registration/assertion and automatic iPhone→VPS→reader delivery remain `READY_FOR_LIVE_VERIFICATION`; mocks do not close them. MS-800 remains blocked until the full physical voice → transcript → UI → router → visible-result chain passes.
