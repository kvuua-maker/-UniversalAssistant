# Business Platform Competitive Gap Audit

Status: mandatory canonical targeted audit. This supplements Master Spec v13.2 and accepted addenda. It does not authorize a second CRM, ERP, accounting, warehouse, POS, marketing automation or AI call-centre architecture.

## Binding scope

Evidence-first audit and minimal completion of: compact partner customer/interaction history, provider-neutral business inbox, truthful partner catalog/price/stock sync, a shared transaction lifecycle foundation with domain-specific states, explicit partner connector capabilities, transactional notifications, and the existing attribution-to-settlement chain. Existing M9, Marketplace, Commerce, Appointment, webhook, ledger, reconciliation, tenant-isolation, privacy and notification components must be reused. Live success must never be fabricated; unavailable connectors are not empty data.

## Pre-implementation evidence matrix

| Capability / subrequirement | Status | Existing implementation | Test evidence | Commit evidence | Gap |
| --- | --- | --- | --- | --- | --- |
| A customer/contact and transaction history | MISSING | Partner onboarding and tenant authorization have no customer interaction model | PartnerOnboardingTests, PartnerTenantAuthorizationTests | M9 history | Minimal tenant-scoped customer/history store with data minimization and dedupe |
| A attribution/refund/dispute/commission linkage | ALREADY_IMPLEMENTED | AttributionRecord, ConversionLedger, CommissionLedgerEntry and ReconciliationSettlement | ConversionLedgerTests, ReconciliationSettlementTests | M9 history | Reuse by reference; no second finance engine |
| B normalized business inbox | MISSING | Consumer SharedInboxStore is a share-extension inbox, not partner interactions | SharedContentActionRouterTests | M12 history | Tenant-scoped normalized interaction stream, event idempotency, source attribution and truthful coverage |
| C feed freshness/health | PARTIAL | PartnerFeedRecord/Directory and PartnerFeedHealthEvaluator track opaque payload references | PartnerFeedHealthTests | M9 history | Normalized SKU/variant/price/stock records, field provenance, deletion, conflict policy, durable idempotent sync |
| D conversion lifecycle | PARTIAL | ConversionState covers monetization but not operational order/booking fulfillment states | ConversionLedgerTests | M9 history | Shared operational foundation with typed domain and validated transitions; keep finance lifecycle separate and linked |
| D appointments | ALREADY_IMPLEMENTED | AppointmentEngine and OfficialAppointmentHTTPProvider implement availability/book/reschedule/cancel | AppointmentEngineTests | M12 history | Adapter into shared operational reference only |
| E connector layer | PARTIAL | Provider protocols, capability registries, signed webhook ingestion and feed health exist per domain | PartnerWebhookIngestionTests, IntegrationDepthAuditorTests | M7/M9 history | Explicit partner connector capability contract and capability-mismatch/partial-failure behavior |
| Transactional business notifications | ALREADY_IMPLEMENTED | durable proactive queue, APNs delivery, notification policy and observability | ProactiveNotificationPolicyTests, APNsDeliveryClientTests | M6/M10 history | Reuse; marketing remains out of scope |

## Completion contract

Only the rows marked MISSING/PARTIAL may receive minimal implementation. Required behavioral evidence includes customer dedupe, interaction attribution/idempotency, connector partial failure/capability mismatch, SKU mapping, price/stock/stale/deletion behavior, lifecycle transition/cancel/refund/dispute/booking references, existing attribution and commission adjustments, and restart persistence. Production connector/account/device executions remain `READY_FOR_LIVE_VERIFICATION` in `LIVE_VERIFICATION_QUEUE.json` after all local work is complete.

## Post-implementation evidence matrix

| Capability | Status | Production and behavioral evidence | Commit |
| --- | --- | --- | --- |
| A. Business mini-CRM | ALREADY_IMPLEMENTED | BusinessOperationsStore tenant-scoped PartnerCustomer dedupe, permitted contacts, interactions and linked transaction/attribution/conversion history; restart test plus existing ConversionLedger tests | f88596e |
| B. Unified business inbox | ALREADY_IMPLEMENTED | provider-neutral BusinessInteraction source/reference/status/assignment model, tenant query and duplicate event idempotency; customerDeduplicationInboxAttributionAndDuplicateEventPersistAcrossRestart | f88596e |
| C. Catalog/price/inventory sync | ALREADY_IMPLEMENTED | PartnerCatalogItem/Variant carries SKU/external IDs, verified field provenance, Decimal price/stock, availability, variants, action URL, timestamp and deletion; deterministic stale rejection/idempotent update and catalog behavioral test | f88596e |
| D. Unified order/booking lifecycle | ALREADY_IMPLEMENTED | BusinessTransaction shared operational foundation validates domain-aware transitions and links existing attribution/conversion IDs without duplicating ConversionLedger; order/booking/cancel/dispute/idempotency tests plus existing refund/commission tests | f88596e |
| E. Partner connector layer | ALREADY_IMPLEMENTED | PartnerBusinessConnector advertises explicit per-operation capabilities and health; capability mismatch and isolated failure behavior test, reusing signed webhook/feed-health infrastructure | f88596e |

Local verification: 83 backend tests across 23 suites and 374 iOS Swift Testing tests across 91 suites plus 5 Routine XCTest tests passed on 2026-09-02. Real partner connector executions remain live-only and are queued explicitly.
