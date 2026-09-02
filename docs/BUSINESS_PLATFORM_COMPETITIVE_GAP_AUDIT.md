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
