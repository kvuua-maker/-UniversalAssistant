# M12 On-device PDF Processing Core

This atomic increment closes a concrete local portion of MS-1474 without overstating the full requirement.

Production implementation uses PDFKit/UIKit entirely on device to merge, split, reorder, delete and explicitly rotate pages; create searchable image PDFs from locally recognized text; raster-compress PDFs; and flatten redaction/signature pixels. Inputs are parsed as real PDF bytes, pages are copied or deliberately rasterized, invalid/duplicate/destructive selections fail closed, redaction cannot be undone by deleting an annotation, and no external AI or server receives document content.

Behavioral tests generate real PDFs and images with UIKit, execute transformations, decode the resulting PDF bytes, verify crop/contrast/PDF-to-image/page text/order/rotation/searchability/highlighting, confirm flattened output contains no recoverable source text or removable annotations, and exercise invalid input. Full regression passed: 337 Swift Testing tests across 85 suites plus 5 Routine XCTest tests; backend 79 tests across 22 suites.

MS-1474 is VERIFIED_LOCAL. VisionKit provides interactive page/edge detection, perspective correction, orientation correction and multi-page capture; Vision provides on-device OCR; the processor behaviorally verifies the remaining safe local transformations. It never silently changes semantic content. Physical camera/UI execution remains truthfully isolated in the existing live-verification queue item.
