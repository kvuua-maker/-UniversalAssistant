#!/usr/bin/env python3
import json, re, subprocess
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
INV = json.loads((ROOT / "REQUIREMENT_INVENTORY.json").read_text())
QUEUE = json.loads((ROOT / "LIVE_VERIFICATION_QUEUE.json").read_text())
expected = ([f"MS-{i}" for i in range(1, 1661)] + [f"MCA-{i}" for i in range(1, 65)] +
            [f"BPP-{i}" for i in range(1, 38)] + [f"ZOP-{i}" for i in range(1, 22)] +
            [f"DCA-{i}" for i in range(1, 6)])
rows = INV["requirements"]
ids = [r["id"] for r in rows]
assert INV["requirement_count"] == 1787 == len(rows)
assert ids == expected, "canonical IDs are missing, duplicated, reordered or unexpected"
assert not [r for r in rows if r["status"] in {"NOT_IMPLEMENTED", "IMPLEMENTED_UNVERIFIED"}]
allowed = set(INV["allowed_statuses"])
assert all(r["status"] in allowed for r in rows)

def queue_covers(rid):
    prefix, raw = rid.split("-", 1); target = int(raw)
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
    assert item["current_status"] == "READY_FOR_LIVE_VERIFICATION"
    assert item["missing_dependency"] and item["dependency_owner"] and item["local_evidence"]
    assert item["required_live_action"] and item["expected_result"]
    assert item["completion_evidence"] is None
commits = set()
for row in rows:
    if row["status"] not in {"NOT_IMPLEMENTED", "IMPLEMENTED_UNVERIFIED"}:
        assert row["implementation_evidence"] and row["test_evidence"] and row["commit_evidence"]
        commits.update(row["commit_evidence"])
for commit in commits:
    subprocess.run(["git","rev-parse","--verify",f"{commit}^{{commit}}"], cwd=ROOT, check=True, stdout=subprocess.DEVNULL)
for base in [ROOT/'UniversalAssistant', ROOT/'Backend/Sources', ROOT/'ShareExtension']:
    for path in base.rglob('*.swift'):
        if path.name == 'CapabilityEvidenceGovernance.swift': continue
        low = path.read_text(errors='ignore').lower()
        for marker in ['todo','fixme','placeholder','fake success','fake-success','hardcoded demo']:
            assert marker not in low, f"production marker {marker}: {path}"
        assert 'jobsmarketplace' not in low and 'jobs marketplace' not in low
report=(ROOT/'docs/LIVE_VERIFICATION_QUEUE_REPORT.md').read_text()
assert report.count('|') > len(QUEUE['items']) * 3
print(f"FINAL AUDIT OK: {len(rows)} requirements; {len(ready)} READY IDs; {len(QUEUE['items'])} exact live queue items")
