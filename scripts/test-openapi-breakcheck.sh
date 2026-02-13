#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPARE_SCRIPT="$ROOT_DIR/scripts/compare-openapi-breaking.py"
FIXTURE_DIR="$ROOT_DIR/scripts/testdata/openapi"

run_case() {
  local name="$1"
  local candidate="$2"
  local expected="$3"

  echo "Running fixture: $name"
  set +e
  python3 "$COMPARE_SCRIPT" "$FIXTURE_DIR/base.json" "$FIXTURE_DIR/$candidate" >/tmp/openapi-breakcheck.out 2>&1
  local code=$?
  set -e

  if [[ "$expected" == "pass" && $code -ne 0 ]]; then
    echo "Expected pass but failed: $name"
    cat /tmp/openapi-breakcheck.out
    exit 1
  fi

  if [[ "$expected" == "fail" && $code -eq 0 ]]; then
    echo "Expected failure but passed: $name"
    cat /tmp/openapi-breakcheck.out
    exit 1
  fi

  cat /tmp/openapi-breakcheck.out
}

run_case "non-breaking additions" "non_breaking.json" "pass"
run_case "removed path" "breaking_removed_path.json" "fail"
run_case "required parameter added" "breaking_required_param.json" "fail"
run_case "enum narrowing" "breaking_enum_narrow.json" "fail"

echo "OpenAPI breakcheck fixtures passed."
