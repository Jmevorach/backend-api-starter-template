#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="$ROOT_DIR/app"
OUT_FILE="$ROOT_DIR/contracts/openapi.json"

echo "Exporting OpenAPI spec to $OUT_FILE"
cd "$APP_DIR"
mix deps.get
mix run -e 'File.write!(Path.expand("../contracts/openapi.json"), Jason.encode_to_iodata!(BackendWeb.ApiSpec.spec()))'

echo "OpenAPI export complete"
