# M12 On-device PDF Processing Core

This atomic increment closes a concrete local portion of MS-1474 without overstating the full requirement.

Production implementation uses PDFKit/UIKit entirely on device to merge, split, reorder, delete and explicitly rotate pages; create searchable image PDFs from locally recognized text; raster-compress PDFs; and flatten redaction/signature pixels. Inputs are parsed as real PDF bytes, pages are copied or deliberately rasterized, invalid/duplicate/destructive selections fail closed, redaction cannot be undone by deleting an annotation, and no external AI or server receives document content.

Behavioral tests generate real PDFs and images with UIKit, execute transformations, decode the resulting PDF bytes, verify page text/order/rotation/searchability, confirm flattened output contains no recoverable source text or removable annotations, and exercise invalid input. Full regression passed: 336 Swift Testing tests across 85 suites plus 5 Routine XCTest tests; backend 79 tests across 22 suites.

MS-1474 remains IMPLEMENTED_UNVERIFIED rather than VERIFIED_LOCAL because its complete canonical surface still includes explicit crop/perspective/image-enhancement and annotation/highlighting workflows where technically appropriate. Existing VisionKit capture handles interactive edge/perspective correction and Vision supplies local OCR, but the remaining testable surfaces are the next work, not silently deferred.
