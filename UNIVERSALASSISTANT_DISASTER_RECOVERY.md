# UniversalAssistant Disaster Recovery

Created: 2026-09-05 (Europe/Berlin)

## Frozen source state

- Repository: `/Users/Shared/UniversalAssistantRemote`
- GitHub origin: `git@github.com:kvuua-maker/-UniversalAssistant.git`
- Branch: `main`
- Frozen HEAD and `origin/main`: `96557638b0ec7b79eed71e3fc218aec20fdf2740`
- Tags: none; submodules: none; Git LFS objects: none.
- Untracked project artifact: `UNIVERSALASSISTANT_FULL_CONTEXT_HANDOFF.md`.
- Product configuration: `0.1.0 (22)`. Signed Build 22 predates frozen HEAD and must not be uploaded as representing it.
- Last verified TestFlight/live baseline: Build 21. Apple error 90382 stated only “Please wait 1 day and try again”; retained evidence has no reset timestamp or Retry-After.

## Recovery-set contents

1. A Git bundle with every current ref and complete history.
2. A source snapshot at frozen HEAD plus the untracked handoff and recovery documents. Reproducible products/caches are excluded.
3. Canonical state: `REQUIREMENT_INVENTORY.json` (2,404 IDs), live queue/plan, matrices, evidence/status documents, tests, scripts, Xcode project, entitlements, privacy manifest, backend source, and dependency locks.
4. Non-secret VPS reconstruction material.
5. A separately encrypted secrets/signing package, never committed or stored unencrypted.

## Development environment

- macOS 26.3.1 (25D2128)
- Xcode 26.6 (17F113)
- Apple Swift 6.3.3
- Developer directory: `/Applications/Xcode.app/Contents/Developer`
- Git 2.50.1
- Restore backend dependencies from `Backend/Package.resolved`; do not restore `Backend/.build`.
- Open `UniversalAssistant.xcodeproj` and retain automatic signing for Team `9V5XXDXF3N`.

## Apple signing recovery

- Owner/team: Vladyslav Khomenko; Team ID `9V5XXDXF3N`.
- Main App ID: `com.universalassistant.app`.
- Share App ID: `com.universalassistant.app.share`.
- App Group: `group.com.universalassistant.shared`.
- iCloud container: `iCloud.com.universalassistant.app`.
- Main distribution profile: UUID `9348617b-0b29-4603-87b9-019187be3d51`, expires 2027-09-04, WeatherKit enabled.
- Share distribution profile: UUID `dcaf1bbb-918d-4360-b978-447acff0f90b`, expires 2027-09-04.
- Valid Apple Development identity SHA-1 `67B72439CD7D16C69C3FD7EBC603E78FA26F92EC`; private-key presence is confirmed by `security find-identity`.
- Old Development certificate SHA-1 `1D1E49C28D0BEA37C783E9C811A7696240B58AD3` has no valid identity/private key.
- No Apple Distribution identity was present in the inspected login keychain. It is reissuable through the owner’s Apple Developer account; do not revoke existing certificates for recovery.

Restore signing in this order: install Xcode; owner signs in and completes 2FA; import the protected PKCS#12; restore or regenerate profiles for the same App IDs; verify Team/bundle/App Group/CloudKit/Sign in with Apple/Push/WeatherKit/MusicKit entitlements; reissue Apple Distribution if absent.

## Secret recovery inventory

Secret values are intentionally omitted.

| Type | Purpose | Current storage | Recovery | Classification |
|---|---|---|---|---|
| Apple Development private key | Development signing | macOS login keychain | Protected PKCS#12 | CRITICAL_BACKUP_REQUIRED |
| Old Development certificate without key | Historical only | macOS login keychain | Do not restore | NOT_REQUIRED_FOR_RECOVERY |
| Apple Distribution identity | TestFlight signing | Not present in inspected keychain | Reissue through Apple | REISSUABLE |
| Provisioning profiles | App/share authorization | Xcode UserData | Restore files or regenerate | REISSUABLE |
| Apple Account session | Developer/App Store Connect access | Owner-controlled | Owner reauth/2FA | ACCOUNT_REAUTHENTICATION_ONLY |
| Mac SSH private key | VPS/Git authorization | `~/.ssh/id_ed25519` | Encrypted package or authorize replacement | CRITICAL_BACKUP_REQUIRED |
| TLS private key/ACME state | VPS HTTPS | `/etc/letsencrypt` | Encrypted server copy or ACME reissue | REISSUABLE |
| App Attest state | Diagnostic authentication | VPS data directory | Preserve if continuity needed; otherwise approved re-registration | REISSUABLE |
| Backend runtime secrets | Diagnostic service | VPS environment/config | Encrypted server-config backup | CRITICAL_BACKUP_REQUIRED |
| App Store Connect API credentials | Upload automation | None confirmed | Owner reauth or reissue | ACCOUNT_REAUTHENTICATION_ONLY |
| Provider/OAuth credentials | External integrations | Values excluded | Provider reauthorization/reissue | REISSUABLE |

## VPS recovery

- Host: `178.105.32.46`; verify the owner-approved ED25519 fingerprint out of band.
- OS: Ubuntu 24.04.4 LTS.
- Service root/data volume: `/mnt/HC_Volume_106589590/universalassistant-diagnostics`.
- Backend: `127.0.0.1:8787`; nginx: public 80/443; SSH: 22.
- Units: `universalassistant-diagnostics.service`, retention service/timer, certificate-monitor service/timer.
- nginx site: `/etc/nginx/sites-available/universalassistant` and enabled link.
- TLS/ACME: `/etc/letsencrypt`; Certbot renewal timer enabled.
- Session retention at checkpoint: seven days.
- Reader: `/mnt/HC_Volume_106589590/universalassistant-diagnostics/live-diagnostics`.
- Live diagnostic records are not needed to reconstruct service and must not be copied unnecessarily.

Restore/reconnect in this order: verify host key and owner authorization; restore backend from Git; restore encrypted runtime config with restrictive permissions; restore/reissue ACME state; restore unit/nginx/timer files; validate before reload; confirm only 22/80/443 public and backend localhost-only; verify App Attest ingest, retention, and SSH-local reader. Never alter unrelated trading/research services.

## Clean-Mac restore order

1. Verify recovery manifest and every SHA-256.
2. Install the recorded macOS/Xcode/toolchain or an approved compatible successor.
3. Clone GitHub or the verified Git bundle; check out frozen HEAD.
4. Overlay recovery-only files, especially `UNIVERSALASSISTANT_FULL_CONTEXT_HANDOFF.md` and this document.
5. Restore signing/SSH/backend secrets from the encrypted package using the owner-held password.
6. Owner reauthenticates accounts directly; never store passwords/2FA in files or chat.
7. Resolve locked dependencies.
8. Run zero-omission checks, iOS/backend regressions, and a clean production build.
9. Verify signed app/profile entitlements before TestFlight upload.
10. Reconnect to VPS diagnostics without changing unrelated services.

## Verification and limitations

- `git fsck --full` must succeed and restored HEAD must equal `96557638b0ec7b79eed71e3fc218aec20fdf2740`.
- All manifest refs must exist; the 2,404-ID inventory, live plan/queue, and handoff must be present.
- Signing recovery is not VERIFIED until the protected identity is imported and successfully used on a replacement Mac.
- A source/build drill does not by itself prove Apple account, signing, provider, or VPS-secret restoration.

Never commit or expose unencrypted `.p12`/private keys, SSH private keys, `.env` values, OAuth/API tokens, Apple credentials, backend runtime secrets, ACME private keys, App Attest state, live diagnostic records, or recovery passwords.
