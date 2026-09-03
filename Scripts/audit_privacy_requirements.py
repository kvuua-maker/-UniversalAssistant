#!/usr/bin/env python3
import hashlib,json,subprocess
from pathlib import Path
R=Path(__file__).resolve().parents[1]; inv=json.loads((R/"REQUIREMENT_INVENTORY.json").read_text()); rows=[x for x in inv["requirements"] if x["id"].startswith("PRIVACY-")]; expected=[f"PRIVACY-{i:03d}" for i in range(1,169)]; assert [x["id"] for x in rows]==expected; assert not [x for x in rows if x["status"] in {"NOT_IMPLEMENTED","IMPLEMENTED_UNVERIFIED"}]
for x in rows:
 assert x["implementation_evidence"] and x["test_evidence"] and x["commit_evidence"]
 for c in x["commit_evidence"]: subprocess.run(["git","cat-file","-e",c+"^{commit}"],cwd=R,check=True,stdout=subprocess.DEVNULL)
a=R/"docs/UniversalAssistant_Privacy_AI_Data_Flow_Hardening_FINAL_NUMBERED.txt"; assert hashlib.sha256(a.read_bytes()).hexdigest()=="2cd2094900eb086a176ba85a84f22555d9ba9d167132b8b5bfb33422dffe10ea"; assert [l.split()[0] for l in a.read_text().splitlines() if l.startswith("PRIVACY-")]==expected
q=json.loads((R/"LIVE_VERIFICATION_QUEUE.json").read_text())["items"]; assert sum(x["requirement_id"]=="PRIVACY-016-157-LIVE-DATA-FLOW" for x in q)==1
code=(R/"UniversalAssistant/Policy/PrivacyOutboundGate.swift").read_text()+(R/"UniversalAssistant/Core/BoundedAIInterpretation.swift").read_text(); tests=(R/"UniversalAssistantTests/PrivacyOutboundGateTests.swift").read_text()
for x in ["PrivacyDataClassification","neverAI","PrivacyOutboundGate","PrivacyConsentState","PrivacyContentTrust","PrivacyScopeKey","sanitizeUntrustedContent","privacyGate.evaluate"]: assert x in code
for x in ["everyAIProviderBlocksAllNeverAIClasses","osPermissionDoesNotEqualExternalConsent","providerSwitchCannotWeakenClassificationConsentOrPurpose","promptInjectionCannotAuthorizeSecretsOrUnrelatedAccess","scopedCacheCannotBleedAndRevocationIsImmediate","safeLocalFallbackSurvivesBlockedSensitiveTransfer"]: assert x in tests
print("PRIVACY AUDIT OK: 168/168; %d local; %d live-ready"%(sum(x["status"]=="VERIFIED_LOCAL" for x in rows),sum(x["status"]=="READY_FOR_LIVE_VERIFICATION" for x in rows)))
