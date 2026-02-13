#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPARE_SCRIPT="$ROOT_DIR/scripts/compare-openapi-breaking.py"
FIXTURE_DIR="$ROOT_DIR/scripts/testdata/openapi"

run_case() {
  local name="$1"
  local base="$2"
  local candidate="$3"
  local expected="$4"

  echo "Running fixture: $name"
  set +e
  python3 "$COMPARE_SCRIPT" "$FIXTURE_DIR/$base" "$FIXTURE_DIR/$candidate" >/tmp/openapi-breakcheck.out 2>&1
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

run_case "non-breaking additions" "base.json" "non_breaking.json" "pass"
run_case "removed path" "base.json" "breaking_removed_path.json" "fail"
run_case "required parameter added" "base.json" "breaking_required_param.json" "fail"
run_case "enum narrowing" "base.json" "breaking_enum_narrow.json" "fail"
run_case "request body became required" "base_with_request_body.json" "breaking_request_body_required.json" "fail"
run_case "response media type removed" "base_with_media_types.json" "breaking_removed_media_type.json" "fail"

echo "OpenAPI breakcheck fixtures passed."
