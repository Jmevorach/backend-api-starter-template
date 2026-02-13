# Observability

This backend ships with practical observability defaults for API operations.

## Request Tracing and Correlation

- Every request gets an `x-request-id` via `Plug.RequestId`.
- API error responses include `request_id` for client-to-server correlation.
- Request logging attaches method, path, status, latency, and user identity metadata.

## Rate and Edge Signals

- API responses include:
  - `x-ratelimit-limit`
  - `x-ratelimit-remaining`
  - `x-ratelimit-reset`
- 429 responses use the same structured error envelope as other failures.

## Health Monitoring

- `GET /healthz` returns service readiness.
- `GET /healthz?detailed=true` includes component-level details (when available).

## OpenAPI and Contract Governance

- `contracts/openapi.json` is the canonical machine-readable API shape.
- CI enforces:
  - Spectral linting
  - Breaking-change checks in pull requests
  - API docs/type drift checks

## Recommended Runtime Integrations

For production, forward logs and metrics into your preferred observability stack:

- CloudWatch Logs / OpenSearch
- Datadog / New Relic
- OpenTelemetry collector (optional extension)
