# API Contract Types

This folder contains TypeScript interfaces for API client use.

## Table of Contents

- [Contract Maintenance](#contract-maintenance)

- `frontend-api.ts` mirrors documented payloads in `docs/API_CONTRACT.md`
- `tsconfig.json` enables strict type-checking for this contract artifact
- `openapi.json` is the generated API contract from the Phoenix router/spec
- `spectral.yaml` contains OpenAPI linting rules used by CI

Use these types directly in any TypeScript client application, or copy them into
your client repo as a starting point.

## Contract Maintenance

- Regenerate OpenAPI contract: `./scripts/export-openapi.sh`
- Lint OpenAPI contract: `make openapi-lint`
- Validate docs/routes/type drift: `make contract-validate`
- Type-check client interfaces: `make contract-typecheck`
