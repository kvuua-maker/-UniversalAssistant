#!/usr/bin/env python3
"""Automatic CloudKit ingestion for existing UniversalAssistant diagnostics."""

from __future__ import annotations
import argparse, base64, datetime as dt, fcntl, hashlib, json, os
import difflib
from pathlib import Path
import shutil, subprocess, sys, time, urllib.error, urllib.parse, urllib.request, uuid

CONTAINER = "iCloud.com.universalassistant.app"
RECORD_TYPE = "UADiagnosticAudio"
DEFAULT_KEY_ID = "125e3318684514f53708d72323451af3991fc75248d7897d1259d59a9ac448ad"
ROOT = Path.home() / "Library/Application Support/UniversalAssistant/DiagnosticIngestion"
KEY = Path.home() / "Library/Application Support/UniversalAssistant/CloudKitCredentials/diagnostics-server-key.pem"
WHISPER = ROOT / "whisper/bin/whisper-cli"
MODEL = ROOT / "whisper/models/ggml-large-v3-turbo-q5_0.bin"
CODEX = Path.home() / ".local/bin/codex"


def now_iso():
    return dt.datetime.now(dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def atomic_json(path: Path, value) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(json.dumps(value, ensure_ascii=False, indent=2, sort_keys=True) + "\n")
    os.replace(temporary, path)


def field(record: dict, name: str, default=None):
    return record.get("fields", {}).get(name, {}).get("value", default)


class CloudKit:
    def __init__(self, key_id: str, private_key: Path):
        if not private_key.is_file():
            raise RuntimeError(f"missing CloudKit private key: {private_key}")
        self.key_id, self.private_key = key_id, private_key

    def post(self, operation: str, payload: dict) -> dict:
        path = f"/database/1/{CONTAINER}/production/public/{operation}"
        body = json.dumps(payload, separators=(",", ":"), sort_keys=True).encode()
        request_date = now_iso()
        body_hash = base64.b64encode(hashlib.sha256(body).digest()).decode()
        signable = f"{request_date}:{body_hash}:{path}".encode()
        signature = subprocess.run(
            ["/usr/bin/openssl", "dgst", "-sha256", "-sign", str(self.private_key)],
            input=signable, capture_output=True, check=True
        ).stdout
        headers = {
            "Content-Type": "text/plain",
            "X-Apple-CloudKit-Request-KeyID": self.key_id,
            "X-Apple-CloudKit-Request-ISO8601Date": request_date,
            "X-Apple-CloudKit-Request-SignatureV1": base64.b64encode(signature).decode(),
        }
        request = urllib.request.Request(
            "https://api.apple-cloudkit.com" + path, data=body, headers=headers, method="POST"
        )
        try:
            with urllib.request.urlopen(request, timeout=15) as response:
                result = json.load(response)
        except urllib.error.HTTPError as error:
            detail = error.read().decode(errors="replace")
            raise RuntimeError(f"CloudKit HTTP {error.code}: {detail[:800]}") from error
        if result.get("serverErrorCode"):
            raise RuntimeError(f"CloudKit {result['serverErrorCode']}: {result.get('reason')}")
        return result

    def records(self) -> list[dict]:
        query = {
            "query": {
                "recordType": RECORD_TYPE,
                "filterBy": [{
                    "fieldName": "physicalBuild",
                    "comparator": "GREATER_THAN",
                    "fieldValue": {"value": 0},
                }],
                "sortBy": [{"fieldName": "capturedAt", "ascending": False}],
            },
            "resultsLimit": 200,
        }
        return self.post("records/query", query).get("records", [])


def decode_trace(record: dict) -> tuple[bytes, dict]:
    encoded = field(record, "requestTrace")
    if not isinstance(encoded, str):
        raise RuntimeError("requestTrace BYTES absent")
    data = base64.b64decode(encoded, validate=True)
    expected_count = int(field(record, "requestTraceByteCount", -1))
    expected_hash = str(field(record, "requestTraceSHA256", ""))
    if len(data) != expected_count or sha256(data) != expected_hash:
        raise RuntimeError("requestTrace integrity mismatch")
    return data, json.loads(data)


def download_audio(record: dict, destination: Path) -> tuple[int, str]:
    asset = field(record, "audio")
    if int(field(record, "audioByteCount", -1)) == 0 and not asset:
        return 0, sha256(b"")
    if not isinstance(asset, dict) or not asset.get("downloadURL"):
        raise RuntimeError("audio CKAsset absent")
    placeholder = "$" + "{f}"
    url = asset["downloadURL"].replace(placeholder, urllib.parse.quote(destination.name))
    with urllib.request.urlopen(urllib.request.Request(url), timeout=30) as response:
        data = response.read()
    destination.write_bytes(data)
    actual_hash = sha256(data)
    if len(data) != int(field(record, "audioByteCount", -1)):
        raise RuntimeError("audio byte count mismatch")
    if actual_hash != str(field(record, "audioSHA256", "")):
        raise RuntimeError("audio SHA-256 mismatch")
    return len(data), actual_hash


def locale_from(trace: dict) -> str | None:
    for event in trace.get("events") or []:
        locale = (event.get("attributes") or {}).get("locale")
        if locale:
            return str(locale)
    return None


def transcribe(audio: Path, bundle: Path, locale: str | None, whisper: Path, model: Path) -> dict:
    language = (locale or "auto").replace("_", "-").split("-", 1)[0].lower()
    if language != "auto" and len(language) not in (2, 3):
        language = "auto"
    if not whisper.is_file() or not model.is_file():
        return {"status": "UNAVAILABLE", "language": language, "text": None}
    wav = bundle / "audio-16k.wav"
    subprocess.run(
        ["/usr/bin/afconvert", str(audio), str(wav), "-f", "WAVE", "-d", "LEI16@16000", "-c", "1"],
        capture_output=True, check=True
    )
    output = bundle / "independent-transcription"
    subprocess.run(
        [str(whisper), "-m", str(model), "-f", str(wav), "--language", language,
         "--no-timestamps", "--no-prints", "--output-json", "--output-file", str(output)],
        capture_output=True, check=True
    )
    result = json.loads(output.with_suffix(".json").read_text())
    text = "".join(str(item.get("text", "")) for item in result.get("transcription", [])).strip()
    wav.unlink(missing_ok=True)
    return {
        "status": "PASS", "requestedLocale": locale,
        "language": result.get("result", {}).get("language", language),
        "engine": "whisper.cpp large-v3-turbo-q5_0", "text": text,
    }


def summarize(trace: dict) -> dict:
    events = trace.get("events") or []
    def latest(markers, key):
        for event in reversed(events):
            if event.get("marker") in markers:
                value = (event.get("attributes") or {}).get(key)
                if value is not None:
                    return value
        return None
    def latest_text(markers):
        for event in reversed(events):
            if event.get("marker") in markers and event.get("textPayload") is not None:
                return event.get("textPayload")
        return None
    request_id = str(trace.get("requestID", "")).lower()
    action_events = [
        event for event in events
        if event.get("marker") in ("execution_started", "compound_step")
        or str(event.get("marker", "")).endswith("COMPOUND_STEP_PRE")
    ]
    return {
        "partialTranscripts": [
            event.get("textPayload") for event in events
            if event.get("marker") == "partial_transcript" and event.get("textPayload")
        ],
        "appleFinalTranscript": latest_text(("APPLE_FINAL",)) or trace.get("finalSpeechTranscript"),
        "stabilizedTranscript": latest_text(("STABILIZED_TRANSCRIPT",)),
        "visibleTranscript": latest_text(("VISIBLE_TRANSCRIPT",)),
        "submittedText": latest_text(("SUBMITTED_TEXT",)) or trace.get("finalSpeechTranscript"),
        "finalTranscript": trace.get("finalSpeechTranscript"),
        "normalizedTranscript": trace.get("normalizedTranscript"),
        "semanticEvents": [
            event for event in events if event.get("marker") == "canonical_semantic_frame"
        ],
        "capability": latest(("selected_capability", "router_accepted"), "capability"),
        "route": latest(("selected_capability", "router_accepted"), "route"),
        "provider": latest(("selected_capability", "execution_started"), "provider"),
        "executor": latest(("execution_started", "EXECUTOR_PRE", "PROVIDER_PRE"), "mechanism"),
        "boundaries": [
            event for event in events if str(event.get("marker", "")).endswith(("_PRE", "_POST"))
        ],
        "actions": [
            {"actionID": f"{request_id}:A{index:02d}", "event": event}
            for index, event in enumerate(action_events, 1)
        ],
        "result": latest(("visible_result", "execution_failed", "EXECUTOR_POST"), "result")
                  or trace.get("result"),
        "errorDomain": trace.get("errorDomain"), "errorCode": trace.get("errorCode"),
        "failureStage": trace.get("failureStage"), "terminalState": trace.get("terminalState"),
    }


def transcript_correlation(independent: dict, production: dict) -> dict:
    values = {
        "realAudio": independent.get("text"),
        "appleFinal": production.get("appleFinalTranscript"),
        "stabilized": production.get("stabilizedTranscript"),
        "submitted": production.get("submittedText"),
    }
    pairs = (("APPLE", "realAudio", "appleFinal"),
             ("STABILIZER", "appleFinal", "stabilized"),
             ("SUBMIT", "stabilized", "submitted"))
    differences = {}
    first = "NONE"
    for stage, left_name, right_name in pairs:
        left, right = values[left_name], values[right_name]
        if left is None or right is None:
            differences[stage] = {"status": "UNKNOWN", "left": left, "right": right}
            if first == "NONE":
                first = "MISSING_EVIDENCE"
            continue
        delta = list(difflib.ndiff(str(left).split(), str(right).split()))
        changed = [item for item in delta if item[:1] in ("+", "-")]
        differences[stage] = {"status": "MATCH" if not changed else "DIFF", "tokens": changed}
        if changed and first == "NONE":
            first = stage
    return {"values": values, "differences": differences, "firstDivergence": first}


def date_epoch(value) -> float | None:
    if not isinstance(value, (int, float)):
        return None
    value = float(value)
    if value < 1_200_000_000:
        return value + 978307200.0
    return value / 1000.0 if value > 4_000_000_000 else value


def launch_codex(bundle: Path, executable: Path) -> None:
    if not executable.is_file():
        return
    prompt = (
        "READ-ONLY. Проаналізуй лише analysis.json і trace.json у поточному каталозі. "
        "Українською визнач earliest divergence між independent audio transcription, "
        "Apple Speech transcript, semantic route, executor і result. Не змінюй нічого "
        "і не вигадуй відсутні факти."
    )
    log = (bundle / "codex-exec.log").open("ab")
    subprocess.Popen(
        [str(executable), "exec", "--ephemeral", "--sandbox", "read-only",
         "--skip-git-repo-check", "-C", str(bundle), "-o",
         str(bundle / "codex-analysis-uk.txt"), prompt],
        stdout=log, stderr=subprocess.STDOUT, start_new_session=True
    )


def process(record, args) -> tuple[str, dict]:
    request_id = str(field(record, "requestID", "")).lower()
    uuid.UUID(request_id)
    trace_data, trace = decode_trace(record)
    if str(trace.get("requestID", "")).lower() != request_id:
        raise RuntimeError("record/trace RequestID mismatch")
    final = args.root / "requests" / request_id
    temporary = args.root / "requests" / ("." + request_id + ".tmp")
    if temporary.exists():
        shutil.rmtree(temporary)
    temporary.mkdir(parents=True)
    started = time.time()
    (temporary / "trace.json").write_bytes(trace_data)
    audio = temporary / "audio.caf"
    byte_count, audio_hash = download_audio(record, audio)
    independent = (
        transcribe(audio, temporary, locale_from(trace), args.whisper, args.model)
        if byte_count > 0 else
        {"status": "NO_AUDIO_VOICE_START_FAILURE", "language": locale_from(trace), "text": None}
    )
    ended = date_epoch(trace.get("endedAt"))
    latency = started - ended if ended is not None else None
    production = summarize(trace)
    analysis = {
        "schema": 1, "requestID": request_id, "recordName": record.get("recordName"),
        "physicalBuild": field(record, "physicalBuild"), "deviceModel": field(record, "deviceModel"),
        "systemVersion": field(record, "systemVersion"), "capturedAt": field(record, "capturedAt"),
        "analysisStartedAt": dt.datetime.fromtimestamp(started, dt.timezone.utc).isoformat(),
        "deliveryLatencySeconds": latency,
        "deliveryLatencyStatus": "DELIVERY_LATENCY_FAIL" if latency is not None and latency > 5 else "PASS",
        "audio": {"byteSize": byte_count, "sha256": audio_hash,
                  "durationMilliseconds": field(record, "durationMilliseconds")},
        "independentTranscription": independent, "productionTrace": production,
        "audioTextSubmittedCorrelation": transcript_correlation(independent, production),
        "requestIDCorrelation": "PASS",
    }
    atomic_json(temporary / "analysis.json", analysis)
    if final.exists():
        shutil.rmtree(temporary)
    else:
        os.replace(temporary, final)
    if not args.no_codex:
        launch_codex(final, args.codex)
    return request_id, analysis


def load_state(path: Path) -> dict:
    try:
        value = json.loads(path.read_text())
        return value if isinstance(value, dict) else {}
    except (FileNotFoundError, json.JSONDecodeError):
        return {}


def run_once(client: CloudKit, args, state_path: Path) -> None:
    state = load_state(state_path)
    processed = set(state.get("processedRequestIDs") or [])
    for record in client.records():
        request_id = str(field(record, "requestID", "")).lower()
        if not request_id or request_id in processed or field(record, "requestTrace") is None:
            continue
        try:
            request_id, analysis = process(record, args)
            processed.add(request_id)
            state.update({
                "processedRequestIDs": sorted(processed),
                "lastProcessedRequestID": request_id,
                "lastAnalysisStartedAt": analysis["analysisStartedAt"],
                "lastDeliveryLatencyStatus": analysis["deliveryLatencyStatus"],
            })
        except Exception as error:
            state["lastError"] = {
                "requestID": request_id, "timestamp": now_iso(),
                "category": type(error).__name__, "message": str(error)[:1000],
            }
        atomic_json(state_path, state)
    state["lastCheckedAt"] = now_iso()
    atomic_json(state_path, state)


def arguments():
    parser = argparse.ArgumentParser()
    parser.add_argument("--once", action="store_true")
    parser.add_argument("--no-codex", action="store_true")
    parser.add_argument("--poll-seconds", type=float, default=1.0)
    parser.add_argument("--root", type=Path, default=ROOT)
    parser.add_argument("--key-id", default=os.getenv("UA_CLOUDKIT_KEY_ID", DEFAULT_KEY_ID))
    parser.add_argument("--private-key", type=Path,
                        default=Path(os.getenv("UA_CLOUDKIT_PRIVATE_KEY", str(KEY))))
    parser.add_argument("--whisper", type=Path, default=WHISPER)
    parser.add_argument("--model", type=Path, default=MODEL)
    parser.add_argument("--codex", type=Path, default=CODEX)
    return parser.parse_args()


def main() -> int:
    args = arguments()
    args.root.mkdir(parents=True, exist_ok=True)
    lock = (args.root / "watcher.lock").open("w")
    try:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError:
        return 0
    client = CloudKit(args.key_id, args.private_key)
    state_path = args.root / "state.json"
    while True:
        try:
            run_once(client, args, state_path)
        except Exception as error:
            state = load_state(state_path)
            state["lastError"] = {
                "timestamp": now_iso(), "category": type(error).__name__,
                "message": str(error)[:1000],
            }
            atomic_json(state_path, state)
        if args.once:
            return 0
        time.sleep(max(0.5, args.poll_seconds))


if __name__ == "__main__":
    sys.exit(main())
