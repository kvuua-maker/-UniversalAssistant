# M12 Share, Clipboard and Scanner Core

Requirements MS-1005–1022. Local implementation status: VERIFIED_LOCAL. Physical Share Sheet, camera and document capture: READY_FOR_LIVE_VERIFICATION.

The embedded ShareExtension target accepts one bounded public URL, webpage, text, vCard, image or document item and persists a structured envelope in the shared App Group. The host consumes it once on activation and feeds the existing command path. Unsupported input fails truthfully. Safari uses this same useful Share Sheet path; a separate Safari Web Extension would duplicate the V1 handoff.

SystemUserInitiatedClipboardReader reads UIPasteboard only from its explicit method; there is no launch/background polling or upload. SharedContentActionRouter preserves the exact item and permits only compatible actions. Opening, routing, calling and contact import require confirmation. Payment QR automation is rejected. A retail barcode enters product identification only after GTIN validation; unknown codes never produce a product identity.

LiveCodeScanner uses VisionKit DataScannerViewController for QR/EAN/UPC/Code128. DocumentScannerCoordinator uses VNDocumentCameraViewController, OnDeviceDocumentOCR uses Vision locally, and VCardImportIntegration validates through Contacts before presenting the system new-contact confirmation UI.

Evidence: embedded host build and standalone extension build succeed; five routing/inbox behavioral tests pass. Full regression passed on 2026-09-02: 276 iOS tests across 71 suites and 78 backend tests across 22 suites. The exact remaining physical-device observation is in LIVE_VERIFICATION_QUEUE.json.
