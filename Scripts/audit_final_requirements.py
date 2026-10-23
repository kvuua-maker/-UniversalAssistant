#!/usr/bin/env python3
import hashlib, json, re, subprocess, sys
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
INV = json.loads((ROOT / "REQUIREMENT_INVENTORY.json").read_text())
QUEUE = json.loads((ROOT / "LIVE_VERIFICATION_QUEUE.json").read_text())
expected = ([f"MS-{i}" for i in range(1, 1661)] + [f"MCA-{i}" for i in range(1, 65)] +
            [f"BPP-{i}" for i in range(1, 38)] + [f"ZOP-{i}" for i in range(1, 22)] +
            [f"JOBS-{i:03d}" for i in range(1, 98)] + [f"LOYALTY-{i:03d}" for i in range(1, 128)] + [f"PRIVACY-{i:03d}" for i in range(1, 169)] + [f"AUDIO-{i:03d}" for i in range(1, 148)] + [f"LIVE-DIAG-{i:03d}" for i in range(1, 79)] + [f"DCA-{i}" for i in range(1, 6)])
rows = INV["requirements"]
ids = [r["id"] for r in rows]
assert INV["requirement_count"] == 2404 == len(rows)
assert ids == expected, "canonical IDs are missing, duplicated, reordered or unexpected"
assert not [r for r in rows if r["status"] in {"NOT_IMPLEMENTED", "IMPLEMENTED_UNVERIFIED"}]
allowed = set(INV["allowed_statuses"])
assert all(r["status"] in allowed for r in rows)

def queue_covers(rid):
    match = re.fullmatch(r"(.+)-(\d+)", rid)
    assert match, f"invalid canonical requirement ID: {rid}"
    prefix, target = match.group(1), int(match.group(2))
    for item in QUEUE["items"]:
        qid = item["requirement_id"]
        if not qid.startswith(prefix + "-"): continue
        nums = [int(v) for v in re.findall(r"(?<=-)\d+", qid)]
        if target in nums or (len(nums) == 2 and nums[0] <= target <= nums[1]): return True
    return False

ready = [r for r in rows if r["status"] == "READY_FOR_LIVE_VERIFICATION"]
assert all(queue_covers(r["id"]) for r in ready)
required_queue_fields = {"requirement_id","service_provider","current_status","missing_dependency","dependency_owner","local_evidence","required_live_action","expected_result","created_at","last_checked","completion_evidence"}
for item in QUEUE["items"]:
    assert required_queue_fields <= item.keys()
    assert item["current_status"] in {"READY_FOR_LIVE_VERIFICATION", "BLOCKED_BY_CONFIRMED_DEFECT", "VERIFIED_LIVE"}
    assert item["dependency_owner"] and item["local_evidence"]
    assert item["required_live_action"] and item["expected_result"]
    if item["current_status"] == "VERIFIED_LIVE":
        assert item["missing_dependency"] is None and item["completion_evidence"]
    else:
        assert item["missing_dependency"] and item["completion_evidence"] is None
commits = set()
for row in rows:
    if row["status"] not in {"NOT_IMPLEMENTED", "IMPLEMENTED_UNVERIFIED"}:
        assert row["implementation_evidence"] and row["test_evidence"] and row["commit_evidence"]
        commits.update(row["commit_evidence"])
shallow = subprocess.run(["git","rev-parse","--is-shallow-repository"],cwd=ROOT,capture_output=True,text=True).stdout.strip()
if shallow == "true":
    raise SystemExit("audit requires full git history: check out with fetch-depth: 0 (shallow clone cannot verify evidence commits)")
for commit in commits:
    subprocess.run(["git","rev-parse","--verify",f"{commit}^{{commit}}"], cwd=ROOT, check=True, stdout=subprocess.DEVNULL)
for base in [ROOT/'UniversalAssistant', ROOT/'Backend/Sources', ROOT/'ShareExtension']:
    for path in base.rglob('*.swift'):
        if path.name == 'CapabilityEvidenceGovernance.swift': continue
        low = path.read_text(errors='ignore').lower()
        for marker in ['todo','fixme','placeholder','fake success','fake-success','hardcoded demo']:
            assert marker not in low, f"production marker {marker}: {path}"
canonical_hashes = {
    "UniversalAssistant_FULL_UNABRIDGED_MASTER_SPEC_v13.2_MAC_GIT_VERIFIED_FINAL.txt": "16489fc577d199918fedb99f68e5fb59548361f4e15f1253cf3c9e7f2bd8fd95",
    "UniversalAssistant_v13.2_MARKETPLACE_COMMERCE_AFFILIATE_FINAL_ADDENDUM.txt": "299bf8025f23a120c77329f831c26217b9ba810835322cf8b085fc09d6c9c23b",
    "DETERMINISTIC_MULTI_STEP_COORDINATION_BOUNDED_AI_FALLBACK_ADDENDUM.md": "7bff9bbd535f1d5e2de52c154d8726552771412ee2160247749e5b739ef9a0ef",
    "UniversalAssistant_Business_Partner_Platform_FINAL.txt": "9cc1b9eba8641f9858bb3e599a48787f50180d6fc68e76165bcaf70ad17022b7",
    "ZERO_OMISSION_REQUIREMENTS_VERIFICATION_EXTERNAL_DEPENDENCY_COMPLETION_POLICY.md": "bb12b460bc75ae32d7404e33fe000b9f1ce7e5af13386c4997ee5430aadf7d21",
    "VOICE_OUTPUT_POLICY_ADDENDUM.md": "1a302401f5d5b15844a85d6721be6260f579c583d5aa61246bb1ce4d3f4ff5ea",
    "UNIVERSALASSISTANT_FINAL_VISUAL_UI_UX_DESIGN_SYSTEM_ADDENDUM.md": "d69ab80ed56c01a54c7a5bbf64e669cfdc222c1200c4270c2d44a86dc5c8fa28",
    "QUICK_LAUNCH_PHYSICAL_ACCESS_ADDENDUM.md": "c8a6d5392340b61a6716fb5239445faf108ed5eebcdfc414462e135afdff9ba4",
    "BUSINESS_PLATFORM_COMPETITIVE_GAP_AUDIT.md": "9e90bffe15f8f008bb71185449df579120b0fe94b89bc2f34ee3f73243dc8e7d",
    "GENERAL_UNKNOWN_INTENT_DISCOVERY_ANSWER_ACTION_ADDENDUM.md": "5f3f4f051ee4758a7e6981c1d33b2d12354fc74987ebcb99b94635070cb266fe",
    "UniversalAssistant_Jobs_Marketplace_FINAL_CLEAR_NUMBERED.txt": "4b46941d2c6d6930c328a726e5ee1d3c9d56c178aad9fe596d6913e5e33ca7b7",
    "UniversalAssistant_Loyalty_Discount_Attribution_Commission_Integrity_FINAL_NUMBERED.txt": "d08375c5fabc74cc493ebb2fd5f6a25cd48a857fb117504ab82240e21e005dc4",
    "UniversalAssistant_Privacy_AI_Data_Flow_Hardening_FINAL_NUMBERED.txt": "2cd2094900eb086a176ba85a84f22555d9ba9d167132b8b5bfb33422dffe10ea",
    "UniversalAssistant_Universal_Audio_Device_Control_FINAL_NUMBERED.txt": "50b594e3027f9b1f6ed446f9222e534430e33566b8ad3cd2b0d45f13d4708a50",
    "UniversalAssistant_Physical_Device_Live_Diagnostic_Loop_FINAL_NUMBERED.md": "595edc4f61990fd97330883a79223505da8e115254ac273272628d5b4b8b1f63",
}
for name, expected_hash in canonical_hashes.items():
    actual = hashlib.sha256((ROOT / "docs" / name).read_bytes()).hexdigest()
    assert actual == expected_hash, f"canonical source hash mismatch: {name}"
report=(ROOT/'docs/LIVE_VERIFICATION_QUEUE_REPORT.md').read_text()
assert report.count('|') > len(QUEUE['items']) * 3
# Metadata alone cannot prove a capability exists. The wiring audit fails on
# unreachable routes, unwired modules, permanently empty screens and missing
# translations, so it must pass before this audit may report success.
subprocess.run([sys.executable, str(ROOT/'Scripts/audit_wiring.py')], check=True)
print(f"FINAL AUDIT OK: {len(rows)} requirements; {len(ready)} READY IDs; {len(QUEUE['items'])} exact live queue items; wiring verified")
