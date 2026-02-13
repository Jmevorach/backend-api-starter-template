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

def resolve_ref(schema, doc, seen=None):
    if not isinstance(schema, dict):
        return schema
    ref = schema.get("$ref")
    if not ref or not isinstance(ref, str) or not ref.startswith("#/"):
        return schema
    seen = seen or set()
    if ref in seen:
        return schema
    seen.add(ref)
    node = doc
    for token in ref[2:].split("/"):
        if not isinstance(node, dict) or token not in node:
            return schema
        node = node[token]
    return resolve_ref(node, doc, seen)

def schema_breaks(base_schema, curr_schema, base_doc, curr_doc, ctx):
    out = []
    b = resolve_ref(base_schema or {}, base_doc)
    c = resolve_ref(curr_schema or {}, curr_doc)

    if not isinstance(b, dict) or not isinstance(c, dict):
        return out

    b_type = b.get("type")
    c_type = c.get("type")
    if b_type and c_type and b_type != c_type:
        out.append(f"{ctx}: schema type changed from {b_type} to {c_type}")
        return out

    # Enum narrowing is breaking.
    b_enum = b.get("enum")
    c_enum = c.get("enum")
    if isinstance(b_enum, list) and isinstance(c_enum, list):
        removed = sorted(set(b_enum) - set(c_enum))
        if removed:
            out.append(f"{ctx}: enum values removed: {removed}")

    # Object compatibility.
    if (b_type == "object") or ("properties" in b):
        b_required = set(b.get("required") or [])
        c_required = set(c.get("required") or [])
        removed_required = sorted(b_required - c_required)
        if removed_required:
            out.append(f"{ctx}: required fields removed: {removed_required}")

        b_props = b.get("properties") or {}
        c_props = c.get("properties") or {}

        removed_props = sorted(set(b_props) - set(c_props))
        if removed_props:
            out.append(f"{ctx}: response properties removed: {removed_props}")

        for prop in sorted(set(b_props) & set(c_props)):
            out.extend(
                schema_breaks(
                    b_props[prop],
                    c_props[prop],
                    base_doc,
                    curr_doc,
                    f"{ctx}.{prop}",
                )
            )

    # Array compatibility.
    if b_type == "array" and c_type == "array":
        out.extend(
            schema_breaks(
                b.get("items") or {},
                c.get("items") or {},
                base_doc,
                curr_doc,
                f"{ctx}[]",
            )
        )

    return out

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

        # 6) Deep response schema compatibility checks for shared 2xx responses.
        for code in sorted(b_success & c_success):
            b_resp = (b.get("responses") or {}).get(code) or {}
            c_resp = (c.get("responses") or {}).get(code) or {}
            b_content = b_resp.get("content") or {}
            c_content = c_resp.get("content") or {}

            removed_media = sorted(set(b_content) - set(c_content))
            for mt in removed_media:
                breaking.append(
                    f"Removed response media type {mt} for {method.upper()} {path} {code}"
                )

            for mt in sorted(set(b_content) & set(c_content)):
                b_schema = (b_content.get(mt) or {}).get("schema") or {}
                c_schema = (c_content.get(mt) or {}).get("schema") or {}
                breaking.extend(
                    schema_breaks(
                        b_schema,
                        c_schema,
                        base,
                        current,
                        f"{method.upper()} {path} {code} [{mt}]",
                    )
                )

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
