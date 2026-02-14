#!/usr/bin/env bash
set -euo pipefail

IMAGE_TAG="${1:-backend-api-functional:local}"
CONTAINER_NAME="backend-functional-smoke"
HOST_PORT="${HOST_PORT:-8443}"

cleanup() {
  docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true
}
trap cleanup EXIT

echo "Starting container from image: $IMAGE_TAG"
docker run -d \
  --name "$CONTAINER_NAME" \
  -p "${HOST_PORT}:443" \
  -e SECRET_KEY_BASE="functional_container_test_secret_key_base_1234567890abcdefghijklmnopqrstuvwxyz" \
  -e PHX_HOST="localhost" \
  -e DB_HOST="127.0.0.1" \
  -e DB_NAME="backend_test" \
  -e DB_USERNAME="postgres" \
  -e DB_IAM_AUTH="false" \
  -e REQUIRE_IAM_AUTH="false" \
  "$IMAGE_TAG" >/dev/null

echo "Waiting for container HTTPS endpoint to boot..."
ready=false
for _ in $(seq 1 60); do
  if curl -sk --connect-timeout 2 "https://localhost:${HOST_PORT}/" >/dev/null 2>&1; then
    ready=true
    break
  fi
  sleep 1
done

if [[ "$ready" != "true" ]]; then
  echo "Container did not become ready in time."
  docker logs "$CONTAINER_NAME" || true
  exit 1
fi

echo "Running functional smoke assertions..."

root_status="$(curl -sk -o /tmp/root.json -w "%{http_code}" "https://localhost:${HOST_PORT}/")"
if [[ "$root_status" != "200" ]]; then
  echo "Expected GET / to return 200, got ${root_status}"
  cat /tmp/root.json || true
  exit 1
fi
if ! grep -q '"service"' /tmp/root.json; then
  echo "Expected GET / response to include service metadata"
  cat /tmp/root.json || true
  exit 1
fi

health_status="$(curl -sk -o /tmp/health.json -w "%{http_code}" "https://localhost:${HOST_PORT}/healthz")"
if [[ "$health_status" != "200" && "$health_status" != "503" ]]; then
  echo "Expected GET /healthz to return 200 or 503, got ${health_status}"
  cat /tmp/health.json || true
  exit 1
fi
if ! grep -q '"status"' /tmp/health.json; then
  echo "Expected GET /healthz response to include status"
  cat /tmp/health.json || true
  exit 1
fi

openapi_status="$(curl -sk -o /tmp/openapi.json -w "%{http_code}" "https://localhost:${HOST_PORT}/api/v1/openapi")"
if [[ "$openapi_status" != "200" ]]; then
  echo "Expected GET /api/v1/openapi to return 200, got ${openapi_status}"
  cat /tmp/openapi.json || true
  exit 1
fi
if ! grep -q '"openapi"' /tmp/openapi.json; then
  echo "Expected OpenAPI response to include openapi field"
  cat /tmp/openapi.json || true
  exit 1
fi

me_status="$(curl -sk -o /tmp/me.json -w "%{http_code}" "https://localhost:${HOST_PORT}/api/v1/me")"
if [[ "$me_status" != "401" ]]; then
  echo "Expected unauthenticated GET /api/v1/me to return 401, got ${me_status}"
  cat /tmp/me.json || true
  exit 1
fi

echo "Container functional smoke checks passed."
