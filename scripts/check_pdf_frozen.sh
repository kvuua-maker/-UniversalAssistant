#!/usr/bin/env bash
# Fails if the frozen PDF module changed relative to the freeze tag.
set -euo pipefail
cd "$(dirname "$0")/.."
BASE="${1:-pdf-frozen-88}"
if ! git rev-parse "$BASE" >/dev/null 2>&1; then
  echo "freeze tag $BASE not found"; exit 0
fi
if git diff --quiet "$BASE" -- UniversalAssistant/Modules/PDFModule; then
  echo "PDF module unchanged since $BASE"
else
  echo "PDF module changed since $BASE:"; git diff --stat "$BASE" -- UniversalAssistant/Modules/PDFModule; exit 1
fi
