#!/usr/bin/env python3
"""Read-only UniversalAssistant physical diagnostic reader (local store or SSH)."""
import argparse, json, pathlib, subprocess, sys

DEFAULT_STORE = pathlib.Path("/mnt/HC_Volume_106589590/universalassistant-diagnostics/data")

def records(store):
    values = []
    directories = [store] if store.name in ("sessions", "bootstrap") or any(store.glob("*.json")) else [store / "sessions", store / "bootstrap"]
    for directory in directories:
        for path in directory.glob("*.json"):
            try:
                value = json.loads(path.read_text())
                if "reportID" in value:
                    value.update({"sessionID": value["reportID"], "feature": "app-attest-bootstrap", "result": "FAILURE", "authentication": "pre-attestation-unverified"})
                values.append(value)
            except (OSError, ValueError): pass
    return sorted(values, key=lambda item: item.get("startedAt", 0), reverse=True)

def select(values, args):
    if args.command == "latest":
        if args.feature: values = [v for v in values if v.get("feature") == args.feature]
        if args.build is not None: values = [v for v in values if v.get("build") == args.build]
        return values[:1]
    if args.command == "session": return [v for v in values if v.get("sessionID", "").lower() == args.session_id.lower()]
    if args.command == "failures": return [v for v in values if v.get("result") in ("FAILURE", "CRASH_SUSPECTED", "INTERRUPTED")]
    if args.command == "since": return [v for v in values if str(v.get("startedAt", "")) >= args.timestamp]
    return []

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--store", type=pathlib.Path, default=DEFAULT_STORE)
    parser.add_argument("--ssh", help="Run this read-only command on the authorized VPS")
    parser.add_argument("--json", action="store_true")
    sub = parser.add_subparsers(dest="command", required=True)
    latest = sub.add_parser("latest"); latest.add_argument("--feature"); latest.add_argument("--build", type=int)
    session = sub.add_parser("session"); session.add_argument("session_id")
    sub.add_parser("failures")
    since = sub.add_parser("since"); since.add_argument("timestamp")
    args = parser.parse_args()
    if args.ssh:
        forwarded = ["/usr/local/bin/live-diagnostics", "--json", args.command]
        if args.command == "latest" and args.feature: forwarded += ["--feature", args.feature]
        if args.command == "latest" and args.build is not None: forwarded += ["--build", str(args.build)]
        if args.command == "session": forwarded.append(args.session_id)
        if args.command == "since": forwarded.append(args.timestamp)
        known_hosts = pathlib.Path(__file__).with_name("universalassistant_vps_known_hosts")
        return subprocess.call(["ssh", "-o", "BatchMode=yes", "-o", "StrictHostKeyChecking=yes", "-o", f"UserKnownHostsFile={known_hosts}", args.ssh, *forwarded])
    result = select(records(args.store), args)
    if args.json: print(json.dumps(result, indent=2, sort_keys=True))
    elif not result: print("No matching diagnostics.")
    else:
        for item in result:
            print(f"{item.get('sessionID')} build={item.get('build')} feature={item.get('feature')} result={item.get('result')} schema={item.get('schema')}")
            for event in item.get("events", []): print(f"  {event.get('sequence')}. {event.get('marker')} {event.get('attributes', {})}")
    return 0

if __name__ == "__main__": raise SystemExit(main())
