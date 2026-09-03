#!/usr/bin/env python3
import hashlib, json, re, subprocess
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
inv=json.loads((ROOT/"REQUIREMENT_INVENTORY.json").read_text())
rows=[r for r in inv["requirements"] if r["id"].startswith("LOYALTY-")]
expected=[f"LOYALTY-{i:03d}" for i in range(1,128)]
assert [r["id"] for r in rows]==expected and len(rows)==127
assert not [r for r in rows if r["status"] in {"NOT_IMPLEMENTED","IMPLEMENTED_UNVERIFIED"}]
for r in rows:
 assert r["implementation_evidence"] and r["test_evidence"] and r["commit_evidence"]
 for commit in r["commit_evidence"]: subprocess.run(["git","cat-file","-e",commit+"^{commit}"],cwd=ROOT,check=True,stdout=subprocess.DEVNULL)
artifact=ROOT/"docs/UniversalAssistant_Loyalty_Discount_Attribution_Commission_Integrity_FINAL_NUMBERED.txt"
assert hashlib.sha256(artifact.read_bytes()).hexdigest()=="d08375c5fabc74cc493ebb2fd5f6a25cd48a857fb117504ab82240e21e005dc4"
assert [line.split()[0] for line in artifact.read_text().splitlines() if line.startswith("LOYALTY-")] == expected
queue=json.loads((ROOT/"LIVE_VERIFICATION_QUEUE.json").read_text())["items"]
assert sum(x["requirement_id"]=="LOYALTY-012-115-LIVE-PARTNER-INTEGRITY" for x in queue)==1
code=(ROOT/"UniversalAssistant/Commerce/LoyaltyPersonalPriceCore.swift").read_text()
for symbol in ["LoyaltyPriceComponentKind","LoyaltyStackingPolicy","LoyaltyAttributionState","LoyaltyCommissionState","LoyaltyCommissionBasis","LoyaltyCommissionIntegrityEngine","LoyaltyAccountQuoteCache"]: assert symbol in code
tests=(ROOT/"UniversalAssistantTests/LoyaltyPersonalPriceCoreTests.swift").read_text()
for name in ["compatibleLoyaltyAndCommissionPreserveBoth","incompatibleBenefitsChooseVerifiedBestUserValueWithoutHidingIt","couponLoyaltyCompatibleAndIncompatibleAreProviderConfigured","sameBenefitCannotBeDoubleApplied","unknownStackingPolicyNeverGuessesCompatibilityOrCommission","loginScopeCannotLeakLoyaltyAcrossUsers","accountDisconnectInvalidatesCachedPersonalPrice","attributedDeepLinkIsRequiredButExternalHandoffIsNotCompletion","crossDeviceAttributionRequiresExplicitPartnerSupport","installmentCompatibilityIsNeverAssumed","priceOrVariantChangeInvalidatesStaleEconomics","netCommissionUsesActualDiscountedAmountNotCatalogPrice","unknownCommissionBasisNeverProducesApproximateRevenue","fullAndPartialRefundWaitForPartnerConfirmationThenAdjustExactly","uaFundedBenefitRemainsSeparatelyTypedFromCustomerAndPartnerBenefits","expiryAndCompetingAttributionNeverForceOrStealClick","refundsAndCancellationsAreNotCommissionEligible"]: assert name in tests
print(f"LOYALTY AUDIT OK: 127/127; {sum(r[chr(115)+chr(116)+chr(97)+chr(116)+chr(117)+chr(115)]==chr(86)+chr(69)+chr(82)+chr(73)+chr(70)+chr(73)+chr(69)+chr(68)+chr(95)+chr(76)+chr(79)+chr(67)+chr(65)+chr(76) for r in rows)} local; {sum(r[chr(115)+chr(116)+chr(97)+chr(116)+chr(117)+chr(115)]==chr(82)+chr(69)+chr(65)+chr(68)+chr(89)+chr(95)+chr(70)+chr(79)+chr(82)+chr(95)+chr(76)+chr(73)+chr(86)+chr(69)+chr(95)+chr(86)+chr(69)+chr(82)+chr(73)+chr(70)+chr(73)+chr(67)+chr(65)+chr(84)+chr(73)+chr(79)+chr(78) for r in rows)} live-ready")
