# M9 Business Partner Platform Acceptance

Local E3 acceptance traceability for the canonical addendum:

- A — submitted application cannot become active: `PartnerOnboardingTests.submittedFormCannotBecomeActiveWithoutVerificationAndApproval`.
- B/O — Partner A cannot access Partner B and dashboard isolation is backend-enforced: `PartnerTenantAuthorizationTests.partnerACannotReadOrWritePartnerB`.
- C — commission does not alter organic ranking: `NormalizedOfferTests.rankingIsIndependentOfAffiliateCommissionSignal`.
- D — sponsored placement is explicitly separate/disclosed: `SponsoredResultSeparationTests.sponsoredPlacementIsSeparateAndExplicitlyDisclosed`.
- E — duplicate webhook has one accepted event and no duplicate downstream eligibility: `PartnerWebhookIngestionTests.validSignedEventIsAcceptedOnce` plus ledger event idempotency.
- F — full/partial refunds append exact adjustments: `ConversionLedgerTests.confirmationAndPartialRefundAreExactAppendOnlyAdjustments`.
- G — qualifying event resolves immutable historical agreement: `CommercialAgreementTests.qualifyingEventUsesHistoricalVersionWithoutRewrite`.
- H — stale/manual data is not verified live: `PartnerFeedHealthTests.freshnessNeverPresentsStaleOrManualDataAsVerifiedLive`.
- I — one provider failure preserves alternatives: `ProviderFanoutEngineTests.ticketProviderFailureReturnsRankedPartialResults` and partner-specific health tests.
- J — reconciliation detects missing/duplicate/amount/currency/status/refund mismatches: `ReconciliationSettlementTests`.
- K — suspended/terminated partner receives no new monetizable handoff: `PartnerFeedHealthTests.suspendedPartnerGetsNoNewHandoffAndCredentialsAreRevoked`.
- L — useful non-partner result remains organic: `SponsoredResultSeparationTests.sponsoredPlacementIsSeparateAndExplicitlyDisclosed`.
- M — financial arithmetic uses exact `Decimal`, including fractional refund adjustments: `ConversionLedgerTests.confirmationAndPartialRefundAreExactAppendOnlyAdjustments` and quota tests.
- N — secrets are absent from audit/client/log contracts: `PartnerWebhookIngestionTests.auditSurfaceContainsNoSecretSignatureOrPayload`; credentials remain inside the server actor.
- P — commercial model and runtime activation change through agreement/config without core rewrites: `CommercialAgreementTests.allCanonicalModelsAreConfigurationValues` and `PartnerRuntimePolicyTests.featureFlagsAreVersionedScopedAndFailClosed`.

Additional M9 Master Spec gates are covered by versioned feature policy, exact atomic cost/quota control and auditable fraud/abuse signals. The implementation deliberately excludes merchant-of-record behavior, payment processing, invented pricing, tax conclusions and production activation decisions.
