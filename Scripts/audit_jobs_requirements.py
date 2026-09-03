#!/usr/bin/env python3
import hashlib, json, re, subprocess
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
inventory=json.loads((ROOT/"REQUIREMENT_INVENTORY.json").read_text())
queue=json.loads((ROOT/"LIVE_VERIFICATION_QUEUE.json").read_text())
jobs=[row for row in inventory["requirements"] if row["id"].startswith("JOBS-")]
expected=[f"JOBS-{i:03d}" for i in range(1,98)]
assert [row["id"] for row in jobs]==expected
assert len(jobs)==97 and len({row["id"] for row in jobs})==97
assert not [row for row in jobs if row["status"] in {"NOT_IMPLEMENTED","IMPLEMENTED_UNVERIFIED"}]
assert all(row["implementation_evidence"] and row["test_evidence"] and row["commit_evidence"] for row in jobs)
queue_ids={item["requirement_id"] for item in queue["items"]}
for row in jobs:
    if row["status"]=="READY_FOR_LIVE_VERIFICATION":
        assert row["remaining_dependency"] in queue_ids
    for commit in row["commit_evidence"]:
        subprocess.run(["git","rev-parse","--verify",f"{commit}^{{commit}}"],cwd=ROOT,check=True,stdout=subprocess.DEVNULL)
ledger=(ROOT/"docs/JOBS_REQUIREMENT_RECONCILIATION.md").read_text()
assert len(re.findall(r"^\| JOBS-\d{3} \|",ledger,re.M))==97
legacy=(ROOT/"docs/JOBS_LEGACY_01_95_COVERAGE.md").read_text()
assert len(re.findall(r"^\| LEGACY-\d{2} \|",legacy,re.M))==95
source=ROOT/"docs/UniversalAssistant_Jobs_Marketplace_FINAL_CLEAR_NUMBERED.txt"
assert hashlib.sha256(source.read_bytes()).hexdigest()=="4b46941d2c6d6930c328a726e5ee1d3c9d56c178aad9fe596d6913e5e33ca7b7"
production="\n".join((ROOT/path).read_text() for path in ["Backend/Sources/UniversalAssistantServer/JobsMarketplace.swift","Backend/Sources/UniversalAssistantServer/JobsPolicyExtensions.swift","UniversalAssistant/Jobs/JobsDiscoveryEngine.swift","UniversalAssistant/Jobs/JobsGoldenJourneys.swift"])
for symbol in ["JobsEntitlementLedger","JobsMarketplaceService","EmploymentProfile","CandidateCV","JobApplicationSnapshot","JobsSourceSelector","JobsPolicyStore","JobsCommercialSource","JobsPromotion","JobDiscoveryEngine","UkrainianJobSourceRegistry"]:
    assert symbol in production
tests="\n".join(path.read_text() for path in list((ROOT/"Backend/Tests/UniversalAssistantServerTests").glob("Jobs*Tests.swift"))+list((ROOT/"UniversalAssistantTests").glob("Jobs*Tests.swift")))
required=["verifiedBusinessEntitlementModerationAndRetryAreExact","unsafeVacancyRejectedAndEntitlementReleased","freePrivateCandidateAndImmutableApplicationSnapshot","paidCandidateSearchNeverLeaksRestrictedContact","ourJobsFirstAndFallbackOnlyWhenInsufficient","lifecycleValidatedIdempotentAndComplaintNotAutomaticGuilt","watchAndATSDedupSurviveRestart","multipleCVsRequiredCVAndMustHaveScreeningAreEnforced","materialEditTriggersReviewAndSalarySemanticsFailClosed","salaryMismatchNeedsReviewAndCrediblePaymentScamProtectsWithoutPublicGuilt","invitationRequiresDiscoverabilityPaidEntitlementAndDeclineKeepsContactPrivate","ATSRequiresDeclaredCapabilityRejectsStaleAndPropagatesClose","expiredVacancyAndHardConstraintsNeverMatch","blockSavedStateAndAppealPersistAcrossRestart","interviewIsProposalUntilCandidateConfirmationAndHTTPSIsRequired","promotionAndCommercialEligibilityFailClosed","runtimePricingQuotaAndRetentionAreConfigurationNotHardcodedPolicy","ourJobsSatisfyRequestWithoutCallingExternalFallback","insufficientOurJobsUsesTruthfulExternalHandoffWithoutRevenueClaim","commercialWithoutCurrentEvidenceIsExcludedAndUnknownSalaryDoesNotPassMinimum","sourceRegistryNeverClaimsUnauditedAPIOrPartnership","corpusIsCompleteStableAndHasConsequentialConfirmations","naturalCandidateJourneyCompilesToTypedJobsIntentWithoutAI","externalJourneysRequireTruthfulHandoffNotFalseApplication"]
assert all(name in tests for name in required)
golden=(ROOT/"UniversalAssistant/Jobs/JobsGoldenJourneys.swift").read_text()
assert len(re.findall(r"id: \"[A-O]\"", golden)) == 15
print(f"JOBS AUDIT OK: {len(jobs)}/97 IDs, 95/95 legacy, {sum(r["status"]=="VERIFIED_LOCAL" for r in jobs)} local, {sum(r["status"]=="READY_FOR_LIVE_VERIFICATION" for r in jobs)} live-ready")
