# Support Matrix

## Table of Contents

- [API Version Support](#api-version-support)
- [CI Baselines](#ci-baselines)

| Component | Supported | Notes |
|---|---|---|
| Elixir | 1.19.x | CI pinned to 1.19.5 |
| Erlang/OTP | 28.x | CI pinned to OTP 28 |
| Phoenix | 1.7.x | JSON API mode |
| PostgreSQL | 17.x | Local + CI service image |
| Valkey/Redis | 7.x | Session + cache use cases |
| Node.js | 22.x | Contract/type/lint jobs |
| Terraform | 1.14.x | Infra and state-backend |
| Python | 3.14.x | Infra lambdas + tooling |

## API Version Support

- `v1` - active and recommended (`/api/v1/*`)
- `legacy` - compatibility paths under `/api/*` that mirror `v1`

## CI Baselines

- `Elixir CI` enforces format/compile/credo/tests.
- `Frontend Contract CI` enforces docs/types consistency.
- `API Governance CI` enforces OpenAPI lint + PR diff checks.
- `Security Scans` runs Semgrep + CodeQL.
- `Container Functional CI` validates shipped container behavior via smoke tests.
