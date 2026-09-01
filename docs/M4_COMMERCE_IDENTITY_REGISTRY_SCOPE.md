# M4 Commerce Capability and Product Identity Core

- Commerce remains a lazy module inside UniversalAssistant; no provider initializes at launch and no catalogue is stored on device.
- `RetailProvider` is provider-neutral and accepts a validated exact-identity request.
- Product identity preserves brand, model, type, provider SKU, GTIN/EAN/UPC barcode, storage, size, color, generation, region, condition, configuration and quantity/unit.
- GTIN-8/12/13/14 values require a valid check digit. Invalid barcodes never produce a product identity claim.
- Matching prioritizes GTIN, then SKU plus compatible core identity. Any known critical variant conflict downgrades the result; visual/textual similarity without a strong identifier is never `exact`.
- The actor-isolated provider registry records regions, granular capabilities, affiliate network, credentials/registration/approval, rate limits, restrictions, fallback, status, enable/kill switch and official verification date.
- Registry eligibility is region/capability/status aware; credential- or approval-blocked providers do not block independent providers.

Verification: Development simulator suite passed 59 tests in 16 suites on 2026-09-01. No live commerce provider is claimed integrated by this core checkpoint.
