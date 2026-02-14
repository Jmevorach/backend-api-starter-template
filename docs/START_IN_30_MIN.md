# Start In 30 Minutes

Use this opinionated path if you want a fast first success: run locally, validate
core endpoints, and understand the production deployment flow.

## Table of Contents

- [Outcomes](#outcomes)
- [Prerequisites](#prerequisites)
- [0-10 Minutes: Local Runtime](#0-10-minutes-local-runtime)
- [10-20 Minutes: API Validation](#10-20-minutes-api-validation)
- [20-30 Minutes: Production Path](#20-30-minutes-production-path)
- [After 30 Minutes](#after-30-minutes)

## Outcomes

In 30 minutes, you should have:

- Local API running with health checks.
- Confidence in versioned endpoints (`/api/v1`).
- A clear path for first production deployment.

This guide is continuously validated by
`.github/workflows/start-in-30-min-ci.yml`.

## Prerequisites

- Docker
- Elixir/Erlang toolchain (or use existing project setup)
- AWS CLI configured (for deployment path)

## 0-10 Minutes: Local Runtime

```bash
make dev-up
cd app
mix deps.get
mix ecto.setup
mix phx.server
```

In another terminal:

```bash
curl -i http://localhost:4000/healthz
curl -i http://localhost:4000/
curl -i http://localhost:4000/api/v1/openapi
```

Expected:

- `GET /healthz` returns `200` (or `503` when a dependency is intentionally down)
- `GET /` returns service metadata
- `GET /api/v1/openapi` returns API contract JSON

## 10-20 Minutes: API Validation

Run quality and contract checks:

```bash
make app-test
make contract-validate
make openapi-lint
```

Verify authenticated bootstrap behavior (unauthenticated):

```bash
curl -i http://localhost:4000/api/v1/me
```

Expected:

- `401 Unauthorized` for unauthenticated `GET /api/v1/me`

## 20-30 Minutes: Production Path

Set deployment variables:

```bash
export TF_VAR_github_owner="your-github-username"
export TF_VAR_github_repo="backend-api-starter-template"
export TF_VAR_domain_name="api.example.com"
export TF_VAR_route53_zone_name="example.com"
```

Preview infrastructure changes:

```bash
./scripts/deploy.sh --plan-only --init-state
```

Deploy when ready:

```bash
./scripts/deploy.sh --init-state
```

Validate deployment:

```bash
./scripts/deployment-health-report.sh
```

Note: in CI, production deployment and health validation are smoke-tested at the
script interface level (`--help`) because real execution requires AWS credentials
and live deployed infrastructure.

## After 30 Minutes

- Add your first domain module via `docs/CUSTOMIZATION.md`.
- Keep contracts stable with `docs/API_CONTRACT.md` and `contracts/frontend-api.ts`.
- Define global rollout strategy with `docs/GLOBAL_AVAILABILITY.md`.
- Capture architecture decisions with `docs/adr/README.md`.
