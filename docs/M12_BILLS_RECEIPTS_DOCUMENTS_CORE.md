# M12 Bills, Receipts and Documents Core

Requirements MS-1023–1029. Status: VERIFIED_LOCAL after the recorded regression.

BillsReceiptsDocumentsEngine models bills, receipts, invoices, warranties, tickets and other everyday documents without banking credentials or payment execution. Every extracted merchant, total, due, purchase or warranty fact carries explicit verified-source versus extracted-unverified confidence. Only verified due dates can form reminder plans; warranty reminders require both a verified receipt purchase date and verified warranty end.

Bill/receipt queries reuse UniversalPersonalSearchEngine across authorized Files/Notes and connected email sources concurrently. Assistant-owned document results retain source object ID and exact open reference. Payment is only an HTTPS official handoff requiring confirmation; missing or non-HTTPS destinations return unavailable and never claim payment.

Behavioral evidence covers unverified due-date rejection, confirmed payment handoff, exact provenance, verified warranty association and cross-source routing. Full regression passed on 2026-09-02: 281 iOS tests across 72 suites and 78 backend tests across 22 suites.
