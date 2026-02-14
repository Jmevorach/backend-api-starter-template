# App Backend Blueprint

This document outlines practical next steps for evolving this repository into a
production-grade backend for any API-driven product.

## Table of Contents

- [Current Baseline](#current-baseline)
- [Suggested Extension Approach](#suggested-extension-approach)
- [Security Direction](#security-direction)
- [Integration Suggestions](#integration-suggestions)
- [Client Integration Tips](#client-integration-tips)

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
- Add retention and deletion workflows for user data exports and account deletion.

## Integration Suggestions

If your roadmap includes external system interoperability:

- Keep internal models decoupled from provider payloads.
- Validate and version integration contracts with tests.
- Add adapter modules for each external provider.

## Client Integration Tips

- Use `/api/v1/profile` and `/api/v1/dashboard` for initial app bootstrap.
- Keep session refresh simple: call `/api/v1/me` on app start.
- Gate feature flags per user in a dedicated endpoint (`/api/features`).

## Enterprise API Baseline Included

This starter now includes baseline enterprise APIs under `/api/v1`:

- SSO + SCIM: `/auth/sso/*`, `/scim/v2/*`
- RBAC/Policy: `/roles`, `/policy/evaluate`
- Audit logs: `/audit/events`
- Webhooks: `/webhooks/endpoints`, `/webhooks/deliveries`
- Notifications: `/notifications/send`, `/notifications/templates`
- Tenant controls: `/tenants`, `/entitlements`, `/features`
- Async and compliance: `/jobs`, `/compliance/export`, `/compliance/delete`
- Cross-domain search: `/search`
