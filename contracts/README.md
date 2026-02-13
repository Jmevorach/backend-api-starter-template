# Frontend Contract Types

This folder contains TypeScript interfaces for frontend consumption.

- `frontend-api.ts` mirrors documented payloads in `docs/API_CONTRACT.md`
- `tsconfig.json` enables strict type-checking for this contract artifact
- `openapi.json` is the generated API contract from the Phoenix router/spec
- `spectral.yaml` contains OpenAPI linting rules used by CI

Use these types directly in your React app, or copy them into your frontend
repo as a starting point.
