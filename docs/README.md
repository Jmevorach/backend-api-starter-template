# Documentation Index

Use this index to find the right guide quickly.

## Table of Contents

- [Start Here](#start-here)
- [Deployment and Operations](#deployment-and-operations)
- [Architecture and Security](#architecture-and-security)
- [Extensibility](#extensibility)
- [Documentation Quality](#documentation-quality)
- [Suggested Reading Paths](#suggested-reading-paths)

## Start Here

- `LOCAL_DEV.md` - Run the API locally for day-to-day development
- `FRONTEND_INTEGRATION.md` - React/frontend integration and bootstrap flows
- `API_CONTRACT.md` - Request/response examples for core client-facing endpoints
- `../contracts/frontend-api.ts` - TypeScript interfaces mirroring API payloads
- `APP_BACKEND_BLUEPRINT.md` - Suggested app-domain roadmap

## Deployment and Operations

- `LOCAL_DEPLOY.md` - Deploy from a local machine
- `OPERATIONS.md` - Day-2 operations, scaling, backups, rotation
- `GLOBAL_AVAILABILITY.md` - Multi-region patterns and failover strategies
- `OBSERVABILITY.md` - Logging, request correlation, and API governance signals
- `TROUBLESHOOTING.md` - Common issues and fixes
- `SUPPORT_MATRIX.md` - Supported versions and compatibility policy

## Architecture and Security

- `ARCHITECTURE.md` - System components and request/data flow
- `AUTHENTICATION.md` - DB/Valkey IAM and auth modes
- `SECURITY.md` - Security posture and hardening suggestions
- `SECURITY_CHECKLIST.md` - Pre-deployment security checks

## Extensibility

- `CUSTOMIZATION.md` - How to adapt the baseline to your product
- `API_INTEGRATIONS.md` - Safe pattern for adding third-party integrations

## Documentation Quality

Before merging documentation changes, run:

- `make contract-validate`
- `make contract-typecheck`
- `make openapi-lint`

## Suggested Reading Paths

- **New platform owner:** `ARCHITECTURE.md` -> `GLOBAL_AVAILABILITY.md` ->
  `OPERATIONS.md`
- **API contributor:** `API_CONTRACT.md` -> `CONTRIBUTING.md` ->
  `CUSTOMIZATION.md`
- **Security reviewer:** `SECURITY.md` -> `SECURITY_CHECKLIST.md` ->
  `AUTHENTICATION.md`
