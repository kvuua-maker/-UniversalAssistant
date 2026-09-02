# M7 Camera Intelligence Core

- Task ID: `M7-CAMERA-INTELLIGENCE-CORE`
- Requirement IDs: 1628–1633.
- Selected path: local/system-first OCR and translation plan, typed QR payload safety, checksum-validated GTIN evidence, and calibrated visual similarity.
- Safety boundary: QR payloads are classified but never auto-executed; payment, URL, contact, Wi-Fi and communication payloads require explicit confirmation.
- Truth boundary: only a valid GTIN is exact product evidence. Visual classification remains probable similarity regardless of confidence.
- Privacy boundary: no person lookup or vehicle-owner data path is exposed.
- Device gate: live Vision OCR/barcode/camera overlay behavior and system translation availability require stable-build iPhone verification.
- Local verification: 156 iOS tests across 37 suites and 29 backend tests across 7 suites passed on 2026-09-02.
- Exit state: `SUCCESS` for the bounded local E3 interpretation and safety core.
