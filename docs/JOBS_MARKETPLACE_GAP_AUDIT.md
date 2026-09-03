# Jobs Marketplace Evidence-Backed Gap Audit

One-time pre-implementation audit on 2026-09-03. It must not be repeated after implementation starts. The repository contained generic web `JobPosting` discovery only; it did not contain a Jobs Marketplace. Existing Business Account, business inbox, connector, exact Decimal ledger, watches, Calendar/Smart Departure, notification, privacy, retention, RemoteConfig and CostQuota components must be reused.

| Capability | Status | Existing production/test evidence | Exact gap |
|---|---|---|---|
| Business Account reuse | ALREADY_IMPLEMENTED | PartnerOnboarding/PartnerProfileService; M9 tests | Wire Jobs tenant to the same partner ID |
| Jobs prepaid entitlements | MISSING | Exact Decimal ledger/quota reusable | Jobs product/credit/reserve/consume/release rules |
| Employer verification | PARTIAL | PartnerOnboarding verification | Gate Jobs publish against existing verified business |
| Vacancy/moderation | MISSING | Fraud/audit primitives reusable | Typed vacancy state, policy risk, edits, complaints/appeal |
| Employment Profile/privacy | MISSING | Account/privacy/retention stores reusable | Consent, PRIVATE/DISCOVERABLE and field disclosure |
| CV/application snapshot | MISSING | Documents and inbox reusable | Versioned CV and immutable confirmed application |
| Search/matching/source priority | PARTIAL | GenericIntent jobs extraction | Typed hard/soft matching and sufficiency-gated source tiers |
| Candidate/employer search/contact | MISSING | Tenant auth/inbox reusable | Paid discoverable-only search and consented invitation |
| Interview/lifecycle | PARTIAL | Calendar/Appointment/Smart Departure | Jobs transition validator and links |
| Watches | PARTIAL | ProactiveWatchEngine | Jobs criteria, fresh/dedup/priority behavior |
| ATS/feed connectors | PARTIAL | BusinessOperations connector capabilities | Jobs-specific create/update/close/status capability contract |
| Commercial registry/attribution | PARTIAL | Affiliate registry/agreement/ledger | Jobs-specific active/effective source classification |
| Ukrainian sources | MISSING | generic web discovery only | Conservative provider registry and truthful fallback adapters |
| Admin/observability/persistence | PARTIAL | M9 admin/audit/config/quota | Jobs events and durable restart tests |
| Native result/action | PARTIAL | Generic result cards | Jobs card and truthful open/apply semantics |

## Legacy source blocker

JOBS-087/JOBS-092 require a byte-accurate map of a prior legacy Jobs addendum sections 1–95. The supplied file references that document but does not contain its section text; repository history and unreachable blobs contain no copy. Assigning `PRESERVED`, `PRESERVED_AND_EXTENDED`, `SUPERSEDED_BY_NEWER_OWNER_DECISION` or `NOT_APPLICABLE_VERIFIED` without the source would fabricate evidence. The exact missing dependency is the complete prior legacy Jobs Marketplace addendum sections 1–95 from the owner. All independent current JOBS-ID work proceeds.
