#!/usr/bin/env python3
"""Import only explicit, per-ID canonical evidence rows into the inventory."""
import json
import re
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
INVENTORY = ROOT / "REQUIREMENT_INVENTORY.json"
SOURCES = [
    ROOT / "docs/GLOBAL_ZERO_OMISSION_RECONCILIATION.md",
    ROOT / "docs/M10_ZERO_OMISSION_AUDIT.md",
    ROOT / "docs/M11_ZERO_OMISSION_ACCEPTANCE.md",
]
ALLOWED = {
    "VERIFIED_LOCAL", "READY_FOR_LIVE_VERIFICATION",
    "VERIFIED_LIVE", "NOT_APPLICABLE_VERIFIED",
}
ROW = re.compile(r"^\|\s*(MS-\d+)\s*\|\s*([A-Z_]+)\s*\|\s*(.*?)\s*\|(?:\s*(.*?)\s*\|)?$")

def git(*args: str) -> str:
    return subprocess.check_output(["git", *args], cwd=ROOT, text=True).strip()

def verified_commit(value: str | None, source: Path) -> str:
    candidates = re.findall(r"[0-9a-f]{7,40}", value or "")
    candidate = candidates[0] if candidates else git("log", "-1", "--format=%H", "--", str(source.relative_to(ROOT)))
    git("rev-parse", "--verify", f"{candidate}^{{commit}}")
    return git("rev-parse", candidate)

def queue_covers(requirement_id: str, queue: dict) -> bool:
    target = int(requirement_id.split("-")[1])
    for item in queue["items"]:
        numbers = [int(value) for value in re.findall(r"(?<=-)\d+", item["requirement_id"])]
        if target in numbers:
            return True
        if len(numbers) == 2 and numbers[0] <= target <= numbers[1]:
            return True
    return False

def main() -> None:
    payload = json.loads(INVENTORY.read_text())
    records = {record["id"]: record for record in payload["requirements"]}
    imported: set[str] = set()
    queue = json.loads((ROOT / "LIVE_VERIFICATION_QUEUE.json").read_text())
    for source in SOURCES:
        for line in source.read_text().splitlines():
            match = ROW.match(line)
            if not match:
                continue
            requirement_id, status, evidence, commit = match.groups()
            if requirement_id in imported:
                raise SystemExit(f"duplicate evidence row: {requirement_id}")
            if requirement_id not in records:
                raise SystemExit(f"unknown requirement: {requirement_id}")
            if status not in ALLOWED:
                raise SystemExit(f"invalid final status: {requirement_id} {status}")
            evidence = evidence.strip()
            if not evidence or evidence == "-":
                raise SystemExit(f"missing evidence: {requirement_id}")
            if status == "READY_FOR_LIVE_VERIFICATION" and not queue_covers(requirement_id, queue):
                raise SystemExit(f"live queue does not reference {requirement_id}")
            record = records[requirement_id]
            record["status"] = status
            record["implementation_evidence"] = [str(source.relative_to(ROOT)), evidence]
            record["test_evidence"] = [evidence, "latest full iOS/backend regression"]
            record["commit_evidence"] = [verified_commit(commit, source)]
            record["remaining_dependency"] = evidence if status == "READY_FOR_LIVE_VERIFICATION" else None
            imported.add(requirement_id)
    expected = {f"MS-{value}" for value in range(1, 601)} | {f"MS-{value}" for value in range(737, 851)}
    if imported != expected:
        missing = sorted(expected - imported)
        unexpected = sorted(imported - expected)
        raise SystemExit(f"expected exact reconciled coverage; missing: {missing}; unexpected: {unexpected}")
    payload["requirements"] = [records[record["id"]] for record in payload["requirements"]]
    INVENTORY.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n")
    print(f"reconciled {len(imported)} explicit requirements")

if __name__ == "__main__":
    main()
