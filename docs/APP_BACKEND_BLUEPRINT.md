# App Backend Blueprint

This document outlines practical next steps for evolving this repository into a
production-grade backend for an open-source React mobile application.

## Current Baseline

Already included:

- OAuth login (Google and Apple) + server-side sessions
- Protected APIs and route guard plug
- Profile/dashboard endpoints:
  - `GET /api/profile`
  - `GET /api/dashboard`
- Notes CRUD (`/api/notes` and `/api/v1/notes`)
- Example project/task domain (`/api/v1/projects`, `/api/v1/tasks`)
- S3 uploads with presigned URLs
- Production AWS deployment stack (ECS, ALB, Aurora, Valkey, IAM auth)

## Suggested Extension Approach

Add only the domain modules your product actually needs.
Keep each module in its own context + schema + controller tests.

## Security Direction

- Minimize sensitive data in logs and traces.
- Add audit event tables for critical reads/writes.
- Encrypt sensitive columns where needed.
- Apply role-based authorization (user, manager, admin).
- Add retention/deletion workflows for user data exports and account deletion.

## Integration Suggestions

If your roadmap includes external system interoperability:

- Keep internal models decoupled from provider payloads.
- Validate and version integration contracts with tests.
- Add adapter modules for each external provider.

## Frontend Integration Tips

- Use `/api/profile` and `/api/dashboard` for initial app bootstrap.
- Keep session refresh simple: call `/api/me` on app start.
- Gate feature flags per user in a dedicated endpoint (`/api/features`).
