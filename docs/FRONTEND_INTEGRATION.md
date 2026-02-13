# Frontend Integration Guide

This guide helps React/frontend teams integrate with this backend quickly and
predictably.

## Table of Contents

- [Auth and Session Model](#auth-and-session-model)
- [Bootstrap API Calls](#bootstrap-api-calls)
- [Profile and Dashboard Endpoints](#profile-and-dashboard-endpoints)
- [Notes and Upload Flows](#notes-and-upload-flows)
- [API Contract Examples](#api-contract-examples)
- [Error Handling Contract](#error-handling-contract)
- [Local Development Checklist](#local-development-checklist)

## Auth and Session Model

This backend is session-based:

1. User starts OAuth at `GET /auth/:provider`
2. Provider callback establishes server session
3. Browser/client sends session cookie on protected API calls

Protected endpoints are under `/api/v1/*` (preferred) and `/api/*` (compatibility), and require authentication via the
`:protected_api` pipeline.

## Bootstrap API Calls

For app startup, call endpoints in this order:

1. `GET /api/v1/me` (is user authenticated?)
2. `GET /api/v1/profile` (identity payload for UI header/profile)
3. `GET /api/v1/dashboard` (home screen summary)

If `GET /api/v1/me` returns `401`, redirect user to login.

## Profile and Dashboard Endpoints

### `GET /api/v1/profile`

Returns normalized user identity:

- `id`
- `email`
- `name`
- `first_name`
- `last_name`
- `avatar_url`
- `auth_provider`

### `GET /api/v1/dashboard`

Returns dashboard summary and note counts:

- `user` (id, name, email)
- `summary.active_notes`
- `summary.archived_notes`
- `summary.recent_notes`

Optional query param:

- `recent_limit` (default `5`, max `20`)

## Notes and Upload Flows

### Notes

- `GET /api/v1/notes`
- `POST /api/v1/notes`
- `PUT /api/v1/notes/:id`
- `DELETE /api/v1/notes/:id`
- `POST /api/v1/notes/:id/archive`
- `POST /api/v1/notes/:id/unarchive`

### Uploads

1. Request presigned upload: `POST /api/v1/uploads/presign`
2. Upload file directly to S3 using returned URL/form fields
3. Save returned key in your app metadata
4. Use:
   - `GET /api/v1/uploads`
   - `GET /api/v1/uploads/:key`
   - `GET /api/v1/uploads/:key/download`
   - `DELETE /api/v1/uploads/:key`

## API Contract Examples

For copy/paste request and response examples, see `API_CONTRACT.md`.
For TypeScript starter interfaces, see `../contracts/frontend-api.ts`.

## Error Handling Contract

Typical API error format:

```json
{
  "error": "Error message",
  "code": "machine_readable_code",
  "message": "Human-readable detail",
  "request_id": "F3n9Zz...",
  "details": {}
}
```

Common statuses:

- `401` unauthenticated
- `403` forbidden
- `404` not found
- `422` validation error
- `429` rate limit exceeded
- `500` internal error
- `503` service unavailable

## Local Development Checklist

- Start dependencies: `make dev-up`
- Run backend: `cd app && mix phx.server`
- Open docs: `http://localhost:4000/api/docs`
- Validate health: `GET /healthz`
