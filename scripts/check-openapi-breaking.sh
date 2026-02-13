#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CURRENT_SPEC="$ROOT_DIR/contracts/openapi.json"
BASE_SPEC="/tmp/openapi-base.json"
COMPARE_SCRIPT="$ROOT_DIR/scripts/compare-openapi-breaking.py"

if [[ ! -f "$CURRENT_SPEC" ]]; then
  echo "Missing current OpenAPI spec: $CURRENT_SPEC"
  exit 1
fi

if [[ -n "${OPENAPI_BASE_SPEC:-}" ]]; then
  BASE_SPEC="$OPENAPI_BASE_SPEC"
  if [[ ! -f "$BASE_SPEC" ]]; then
    echo "Missing base OpenAPI spec: $BASE_SPEC"
    exit 1
  fi
  python3 "$COMPARE_SCRIPT" "$BASE_SPEC" "$CURRENT_SPEC"
elif git rev-parse --verify origin/main >/dev/null 2>&1; then
  if git show origin/main:contracts/openapi.json >"$BASE_SPEC" 2>/dev/null; then
    echo "Comparing OpenAPI spec against origin/main baseline"
    python3 "$COMPARE_SCRIPT" "$BASE_SPEC" "$CURRENT_SPEC"
  else
    echo "No baseline contracts/openapi.json on origin/main yet; skipping diff."
  fi
else
  echo "origin/main not available; skipping OpenAPI diff."
fi
