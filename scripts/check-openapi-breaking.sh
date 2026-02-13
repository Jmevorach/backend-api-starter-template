#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CURRENT_SPEC="$ROOT_DIR/contracts/openapi.json"
BASE_SPEC="/tmp/openapi-base.json"

if [[ ! -f "$CURRENT_SPEC" ]]; then
  echo "Missing current OpenAPI spec: $CURRENT_SPEC"
  exit 1
fi

if git rev-parse --verify origin/main >/dev/null 2>&1; then
  if git show origin/main:contracts/openapi.json >"$BASE_SPEC" 2>/dev/null; then
    echo "Comparing OpenAPI spec against origin/main baseline"
    python3 - "$BASE_SPEC" "$CURRENT_SPEC" <<'PY'
import json
import sys

base_path, current_path = sys.argv[1], sys.argv[2]

with open(base_path, "r", encoding="utf-8") as f:
    base = json.load(f)
with open(current_path, "r", encoding="utf-8") as f:
    current = json.load(f)

base_paths = base.get("paths", {})
curr_paths = current.get("paths", {})
breaking = []

# 1) Removed paths are always breaking.
for path in sorted(set(base_paths) - set(curr_paths)):
    breaking.append(f"Removed path: {path}")

# 2) Removed operations are breaking.
http_methods = {"get", "post", "put", "patch", "delete", "options", "head", "trace"}
for path in sorted(set(base_paths) & set(curr_paths)):
    b_ops = {k: v for k, v in base_paths[path].items() if k.lower() in http_methods}
    c_ops = {k: v for k, v in curr_paths[path].items() if k.lower() in http_methods}
    for method in sorted(set(b_ops) - set(c_ops)):
        breaking.append(f"Removed operation: {method.upper()} {path}")

    for method in sorted(set(b_ops) & set(c_ops)):
        b = b_ops[method]
        c = c_ops[method]

        # 3) Adding newly required params is breaking.
        def required_params(op):
            params = op.get("parameters") or []
            out = set()
            for p in params:
                if isinstance(p, dict) and p.get("required") is True:
                    out.add((p.get("in"), p.get("name")))
            return out

        new_required = required_params(c) - required_params(b)
        for p in sorted(new_required):
            breaking.append(f"Added required parameter on {method.upper()} {path}: {p[0]}:{p[1]}")

        # 4) Making request body required is breaking.
        b_req_required = bool((b.get("requestBody") or {}).get("required"))
        c_req_required = bool((c.get("requestBody") or {}).get("required"))
        if (not b_req_required) and c_req_required:
            breaking.append(f"Request body became required: {method.upper()} {path}")

        # 5) Removing success response codes is breaking.
        b_success = {
            code
            for code in (b.get("responses") or {}).keys()
            if str(code).startswith("2")
        }
        c_success = {
            code
            for code in (c.get("responses") or {}).keys()
            if str(code).startswith("2")
        }
        removed_success = b_success - c_success
        for code in sorted(removed_success):
            breaking.append(f"Removed success response {code} on {method.upper()} {path}")

if breaking:
    print("Breaking OpenAPI changes detected:")
    for item in breaking:
        print(f" - {item}")
    sys.exit(1)

print("No breaking OpenAPI changes detected.")
PY
  else
    echo "No baseline contracts/openapi.json on origin/main yet; skipping diff."
  fi
else
  echo "origin/main not available; skipping OpenAPI diff."
fi
