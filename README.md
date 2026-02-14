# Mobile Backend Baseline – Production AWS + Phoenix

[![Elixir CI](https://github.com/Jmevorach/backend-api-starter-template/actions/workflows/elixir-ci.yml/badge.svg)](https://github.com/Jmevorach/backend-api-starter-template/actions/workflows/elixir-ci.yml)
[![Terraform CI](https://github.com/Jmevorach/backend-api-starter-template/actions/workflows/terraform-ci.yml/badge.svg)](https://github.com/Jmevorach/backend-api-starter-template/actions/workflows/terraform-ci.yml)
[![Python CI](https://github.com/Jmevorach/backend-api-starter-template/actions/workflows/python-lambda-ci.yml/badge.svg)](https://github.com/Jmevorach/backend-api-starter-template/actions/workflows/python-lambda-ci.yml)
[![ShellCheck](https://github.com/Jmevorach/backend-api-starter-template/actions/workflows/shellcheck.yml/badge.svg)](https://github.com/Jmevorach/backend-api-starter-template/actions/workflows/shellcheck.yml)
[![Frontend Contract CI](https://github.com/Jmevorach/backend-api-starter-template/actions/workflows/frontend-contract-ci.yml/badge.svg)](https://github.com/Jmevorach/backend-api-starter-template/actions/workflows/frontend-contract-ci.yml)
[![API Governance CI](https://github.com/Jmevorach/backend-api-starter-template/actions/workflows/api-governance-ci.yml/badge.svg)](https://github.com/Jmevorach/backend-api-starter-template/actions/workflows/api-governance-ci.yml)
[![Security Scans](https://github.com/Jmevorach/backend-api-starter-template/actions/workflows/security-scans.yml/badge.svg)](https://github.com/Jmevorach/backend-api-starter-template/actions/workflows/security-scans.yml)
[![Version Check](https://github.com/Jmevorach/backend-api-starter-template/actions/workflows/version-check.yml/badge.svg)](https://github.com/Jmevorach/backend-api-starter-template/actions/workflows/version-check.yml)
[![Container Functional CI](https://github.com/Jmevorach/backend-api-starter-template/actions/workflows/container-functional-ci.yml/badge.svg)](https://github.com/Jmevorach/backend-api-starter-template/actions/workflows/container-functional-ci.yml)
[![Container Benchmark](https://github.com/Jmevorach/backend-api-starter-template/actions/workflows/container-benchmark.yml/badge.svg)](https://github.com/Jmevorach/backend-api-starter-template/actions/workflows/container-benchmark.yml)
[![Latest Container p95](https://img.shields.io/endpoint?url=https://jmevorach.github.io/backend-api-starter-template/benchmarks/latest-shields.json)](https://jmevorach.github.io/backend-api-starter-template/benchmarks/latest.html)

[![Elixir](https://img.shields.io/badge/Elixir-1.19.5+-4B275F?logo=elixir)](https://elixir-lang.org/)
[![Phoenix](https://img.shields.io/badge/Phoenix-1.7+-FD4F00?logo=phoenix-framework)](https://www.phoenixframework.org/)
[![Terraform](https://img.shields.io/badge/Terraform-1.14+-7B42BC?logo=terraform)](https://www.terraform.io/)
[![Python](https://img.shields.io/badge/Python-3.14+-3776AB?logo=python)](https://www.python.org/)
[![AWS](https://img.shields.io/badge/AWS-ECS%20%7C%20Aurora%20%7C%20ElastiCache-FF9900?logo=amazon-aws)](https://aws.amazon.com/)
[![License](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

This repository is an **open-source production baseline** for mobile app
backends. It pairs a **Phoenix JSON API** with **battle-tested AWS
infrastructure** so teams can ship faster without rebuilding core platform
foundations.

## Table of Contents

- [Why This Exists](#why-this-exists)
- [What You Get](#what-you-get)
- [Architecture (High Level)](#architecture-high-level)
- [Repository Layout](#repository-layout)
- [Quick Start](#quick-start)
- [Frontend Quickstart (React)](#frontend-quickstart-react)
- [Documentation](#documentation)
- [Local Tooling](#local-tooling)
- [Customize It](#customize-it)

## Why This Exists

Most teams repeatedly implement the same building blocks:

- A secure, scalable API service
- Database, cache, and network plumbing
- Logging, backups, and secret rotation
- Deployment discipline

This repo bundles those pieces into a cohesive, production-ready starting point
while staying generic enough to fit almost any backend product.

## What You Get

- **Phoenix API service** with Ecto, health checks, and optional OAuth
- **Valkey/Redis-backed sessions** for multi-container deployments
- **Aurora Serverless v2 + RDS Proxy** for PostgreSQL
- **ECS Fargate (Graviton)** behind **ALB** and **Global Accelerator**
- **Automatic TLS** for database and cache connections in production
- **IAM authentication** for RDS and ElastiCache (with password fallback option)
- **Secrets Manager + KMS** with automated rotation (Lambdas in `infra/lambdas`)
- **Centralized logging & auditing** (CloudWatch, CloudTrail, VPC Flow Logs)
- **AWS Backup** with long-term retention policies
- **Pre-built CloudWatch dashboards** for monitoring
- **Cost monitoring** with AWS Budgets and Anomaly Detection
- **OpenAPI/Swagger documentation** at `/api/docs`
- **Optional API clients** for Stripe, Checkr, and Google Maps integrations
- **Authenticated profile/dashboard endpoints** (`/api/profile`, `/api/dashboard`)
- **Versioned API namespace** (`/api/v1/*`) with compatibility routes at `/api/*`
- **Golden path domain module** with `projects` and `tasks` APIs

## Architecture (High Level)

```
Clients
  |
  v
Global Accelerator
  |
  v
ALB (HTTPS)
  |
  v
ECS Fargate (Phoenix API)
  |                 |
  |                 +--> Valkey/Redis (sessions)
  |
  +--> RDS Proxy --> Aurora Serverless v2 (PostgreSQL)
```

## Repository Layout

- `app/` – Phoenix API service (JSON-only)
- `infra/` – Terraform infrastructure for AWS
- `infra/lambdas/` – Python rotation Lambdas (separate files)
- `state-backend/` – Terraform for S3 + DynamoDB remote state
- `compose.yaml` – Local Postgres + Valkey for development
- `scripts/` – Local helper scripts (deploy/dev)
- `loadtests/` – k6 load testing scripts
- `Makefile` – Common local commands
- `ENVIRONMENT.md` – Centralized environment variable reference
- `docs/` – Deep-dive documentation for architecture, operations, security

## Quick Start

1. **Configure AWS credentials and environment**
   ```bash
   aws configure  # or set AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY
   export TF_VAR_github_owner="your-github-username"
   export TF_VAR_github_repo="backend-api-starter-template"

   # Option A: Auto-create HTTPS certificate (recommended)
   export TF_VAR_domain_name="api.example.com"
   export TF_VAR_route53_zone_name="example.com"

   # Option B: Use existing ACM certificate
   # export TF_VAR_alb_acm_certificate_arn="arn:aws:acm:..."
   ```

2. **Deploy everything with one command**
   ```bash
   ./scripts/deploy.sh --init-state
   ```
   This will:
   - Bootstrap the Terraform state backend (S3 + DynamoDB)
   - Build and push the container image to ECR
   - Create and validate ACM certificate (if using auto-creation)
   - Deploy all infrastructure via Terraform
   - Wait for the service to stabilize

3. **Verify the deployment**
   ```bash
   ./scripts/deployment-health-report.sh
   ```

4. **Tear down when done**
   ```bash
   ./scripts/destroy.sh
   ```

See [`docs/LOCAL_DEPLOY.md`](docs/LOCAL_DEPLOY.md) for detailed deployment instructions.

## Frontend Quickstart (React)

If your team is starting with the frontend first, use this path:

1. Run backend locally with `docs/LOCAL_DEV.md`
2. Review auth/session and API bootstrap flow in `docs/FRONTEND_INTEGRATION.md`
3. Start frontend bootstrap calls with:
   - `GET /api/v1/me`
   - `GET /api/v1/profile`
   - `GET /api/v1/dashboard`

The `/api/*` equivalents remain available for compatibility.

## Documentation

- [`ENVIRONMENT.md`](ENVIRONMENT.md) – **Single source** for all variables and secrets
- [`CONTRIBUTING.md`](CONTRIBUTING.md) – How to add API modules and modify infrastructure
- [`docs/API_INTEGRATIONS.md`](docs/API_INTEGRATIONS.md) – How to add your own integrations safely
- [`docs/AUTHENTICATION.md`](docs/AUTHENTICATION.md) – Database/Valkey auth, TLS, IAM setup
- [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) – Service layout and data flows
- [`docs/OPERATIONS.md`](docs/OPERATIONS.md) – Deployments, scaling, and day-2 operations
- [`docs/CUSTOMIZATION.md`](docs/CUSTOMIZATION.md) – How to tailor this repo to your app
- [`docs/SECURITY.md`](docs/SECURITY.md) – Security model and best practices
- [`docs/TROUBLESHOOTING.md`](docs/TROUBLESHOOTING.md) – Common issues and fixes
- [`docs/LOCAL_DEPLOY.md`](docs/LOCAL_DEPLOY.md) – Deploy from a laptop without GitHub Actions
- [`docs/LOCAL_DEV.md`](docs/LOCAL_DEV.md) – Local dev workflow with Postgres + Valkey
- [`docs/FRONTEND_INTEGRATION.md`](docs/FRONTEND_INTEGRATION.md) – React/frontend integration patterns
- [`docs/API_CONTRACT.md`](docs/API_CONTRACT.md) – Request/response examples for frontend endpoints
- [`contracts/frontend-api.ts`](contracts/frontend-api.ts) – TypeScript interfaces matching the API contract
- [`contracts/openapi.json`](contracts/openapi.json) – Generated OpenAPI contract used for governance checks
- [`docs/APP_BACKEND_BLUEPRINT.md`](docs/APP_BACKEND_BLUEPRINT.md) – Suggested app-domain extensions
- [`docs/SECURITY_CHECKLIST.md`](docs/SECURITY_CHECKLIST.md) – Pre-deployment security checklist
- [`docs/OBSERVABILITY.md`](docs/OBSERVABILITY.md) – Runtime visibility and request correlation
- [`docs/SUPPORT_MATRIX.md`](docs/SUPPORT_MATRIX.md) – Supported versions and CI baselines
- [`docs/README.md`](docs/README.md) – Documentation index and navigation
- [`CHANGELOG.md`](CHANGELOG.md) – Release notes and breaking-change history

## Local Tooling

This repo provides scripts and commands for local development and deployment:

**Development:**
- `make dev-up` – Start local Postgres + Valkey
- `make dev-down` – Stop local services
- `make dev-reset` – Reset local database

**Quality Checks:**
- `make app-format` – Check Elixir formatting
- `make app-credo` – Run Credo linter
- `make app-test` – Run tests
- `cd app && mix test --cover` – Run tests with coverage output
- `make terraform-security` – Run security scans (Checkov, KICS)
- `make contract-validate` – Validate API contract docs against routes/type exports
- `make contract-typecheck` – Type-check frontend contract interfaces
- `make openapi-lint` – Export + lint OpenAPI contract
- `make openapi-breakcheck-test` – Validate OpenAPI break-check fixture harness
- `make verify` – Run default quality gate before opening PRs

**Deployment:**
- `make deploy` – Full deployment (build + push + terraform)
- `make deploy-plan` – Preview changes without applying
- `make health-report` – Check deployment health status
- `make destroy` – Tear down infrastructure

**Script Options:**
```bash
./scripts/deploy.sh --help              # See all deploy options
./scripts/deploy.sh --skip-build        # Redeploy without rebuilding image
./scripts/deploy.sh --plan-only         # Preview Terraform changes
./scripts/deployment-health-report.sh --json  # JSON output for automation
./scripts/destroy.sh --include-ecr      # Also delete ECR images
```

**Pre-commit Hooks:**
```bash
pip install pre-commit
pre-commit install
```

Hooks run automatically on commit (Terraform fmt, Python linting, shellcheck, etc.).

## Customize It

**Getting Started:**
1. Add your API routes in `app/lib/backend_web/controllers`
2. Wire them up in `app/lib/backend_web/router.ex`
3. Model your app-domain entities (profiles, projects/tasks, appointments, messaging)
4. Deploy to production

**Using Existing Authenticated Endpoints:**
```bash
curl -i http://localhost:4000/api/profile
curl -i http://localhost:4000/api/dashboard
```

**Extending the Project:**
- Add new API client modules – see [`CONTRIBUTING.md`](CONTRIBUTING.md)
- Modify AWS infrastructure – see [`CONTRIBUTING.md`](CONTRIBUTING.md#modifying-aws-infrastructure)
- Customize authentication, sessions, scaling – see [`docs/CUSTOMIZATION.md`](docs/CUSTOMIZATION.md)

If you are new to infrastructure or Phoenix, start with
[`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) and
[`docs/OPERATIONS.md`](docs/OPERATIONS.md).
