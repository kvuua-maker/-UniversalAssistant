#!/usr/bin/env python3
"""Behavioural wiring audit.

The legacy audits only assert that a symbol/word exists somewhere in a file.
That is satisfied by dead code, so this audit asserts *reachability*:

  1. Backend: every required route is registered inside a configure() function
     that is transitively reachable from ServerMain, and every required service
     module is constructed by one of those reachable functions.
  2. iOS: every user-facing data surface is actually populated (a property that
     only ever holds its empty default is a dead screen).
  3. Localization: every key the UI asks for exists in all five languages and
     the language picker exposes all five.

Exit code is non-zero with an explicit list of failures.
"""
from __future__ import annotations

import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BACKEND = ROOT / "Backend/Sources/UniversalAssistantServer"
IOS = ROOT / "UniversalAssistant"

failures: list[str] = []
checks = 0


def check(condition: bool, message: str) -> None:
    global checks
    checks += 1
    if not condition:
        failures.append(message)


# ---------------------------------------------------------------- backend ----
def mask_strings(source: str) -> str:
    """Blank out string/comment contents while preserving length and offsets."""
    out, i, n = [], 0, len(source)
    while i < n:
        ch = source[i]
        if ch == '"':
            out.append('"')
            i += 1
            while i < n and source[i] != '"':
                if source[i] == "\\":
                    out.append(" ")
                    i += 1
                    if i < n:
                        out.append(" ")
                        i += 1
                    continue
                out.append(" ")
                i += 1
            if i < n:
                out.append('"')
                i += 1
            continue
        if ch == "/" and i + 1 < n and source[i + 1] == "/":
            while i < n and source[i] != "\n":
                out.append(" ")
                i += 1
            continue
        out.append(ch)
        i += 1
    return "".join(out)


def function_body(source: str, name: str) -> str | None:
    """Return the brace-balanced body of `func <name>(` from the original text."""
    masked = mask_strings(source)
    match = re.search(r"func\s+" + re.escape(name) + r"\s*\(", masked)
    if not match:
        return None
    start = masked.find("{", match.end())
    if start < 0:
        return None
    depth = 0
    for i in range(start, len(masked)):
        if masked[i] == "{":
            depth += 1
        elif masked[i] == "}":
            depth -= 1
            if depth == 0:
                return source[start : i + 1]
    return None


def backend_configure_graph() -> tuple[set[str], str]:
    """Configure functions reachable from ServerMain, plus their combined body."""
    definitions: dict[str, str] = {}
    for path in BACKEND.rglob("*.swift"):
        text = path.read_text(errors="ignore")
        for name in re.findall(r"func\s+(configure\w+)\s*\(", text):
            body = function_body(text, name)
            if body:
                definitions[name] = body

    main = (BACKEND / "ServerMain.swift").read_text(errors="ignore")
    roots = set(re.findall(r"\.(configure\w+)\s*\(", main))
    check(bool(roots), "ServerMain registers no configure* entry point at all")

    reachable: set[str] = set()
    queue = list(roots)
    while queue:
        name = queue.pop()
        if name in reachable or name not in definitions:
            continue
        reachable.add(name)
        queue.extend(re.findall(r"\.(configure\w+)\s*\(", definitions[name]))
    combined = "\n".join(definitions[n] for n in sorted(reachable))
    return reachable, combined


REQUIRED_ROUTES = {
    "POST v1/jobs/search": r'post\(\s*"v1"\s*,\s*"jobs"\s*,\s*"search"',
    "GET v1/jobs/vacancies/:id": r'get\(\s*"v1"\s*,\s*"jobs"\s*,\s*"vacancies"\s*,',
    "GET v1/jobs/health": r'get\(\s*"v1"\s*,\s*"jobs"\s*,\s*"health"',
    "POST v1/app-attest/challenge": r'post\(\s*"v1"\s*,\s*"app-attest"\s*,\s*"challenge"',
    "POST v1/diagnostics": r'post\(\s*"v1"\s*,\s*"diagnostics"',
    "GET health": r'get\(\s*"health"',
}

REQUIRED_MODULES = {
    "JobsMarketplaceService": "Jobs marketplace actor",
    "JobsEntitlementLedger": "jobs entitlement ledger",
    "DiagnosticSessionStore": "diagnostics store",
    "AppAttestRegistrationStore": "app attest registry",
}


def audit_backend() -> None:
    reachable, combined = backend_configure_graph()
    if not reachable:
        failures.append("no configure* function is reachable from ServerMain")
        return
    for label, pattern in REQUIRED_ROUTES.items():
        check(
            re.search(pattern, combined) is not None,
            f"route not registered by a reachable configure function: {label}",
        )
    for symbol, label in REQUIRED_MODULES.items():
        check(
            re.search(r"\b" + re.escape(symbol) + r"\b", combined) is not None,
            f"module never constructed by a reachable configure function: {symbol} ({label})",
        )


# -------------------------------------------------------------------- iOS ----
POPULATED_SURFACES = {
    "My Tasks tab": ("UniversalAssistant/Core/AssistantViewModel.swift", "personalTasks"),
    "Favorites tab": ("UniversalAssistant/Core/AssistantViewModel.swift", "favorites"),
}


def audit_ios_surfaces() -> None:
    for label, (rel, prop) in POPULATED_SURFACES.items():
        path = ROOT / rel
        text = path.read_text(errors="ignore")
        declaration = re.search(r"var\s+" + re.escape(prop) + r"\b", text)
        check(declaration is not None, f"{label}: property {prop} does not exist")
        if declaration is None:
            continue
        writes = [
            m
            for m in re.finditer(
                r"\b" + re.escape(prop) + r"\s*(?:=|\.append|\.insert|\.removeAll)", text
            )
        ]
        check(
            bool(writes),
            f"{label}: {prop} is declared but never assigned/appended - the screen is permanently empty",
        )
        # The property must also be consumed by a view, otherwise it is a
        # populated store that never reaches the user.
        consumed = any(
            re.search(r"\b" + re.escape(prop) + r"\b", p.read_text(errors="ignore"))
            for p in (IOS / "App").glob("*.swift")
        )
        check(consumed, f"{label}: {prop} is not consumed by any view under App/")


# ---------------------------------------------------------- localization ----
LANGS = ("uk", "ru", "en", "de", "fr")


def parse_strings(path: Path) -> dict[str, str]:
    entries: dict[str, str] = {}
    if not path.exists():
        return entries
    text = path.read_text(errors="ignore")
    for key, value in re.findall(
        r'"([^"\n]+)"\s*=\s*"((?:[^"\\\n]|\\.)*)"\s*;', text
    ):
        entries[key] = value
    return entries


def audit_localization() -> None:
    tables = {
        lang: parse_strings(ROOT / f"UniversalAssistant/Resources/{lang}.lproj/Localizable.strings")
        for lang in LANGS
    }
    for lang, table in tables.items():
        check(bool(table), f"{lang}.lproj/Localizable.strings is missing or empty")

    referenced: set[str] = set()
    for path in list(IOS.rglob("*.swift")):
        text = path.read_text(errors="ignore")
        referenced |= set(re.findall(r'AppText\.value\(\s*"([^"]+)"', text))
        referenced |= set(re.findall(r'Text\(\s*"([a-z0-9_]+)"\s*\)', text))
        referenced |= set(re.findall(r'Label\(\s*"([a-z0-9_]+)"', text))
    keys = {k for k in referenced if re.fullmatch(r"[a-z0-9_]+", k) and len(k) > 2}
    for lang, table in tables.items():
        missing = sorted(keys - set(table))
        check(
            not missing,
            f"{lang}: {len(missing)} referenced keys missing, e.g. {missing[:6]}",
        )


def audit_language_picker() -> None:
    settings = (IOS / "App/AssistantSettingsView.swift").read_text(errors="ignore")
    model = (IOS / "Core/LanguageAndAIConfiguration.swift").read_text(errors="ignore")
    check(
        "UILanguage" in settings,
        "Settings screen exposes no UILanguage picker - language is hardcoded",
    )
    body = re.search(r"enum\s+UILanguage[^{]*\{([^}]*)\}", model, re.S)
    declared: set[str] = set()
    if body:
        for chunk in re.findall(r"case\s+([A-Za-z0-9_,\s]+)", body.group(1)):
            declared |= {part.strip() for part in chunk.split(",") if part.strip()}
    for raw in LANGS:
        check(raw in declared, f"UILanguage is missing the '{raw}' case")


def audit_sync_transport() -> None:
    """A declared CloudKit entitlement must be reachable from the sync factory.

    Declaring iCloud in the entitlements while the app always falls back to a
    local mirror is the same class of defect as an unmounted backend module: the
    capability exists on paper only.
    """
    entitlements = ROOT / "UniversalAssistant/UniversalAssistant.entitlements"
    declared = (
        "com.apple.developer.icloud-container-identifiers" in entitlements.read_text(errors="ignore")
        if entitlements.exists()
        else False
    )
    factory = (IOS / "Persistence/PersonalHubSync.swift").read_text(errors="ignore")
    check(
        "CloudKitSyncTransport" in factory,
        "sync factory never references CloudKitSyncTransport",
    )
    if not declared:
        return
    production = (ROOT / "Config/Production.xcconfig").read_text(errors="ignore")
    info = (IOS / "Info.plist").read_text(errors="ignore")
    check(
        re.search(r"^\s*UA_USE_CLOUDKIT_SYNC\s*=\s*(YES|NO)", production, re.M) is not None,
        "CloudKit container is declared in entitlements but Production.xcconfig "
        "does not define UA_USE_CLOUDKIT_SYNC (YES or NO)",
    )
    check(
        "UAUseCloudKitSync" in info,
        "Info.plist does not expose UAUseCloudKitSync, so the runtime cannot choose CloudKit",
    )
    check(
        "UAUseCloudKitSync" in factory,
        "sync factory ignores the UAUseCloudKitSync build flag",
    )


def main() -> int:
    audit_backend()
    audit_ios_surfaces()
    audit_localization()
    audit_language_picker()
    audit_sync_transport()
    if failures:
        print(f"WIRING AUDIT FAILED: {len(failures)} of {checks} checks\n")
        for item in failures:
            print("  FAIL  " + item)
        return 1
    print(f"WIRING AUDIT OK: {checks} behavioural checks (routes reachable, surfaces populated, {len(LANGS)} languages complete)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
