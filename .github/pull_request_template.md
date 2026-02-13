# Pull Request Template

## Table of Contents

- [What Changed](#what-changed)
- [Why](#why)
- [API Impact](#api-impact)
- [Validation](#validation)
- [Security and Ops](#security-and-ops)

## What Changed

- 

## Why

- 

## API Impact

- [ ] No contract changes
- [ ] Contract updated (`docs/API_CONTRACT.md`, `contracts/frontend-api.ts`)
- [ ] OpenAPI updated (`contracts/openapi.json`)

## Validation

- [ ] `make verify`
- [ ] `make contract-validate`
- [ ] `make contract-typecheck`
- [ ] `cd app && mix test`

## Security and Ops

- [ ] No secrets committed
- [ ] Logging/tracing reviewed for sensitive fields
- [ ] Infra/docs updated if runtime behavior changed
