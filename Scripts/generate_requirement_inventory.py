#!/usr/bin/env python3
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "REQUIREMENT_INVENTORY.json"
ALLOWED = {"NOT_IMPLEMENTED", "IMPLEMENTED_UNVERIFIED", "VERIFIED_LOCAL",
           "READY_FOR_LIVE_VERIFICATION", "VERIFIED_LIVE", "NOT_APPLICABLE_VERIFIED"}

SOURCES = [
    ("MS", ROOT / "docs/UniversalAssistant_FULL_UNABRIDGED_MASTER_SPEC_v13.2_MAC_GIT_VERIFIED_FINAL.txt", re.compile(r"^\s*(\d+)\.\s+(.+)$")),
    ("MCA", ROOT / "docs/UniversalAssistant_v13.2_MARKETPLACE_COMMERCE_AFFILIATE_FINAL_ADDENDUM.txt", re.compile(r"^(\d+)\.\s+(.+)$")),
    ("BPP", ROOT / "docs/UniversalAssistant_Business_Partner_Platform_FINAL.txt", re.compile(r"^(\d+)\.\s+(.+)$")),
    ("ZOP", ROOT / "docs/ZERO_OMISSION_REQUIREMENTS_VERIFICATION_EXTERNAL_DEPENDENCY_COMPLETION_POLICY.md", re.compile(r"^##\s+(\d+)\.\s+(.+)$")),
]

def load_existing():
    if not OUTPUT.exists():
        return {}
    data = json.loads(OUTPUT.read_text())
    return {item["id"]: item for item in data.get("requirements", [])}

def main():
    existing = load_existing()
    records = []
    for prefix, path, pattern in SOURCES:
        for line in path.read_text().splitlines():
            match = pattern.match(line)
            if not match:
                continue
            requirement_id = f"{prefix}-{int(match.group(1))}"
            prior = existing.get(requirement_id, {})
            status = prior.get("status", "NOT_IMPLEMENTED")
            if status not in ALLOWED:
                raise SystemExit(f"invalid status for {requirement_id}: {status}")
            records.append({
                "id": requirement_id,
                "source": str(path.relative_to(ROOT)),
                "title": match.group(2).strip(),
                "status": status,
                "implementation_evidence": prior.get("implementation_evidence", []),
                "test_evidence": prior.get("test_evidence", []),
                "commit_evidence": prior.get("commit_evidence", []),
                "live_evidence": prior.get("live_evidence", []),
                "remaining_dependency": prior.get("remaining_dependency"),
            })
    jobs = ROOT / "docs/UniversalAssistant_Jobs_Marketplace_FINAL_CLEAR_NUMBERED.txt"
    lines = jobs.read_text().splitlines()
    for index, line in enumerate(lines):
        match = re.fullmatch(r"JOBS-(\d{3})", line.strip())
        if not match: continue
        requirement_id = f"JOBS-{int(match.group(1)):03d}"
        title = next((value.strip() for value in lines[index + 1:] if value.strip() and not value.startswith("JOBS-")), requirement_id)
        prior = existing.get(requirement_id, {})
        records.append({"id": requirement_id, "source": str(jobs.relative_to(ROOT)), "title": title, "status": prior.get("status", "NOT_IMPLEMENTED"), "implementation_evidence": prior.get("implementation_evidence", []), "test_evidence": prior.get("test_evidence", []), "commit_evidence": prior.get("commit_evidence", []), "live_evidence": prior.get("live_evidence", []), "remaining_dependency": prior.get("remaining_dependency")})
    coordination = ROOT / "docs/DETERMINISTIC_MULTI_STEP_COORDINATION_BOUNDED_AI_FALLBACK_ADDENDUM.md"
    for index, title in enumerate(["Deterministic core", "Facts and composition", "Bounded AI fallback", "Observability and acceptance", "Roadmap rule"], 1):
        requirement_id = f"DCA-{index}"
        prior = existing.get(requirement_id, {})
        records.append({
            "id": requirement_id, "source": str(coordination.relative_to(ROOT)), "title": title,
            "status": prior.get("status", "NOT_IMPLEMENTED"),
            "implementation_evidence": prior.get("implementation_evidence", []),
            "test_evidence": prior.get("test_evidence", []),
            "commit_evidence": prior.get("commit_evidence", []),
            "live_evidence": prior.get("live_evidence", []),
            "remaining_dependency": prior.get("remaining_dependency"),
        })
    identifiers = [record["id"] for record in records]
    if len(identifiers) != len(set(identifiers)):
        raise SystemExit("duplicate requirement ID")
    payload = {"schema_version": 1, "allowed_statuses": sorted(ALLOWED),
               "requirement_count": len(records), "requirements": records}
    OUTPUT.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n")
    print(f"wrote {len(records)} requirements")

if __name__ == "__main__":
    main()
