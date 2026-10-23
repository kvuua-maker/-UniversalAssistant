#!/usr/bin/env bash
# Local preflight: fails fast, before any Apple-runner minute is spent.
# Order is intentional - cheapest and most mechanical checks first.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

# Toolchain: use a project-local install when present (VPS / CI cache),
# otherwise fall back to PATH so the same script works on a Mac.
TOOLS="${UA_TOOLS:-/root/projects/.tools}"
[ -d "$TOOLS/swift/usr/bin" ] && export PATH="$TOOLS/swift/usr/bin:$PATH"
[ -d "$TOOLS/bin" ] && export PATH="$TOOLS/bin:$PATH"
# SwiftLint on Linux needs libsourcekitdInProc from the matching toolchain.
SWIFT_LIB="$(cd "$(dirname "$(command -v swift)")/../lib" && pwd)"
export LINUX_SOURCEKIT_LIB_PATH="${LINUX_SOURCEKIT_LIB_PATH:-$SWIFT_LIB}"
export LD_LIBRARY_PATH="$SWIFT_LIB/swift/linux:$SWIFT_LIB${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
# Sandboxed/CI runs have a read-only HOME cache; keep every cache in-tree.
export CLANG_MODULE_CACHE_PATH="$ROOT/.build/clang-module-cache"

step() { printf '\n\033[1m▶ %s\033[0m\n' "$1"; }
fail() {
  printf '\n\033[31m✗ PREFLIGHT FAILED: %s\033[0m\n' "$1" >&2
  printf '  fix the problem above, then re-run scripts/preflight.sh\n' >&2
  exit 1
}
need() { command -v "$1" >/dev/null 2>&1 || fail "$2 ($1 not installed)"; }

step "0/4 tool availability"
need swiftformat "install SwiftFormat"
need swiftlint "install SwiftLint"
need swift "install the Swift toolchain"
need python3 "install python3"
echo "  swiftformat $(swiftformat --version), swiftlint $(swiftlint version), $(swift --version 2>&1 | head -1)"

step "1/4 swiftformat --lint"
swiftformat --lint . \
  --swift-version 6 \
  --rules trailingSpace,linebreakAtEndOfFile \
  --exclude .build,Backend/.build,.tools,DerivedData \
  || fail "swiftformat (formatting rules)"

step "2/4 swiftlint lint --strict"
swiftlint lint --strict --quiet --no-cache --config .swiftlint.yml || fail "swiftlint (style / probable bugs)"

step "3/4 swift build"
swift build --package-path Backend --scratch-path .build/backend --cache-path .build/swiftpm-cache || fail "swift build (backend package)"

# Backend tests are deliberately NOT part of the Linux gate: they are
# platform-dependent and run on the macOS runner, after this gate has already
# rejected formatting/syntax failures. Pass --tests to run them locally on a
# machine where they are known to work (macOS).
if [ "${1:-}" = "--tests" ]; then
  step "3.5/4 swift test (macOS only)"
  swift test --package-path Backend --scratch-path .build/backend --cache-path .build/swiftpm-cache || fail "swift test (backend package)"
fi

step "4/4 wiring audit"
python3 Scripts/audit_wiring.py || fail "audit_wiring.py (unreachable code / empty screens / missing translations)"

printf '\n\033[32m✓ PREFLIGHT PASSED\033[0m - safe to push\n'
exit 0
