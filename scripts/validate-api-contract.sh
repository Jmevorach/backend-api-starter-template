#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DOC_FILE="$ROOT_DIR/docs/API_CONTRACT.md"
ROUTER_FILE="$ROOT_DIR/app/lib/backend_web/router.ex"
TS_FILE="$ROOT_DIR/contracts/frontend-api.ts"

if command -v rg >/dev/null 2>&1; then
  SEARCH_CMD=(rg -Fq)
else
  SEARCH_CMD=(grep -Fq)
fi

echo "Validating API contract documentation..."

required_endpoints=(
  "GET /api/me"
  "GET /api/patient/profile"
  "GET /api/patient/dashboard"
  "GET /api/notes"
  "POST /api/notes"
  "PUT /api/notes/:id"
  "DELETE /api/notes/:id"
  "POST /api/notes/:id/archive"
  "POST /api/notes/:id/unarchive"
  "POST /api/uploads/presign"
  "GET /api/uploads"
  "GET /api/uploads/:key/download"
  "DELETE /api/uploads/:key"
)

for endpoint in "${required_endpoints[@]}"; do
  if ! "${SEARCH_CMD[@]}" "$endpoint" "$DOC_FILE"; then
    echo "Missing endpoint in API contract doc: $endpoint"
    exit 1
  fi
done

echo "Checking endpoint coverage in router..."

router_markers=(
  "/me"
  "/patient/profile"
  "/patient/dashboard"
  "/notes"
  "/uploads"
)

for marker in "${router_markers[@]}"; do
  if ! "${SEARCH_CMD[@]}" "$marker" "$ROUTER_FILE"; then
    echo "Missing route marker in router: $marker"
    exit 1
  fi
done

echo "Checking TypeScript contract exports..."

required_types=(
  "export interface ApiError"
  "export interface MeResponse"
  "export interface PatientProfileResponse"
  "export interface PatientDashboardResponse"
  "export interface NotesListResponse"
  "export interface UploadPresignResponse"
)

for type_decl in "${required_types[@]}"; do
  if ! "${SEARCH_CMD[@]}" "$type_decl" "$TS_FILE"; then
    echo "Missing type declaration in TypeScript contract: $type_decl"
    exit 1
  fi
done

echo "API contract validation passed."
