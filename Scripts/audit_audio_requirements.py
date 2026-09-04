#!/usr/bin/env python3
import json
from pathlib import Path
root = Path(__file__).resolve().parents[1]
data = json.loads((root / "REQUIREMENT_INVENTORY.json").read_text())
items = [x for x in data["requirements"] if x["id"].startswith("AUDIO-")]
assert {x["id"] for x in items} == {f"AUDIO-{n:03d}" for n in range(1,148)}
allowed={"VERIFIED_LOCAL","READY_FOR_LIVE_VERIFICATION","VERIFIED_LIVE","NOT_APPLICABLE_VERIFIED"}
for x in items:
 assert x["status"] in allowed and x["implementation_evidence"] and x["test_evidence"] and x["commit_evidence"], x["id"]
 if x["status"] == "READY_FOR_LIVE_VERIFICATION": assert x["remaining_dependency"] and x["live_evidence"], x["id"]
print("AUDIO audit: 147/147 evidence-mapped; local gaps=0")
