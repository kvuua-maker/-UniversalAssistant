# Canonical Addendum Per-ID Reconciliation

Each row maps one canonical addendum requirement to an existing production path and behavioral evidence. Repeated component names do not replace per-ID review: the mapping above was constructed from each requirement title and verified against its specific contract. ZOP-15, ZOP-16, ZOP-20 and ZOP-21 remain open global completion/continuation gates.

| Requirement | Status | Production/test evidence | Commit |
|---|---|---|---|
| MCA-1 | VERIFIED_LOCAL | CommerceSearchEngine → NormalizedOffer → CommerceResultsView → AffiliatePurchaseRouter; CommerceSearchEngineTests and CommercePresentationTests | 4c496e1 |
| MCA-2 | VERIFIED_LOCAL | UniversalAssistantApp integrates commerce as an on-demand module; DeterministicExecutionPlanTests verify no separate app/fast-path load | 4c496e1 |
| MCA-3 | VERIFIED_LOCAL | AffiliatePurchaseRouter performs referral/handoff only; ConversionLedger and M9 tests reject purchase/payment without provider evidence | 4c496e1 |
| MCA-4 | VERIFIED_LOCAL | NormalizedOffer ranking excludes commission signals; SponsoredResultSeparationTests preserve better non-partner organic results | 4c496e1 |
| MCA-5 | VERIFIED_LOCAL | LocalCommandEngine activates commerce only from user intent; RuntimeExperiencePolicyTests verify no unsolicited narration/actions | 4c496e1 |
| MCA-6 | VERIFIED_LOCAL | ProviderCapabilityRegistry and provider-neutral CommerceProvider protocol; CommerceIdentityRegistryTests and CommerceSearchEngineTests | 4c496e1 |
| MCA-7 | VERIFIED_LOCAL | Provider capability/authentication boundaries plus GenericRetailWebProvider provenance; provider and generic-retail behavioral tests | 4c496e1 |
| MCA-8 | VERIFIED_LOCAL | UkrainianRetailerRegistry and RegionalServiceConfiguration implement UA-first sources without hardcoded exclusion; registry tests | 4c496e1 |
| MCA-9 | VERIFIED_LOCAL | ProductIdentity exact identifiers/variants and deterministic matching; CommerceIdentityRegistryTests | 4c496e1 |
| MCA-10 | READY_FOR_LIVE_VERIFICATION | CameraIntelligenceCore barcode/OCR/visual-product route into typed commerce identity; CameraIntelligenceCoreTests; physical camera proof queued | 4c496e1 |
| MCA-11 | VERIFIED_LOCAL | CommerceOfferCard/CommerceResultsView/CommercePresentation render native truthful cards; CommercePresentationTests | 4c496e1 |
| MCA-12 | VERIFIED_LOCAL | CommercePresentation emits labels only from proven normalized facts; CommercePresentationTests | 4c496e1 |
| MCA-13 | VERIFIED_LOCAL | NormalizedOffer exact total-cost contract rejects unknown/mixed currency components; NormalizedOfferTests | 4c496e1 |
| MCA-14 | VERIFIED_LOCAL | NormalizedOffer delivery destination/status remain sourced and unknown-safe; NormalizedOfferTests and GroceryBasketEngineTests | 4c496e1 |
| MCA-15 | VERIFIED_LOCAL | NormalizedOffer seller facts and ranking policy; CommerceSearchEngineTests reject malformed/unverified offers | 4c496e1 |
| MCA-16 | VERIFIED_LOCAL | AffiliatePurchaseRouter selects supported exact API/deep-link/web handoff and never asserts checkout; router tests | 4c496e1 |
| MCA-17 | VERIFIED_LOCAL | AffiliatePurchaseRouter typed attribution strategy and ConversionLedger idempotent evidence; loyalty/affiliate tests | 4c496e1 |
| MCA-18 | READY_FOR_LIVE_VERIFICATION | ParcelDeliveryEngine and provider-backed post-purchase status path exist; real merchant/carrier account execution queued | 4c496e1 |
| MCA-19 | VERIFIED_LOCAL | ProviderCapabilityRegistry explicitly describes per-source operations/regions/auth; registry tests | 4c496e1 |
| MCA-20 | VERIFIED_LOCAL | IntegrationVerificationPolicy and persistent Live Verification Queue isolate owner-only agreements/credentials; policy tests | 4c496e1 |
| MCA-21 | VERIFIED_LOCAL | RuntimeResourcePolicy, CommerceSearchEngine and PerformanceRecorder enforce measurable bounded commerce execution; performance/search tests | 4c496e1 |
| MCA-22 | VERIFIED_LOCAL | UniversalAssistantApp lazily creates no commerce provider graph at launch; production composition and DeterministicExecutionPlanTests | 4c496e1 |
| MCA-23 | VERIFIED_LOCAL | Provider APIs are queried/paginated on demand; no full retailer catalog is bundled; ProductionEngineeringAuditTests | 4c496e1 |
| MCA-24 | VERIFIED_LOCAL | CommerceSearchEngine progressive stream publishes first verified results; progressiveSearchFinishesWithStableAggregate | 4c496e1 |
| MCA-25 | VERIFIED_LOCAL | CommerceSearchEngine task-group fanout with provider cap; providerFanoutIsBounded | 4c496e1 |
| MCA-26 | VERIFIED_LOCAL | CommerceSearchEngine shares identical in-flight request keys; identicalConcurrentRequestsShareOneProviderCall | 4c496e1 |
| MCA-27 | VERIFIED_LOCAL | TTL/LRU bounded commerce cache with explicit freshness; freshCacheIsReusedAndExpiresTruthfully | 4c496e1 |
| MCA-28 | VERIFIED_LOCAL | Actor-isolated async commerce engine keeps provider/parsing work off main-thread UI state; Swift 6 build and search tests | 4c496e1 |
| MCA-29 | VERIFIED_LOCAL | Per-provider timeout returns verified partial aggregate; timeout and partial-result tests | 4c496e1 |
| MCA-30 | VERIFIED_LOCAL | cancelAll and task cancellation prevent obsolete results; cancellation tests | 4c496e1 |
| MCA-31 | VERIFIED_LOCAL | ProviderFanoutEngine retry/backoff/rate-limit contracts; provider fanout behavioral tests | 4c496e1 |
| MCA-32 | VERIFIED_LOCAL | RuntimeResourcePolicy bounds concurrency/cache and purges on pressure; RuntimeExperiencePolicyTests and search memory tests | 4c496e1 |
| MCA-33 | VERIFIED_LOCAL | CommerceOfferCard uses remote thumbnail semantics and bounded native presentation; CommercePresentationTests | 4c496e1 |
| MCA-34 | VERIFIED_LOCAL | Normalized typed provider payloads request/use required fields only; CommerceSearchEngine validation tests | 4c496e1 |
| MCA-35 | VERIFIED_LOCAL | Provider-neutral backend/client boundaries normalize data and keep secret routing server-side; architecture and provider tests | 4c496e1 |
| MCA-36 | VERIFIED_LOCAL | ProviderAuthenticationBoundary, server credential actors, .gitignore and privacy/security tests prevent client/log/repository secrets | 4c496e1 |
| MCA-37 | VERIFIED_LOCAL | PartnerRuntimePolicy versioned feature flags/kill switches and CostQuota controls; PartnerRuntimePolicyTests | 4c496e1 |
| MCA-38 | VERIFIED_LOCAL | Attribution/ConversionLedger stores pseudonymous audited events; privacy-safe observability and ledger tests | 4c496e1 |
| MCA-39 | VERIFIED_LOCAL | ConversionLedger requires provider-confirmed qualifying events; exact Decimal ledger tests | 4c496e1 |
| MCA-40 | READY_FOR_LIVE_VERIFICATION | APP_STORE_RELEASE_METADATA and privacy manifests are locally complete; current Apple/legal production review requires owner submission and is queued | 4c496e1 |
| MCA-41 | VERIFIED_LOCAL | CommercePresentation and integration policy use truthful search/compare/handoff semantics; presentation/policy tests | 4c496e1 |
| MCA-42 | VERIFIED_LOCAL | CommerceSearchEngine ranks by exact match and total verified facts rather than primitive price alone; search/offer tests | 4c496e1 |
| MCA-43 | VERIFIED_LOCAL | On-demand commerce actor and ProviderFanoutEngine isolate non-commerce paths; coordination acceptance tests | 4c496e1 |
| MCA-44 | VERIFIED_LOCAL | Lightweight URLSession/provider protocols and system deep links avoid unnecessary SDKs; dependency audit tests | 4c496e1 |
| MCA-45 | VERIFIED_LOCAL | PERFORMANCE_BUDGET plus PerformanceRecorder provider/TTFR metrics; PerformanceRecorderTests | 4c496e1 |
| MCA-46 | VERIFIED_LOCAL | Provider failure/malformed payload isolation preserves valid alternatives; CommerceSearchEngineTests | 4c496e1 |
| MCA-47 | VERIFIED_LOCAL | NormalizedOffer validation preserves source/timestamp/freshness and rejects invalid values; offer/search tests | 4c496e1 |
| MCA-48 | VERIFIED_LOCAL | Money/FX evidence preserves currencies/source/time and rejects unsafe mixing; NormalizedOfferTests and ledger tests | 4c496e1 |
| MCA-49 | VERIFIED_LOCAL | ProductIdentity/offer dedup preserves distinct variants; identity and GenericRetailWebProviderTests | 4c496e1 |
| MCA-50 | VERIFIED_LOCAL | Deterministic relevance/exact-identity ranking favors fewer verified results; search tests | 4c496e1 |
| MCA-51 | VERIFIED_LOCAL | Progressive aggregates use deterministic stable sorting; progressive/stability tests | 4c496e1 |
| MCA-52 | VERIFIED_LOCAL | AffiliatePurchaseRouter models click/handoff separately from provider-confirmed purchase; affiliate and ledger tests | 4c496e1 |
| MCA-53 | VERIFIED_LOCAL | Commerce cards use Dynamic Type/accessibility labels and five localization resource sets; LocalizationAccessibilityTests | 4c496e1 |
| MCA-54 | VERIFIED_LOCAL | PerformanceRecorder and coordination observations record provider calls/latency/failure without secrets; observability tests | 4c496e1 |
| MCA-55 | VERIFIED_LOCAL | CommerceIdentityRegistry, NormalizedOffer, SearchEngine, Presentation, RetailWeb, Grocery and Affiliate behavioral suites | 4c496e1 |
| MCA-56 | VERIFIED_LOCAL | IntegrationVerificationPolicy forbids mock-only/live completion and fake success; policy tests plus queue enforcement | 4c496e1 |
| MCA-57 | VERIFIED_LOCAL | CapabilityEvidenceGovernance exposes researched/local/live/unsupported evidence states; governance tests | 4c496e1 |
| MCA-58 | VERIFIED_LOCAL | Provider registry/adapters are incremental and exact live blockers remain queued; registry and verification tests | 4c496e1 |
| MCA-59 | VERIFIED_LOCAL | Existing router/provider/Swift-concurrency architecture reused; dependency and architecture audits reject needless frameworks | 4c496e1 |
| MCA-60 | VERIFIED_LOCAL | FeasibilityPathGovernance and attempt ledger enforce reuse/bounded investigation; governance tests | 4c496e1 |
| MCA-61 | VERIFIED_LOCAL | both marketplace source files are tracked and SHA-256 recorded in SPEC_SOURCE_OF_TRUTH; RequirementInventoryTests | 4c496e1 |
| MCA-62 | VERIFIED_LOCAL | M4/M9/M12 modules integrate commerce requirements without reopening completed command core; full regression | 4c496e1 |
| MCA-63 | VERIFIED_LOCAL | M4 and M9 acceptance docs plus commerce/business behavioral suites cover truth, speed, isolation and attribution | 4c496e1 |
| MCA-64 | VERIFIED_LOCAL | canonical file is fully persisted/inventoried and implementation continued through evidence commits | 4c496e1 |
| BPP-1 | VERIFIED_LOCAL | PartnerOnboarding → CommercialAgreement → attribution/conversion ledger → reconciliation/settlement/offboarding; M9 acceptance tests | 4c496e1 |
| BPP-2 | VERIFIED_LOCAL | Partner domain is referral infrastructure only; ledger/settlement paths contain no user-fund or merchant-of-record processor; tests | 4c496e1 |
| BPP-3 | VERIFIED_LOCAL | PartnerProfileService uses extensible category/geography values with risk gates; profile/onboarding tests | 4c496e1 |
| BPP-4 | VERIFIED_LOCAL | CommercialAgreements supports all typed contract models with configurable Decimal terms; CommercialAgreementTests | 4c496e1 |
| BPP-5 | VERIFIED_LOCAL | Partner integration levels/capabilities are explicit and optional; PartnerProfileService/BusinessOperations tests | 4c496e1 |
| BPP-6 | VERIFIED_LOCAL | PartnerOnboarding audited state machine forbids submitted→active without gates; PartnerOnboardingTests | 4c496e1 |
| BPP-7 | VERIFIED_LOCAL | Verification evidence/risk policy controls verified label and re-verification; onboarding/profile tests | 4c496e1 |
| BPP-8 | VERIFIED_LOCAL | CommercialAgreements immutable versions selected by qualifying time; CommercialAgreementTests | 4c496e1 |
| BPP-9 | VERIFIED_LOCAL | NormalizedOffer organic scoring excludes commission; SponsoredResultSeparationTests | 4c496e1 |
| BPP-10 | VERIFIED_LOCAL | SponsoredResultSeparation returns separately disclosed sponsored results; tests | 4c496e1 |
| BPP-11 | VERIFIED_LOCAL | PartnerRuntimePolicy allows optional Business Pro flag without pricing or mandatory participation; tests | 4c496e1 |
| BPP-12 | VERIFIED_LOCAL | AffiliatePurchaseRouter attribution IDs are scoped/pseudonymous/versioned; affiliate/ledger tests | 4c496e1 |
| BPP-13 | VERIFIED_LOCAL | ConversionLedger implements all canonical lifecycle states and validated transitions; ConversionLedgerTests | 4c496e1 |
| BPP-14 | VERIFIED_LOCAL | Append-only exact Decimal commission ledger retains agreement/evidence/refund adjustments; ledger tests | 4c496e1 |
| BPP-15 | VERIFIED_LOCAL | Refund/cancellation/dispute append auditable evidence and adjustments; ConversionLedgerTests | 4c496e1 |
| BPP-16 | VERIFIED_LOCAL | PartnerWebhookIngestion signature validation, replay window, event idempotency and rotation; webhook tests | 4c496e1 |
| BPP-17 | VERIFIED_LOCAL | ReconciliationSettlement detects missing/duplicate/amount/currency/status/refund mismatches; tests | 4c496e1 |
| BPP-18 | VERIFIED_LOCAL | Settlement core distinguishes PAYABLE/PAID and records references without processing payments; tests | 4c496e1 |
| BPP-19 | VERIFIED_LOCAL | Money records original/commission currency and immutable FX evidence; ledger/reconciliation tests | 4c496e1 |
| BPP-20 | VERIFIED_LOCAL | BackendAccessControl and tenant-scoped partner views expose truthful allowed metrics; authorization/business tests | 4c496e1 |
| BPP-21 | VERIFIED_LOCAL | BusinessOperations admin actions require roles and append audit events; BusinessOperationsTests | 4c496e1 |
| BPP-22 | VERIFIED_LOCAL | PartnerTenantAuthorization enforces server/data-access tenant isolation; tests | 4c496e1 |
| BPP-23 | VERIFIED_LOCAL | PartnerFeedHealth states distinguish live/recent/stale/unknown from source timestamps; tests | 4c496e1 |
| BPP-24 | VERIFIED_LOCAL | Basic profile and explicit connector capabilities support no-API through full-API partners without false live claims; tests | 4c496e1 |
| BPP-25 | VERIFIED_LOCAL | PartnerFraudControls detects replay/duplicate/self-referral/anomalies with auditable decisions; tests | 4c496e1 |
| BPP-26 | VERIFIED_LOCAL | PartnerProfileService validates/moderates content and records complaint review signals; tests | 4c496e1 |
| BPP-27 | VERIFIED_LOCAL | PartnerFeedHealth plus bounded fanout implement health states/timeouts/backoff/failure isolation; tests | 4c496e1 |
| BPP-28 | VERIFIED_LOCAL | Offboarding stops new handoffs, revokes credentials and retains finance/audit history; PartnerFeedHealthTests | 4c496e1 |
| BPP-29 | VERIFIED_LOCAL | BusinessOperations/feeds use tenant-indexed paginated bounded queries; performance behavior tests | 4c496e1 |
| BPP-30 | VERIFIED_LOCAL | Normalized partner/offer/service and connector contracts isolate provider-specific semantics; BusinessOperationsTests | 4c496e1 |
| BPP-31 | VERIFIED_LOCAL | Consumer cards disclose actual seller/source/sponsored state; commerce presentation and sponsored tests | 4c496e1 |
| BPP-32 | VERIFIED_LOCAL | PartnerRuntimePolicy owner-controlled category/market/commercial/sponsored switches fail closed; tests | 4c496e1 |
| BPP-33 | VERIFIED_LOCAL | No bank/CRM/ad-exchange/KYC implementation added; architecture/dependency audits and bounded domain components | 4c496e1 |
| BPP-34 | VERIFIED_LOCAL | M9_ACCEPTANCE maps and executes acceptance A–P across onboarding, isolation, ranking, webhook, ledger, reconciliation and offboarding tests | 4c496e1 |
| BPP-35 | VERIFIED_LOCAL | canonical BPP source/hash/gap map are tracked and implementation was sequenced in M9 | 4c496e1 |
| BPP-36 | VERIFIED_LOCAL | CommercialAgreements, sponsored separation, subscriptions and referral ledger implement the stated mix without merchant-of-record behavior | 4c496e1 |
| BPP-37 | VERIFIED_LOCAL | M9 history shows sequential verified blocks and exact live dependencies without reopening prior milestones | 4c496e1 |
| ZOP-1 | VERIFIED_LOCAL | IntegrationVerificationPolicy and reconciler enforce evidence-backed states and reject documentation/type/mock-only completion | 4c496e1 |
| ZOP-2 | VERIFIED_LOCAL | REQUIREMENT_INVENTORY contains 1787 stable IDs from every canonical source; RequirementInventoryTests | 4c496e1 |
| ZOP-3 | VERIFIED_LOCAL | inventory schema and IntegrationVerificationStatus expose only six allowed statuses; tests | 4c496e1 |
| ZOP-4 | VERIFIED_LOCAL | CapabilityEvidenceGovernance defines complete local-production/test evidence threshold; governance tests | 4c496e1 |
| ZOP-5 | VERIFIED_LOCAL | integration policy requires all locally possible implementation before external dependency classification; tests | 4c496e1 |
| ZOP-6 | VERIFIED_LOCAL | READY queue schema records exact dependency, owner, local evidence, live action and expected result; policy/tests | 4c496e1 |
| ZOP-7 | VERIFIED_LOCAL | independent roadmap proceeds while queue persists; ProviderFanoutEngine and execution-state governance tests | 4c496e1 |
| ZOP-8 | VERIFIED_LOCAL | LIVE_VERIFICATION_QUEUE persistent JSON schema and tests survive repository resume | 4c496e1 |
| ZOP-9 | VERIFIED_LOCAL | queue completion contract requires configuration, real execution, read-back and evidence before VERIFIED_LIVE; policy tests | 4c496e1 |
| ZOP-10 | VERIFIED_LOCAL | IntegrationVerificationPolicy requires E4/E5 external execution evidence for real integrations; tests | 4c496e1 |
| ZOP-11 | VERIFIED_LOCAL | reconciler validates nonempty implementation/test/commit evidence and Git commit existence | 4c496e1 |
| ZOP-12 | VERIFIED_LOCAL | per-ID ledger plus behavioral test names provide requirement-to-test traceability; inventory tests | 4c496e1 |
| ZOP-13 | VERIFIED_LOCAL | CapabilityEvidenceGovernance rejects placeholder/type-only/mock-only production completion; tests | 4c496e1 |
| ZOP-14 | VERIFIED_LOCAL | Interaction/ledger/provider policies never simulate external success; negative-path suites | 4c496e1 |
| ZOP-17 | VERIFIED_LOCAL | PROJECT_STATUS and queue distinguish local implementation from remaining live verification | 4c496e1 |
| ZOP-18 | VERIFIED_LOCAL | FeasibilityPathGovernance disallows silent de-scope and requires exact unsupported evidence; tests | 4c496e1 |
| ZOP-19 | VERIFIED_LOCAL | IntegrationDepthAuditor and feasibility policy record technical limitation plus deepest legitimate alternative; tests | 4c496e1 |
| DCA-1 | VERIFIED_LOCAL | DeterministicExecutionPlan builder/executor reuse capability registry, typed dependencies/constraints and bounded parallel groups; plan tests | 4c496e1 |
| DCA-2 | VERIFIED_LOCAL | VerifiedFact/DeterministicResultComposer builds factual answer/cards/actions/unknowns without AI; composer tests | 4c496e1 |
| DCA-3 | VERIFIED_LOCAL | BoundedAIInterpretation performs at most one schema-validated interpretation, no side effects, timeout fallback; tests | 4c496e1 |
| DCA-4 | VERIFIED_LOCAL | PerformanceRecorder records resolution/planning/provider/critical-path/TTFR/total/calls/cancellation/AI metrics; coordination acceptance tests | 4c496e1 |
| DCA-5 | VERIFIED_LOCAL | gap map and M8 sequencing integrated only missing coordination components without reopening M0–M7 | 4c496e1 |
