# M12 Apple System Domains Core

Requirements MS-949–955. Local implementation status: VERIFIED_LOCAL. Entitlement/device operations: READY_FOR_LIVE_VERIFICATION.

`AppleSystemDomainAudit` covers Mail, Messages, Calendar, Reminders, Phone, Photos, Files, Notes, Maps, Camera, Clock, Audio and Search, recording the deepest implemented public behavior and every material platform boundary. Existing EventKit, Contacts, MapKit, PhotoKit, document picker, Core Spotlight, recorder, MessageUI and connected-email implementations are reused.

`SystemCameraCapture` provides real user-visible in-app capture through the public system camera surface and fails closed when a camera is unavailable; it never substitutes an old library photo or claims control of Camera.app. `AppleMusicProviderAdapter` is a concrete MainActor-isolated MusicKit implementation for authorization, song/album/artist/playlist/station catalog search and managed song playback controls. `ApplePodcastSearchProvider` performs bounded country-aware public iTunes Search API requests and returns only validated exact HTTPS episode handoffs.

Clock timer/alarm requests remain truthful unavailable results because this app target has no general public creation API; no fake completion is emitted. Automated tests verify complete domain coverage/private-access limits, simulator camera fail-closed behavior, bounded podcast queries/exact handoff and provider failure handling. Camera, MusicKit entitlement/playback and live podcast response remain explicitly queued.

Full regression on 2026-09-02: 260 iOS tests across 67 suites and 78 backend tests across 22 suites passed. The built app Info.plist contains `NSCameraUsageDescription`; canonical JSON and diff checks passed.
