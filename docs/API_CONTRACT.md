# API Contract Reference

This document provides request/response examples for the core frontend-facing
endpoints.

## Conventions

- Base URL (local): `http://localhost:4000`
- Versioned base URL (recommended): `http://localhost:4000/api/v1`
- Protected endpoints require the session cookie.
- JSON content type is used for API request/response bodies.

## Versioning

- `/api/v1/*` is the canonical contract path for all new clients.
- `/api/*` remains available for backward compatibility in this starter.

## Standard Error Envelope

Most 4xx/5xx responses include:

```json
{
  "error": "Validation failed",
  "code": "validation_failed",
  "message": "Validation failed",
  "request_id": "F3n9Zz...",
  "details": {
    "title": [
      "can't be blank"
    ]
  }
}
```

## Auth Bootstrap

### `GET /api/me`

Also available as `GET /api/v1/me`.

Use this first to determine whether the user is authenticated.

#### `200 OK`

```json
{
  "user": {
    "email": "john@example.com",
    "name": "John Doe",
    "first_name": "John",
    "last_name": "Doe",
    "image": "https://example.com/avatar.jpg",
    "provider": "google",
    "provider_uid": "google_uid_123"
  },
  "authenticated": true
}
```

#### `401 Unauthorized`

```json
{
  "error": "Authentication required"
}
```

## Profile and Dashboard APIs

### `GET /api/profile`

Also available as `GET /api/v1/profile`.

#### `200 OK`

```json
{
  "data": {
    "id": "google_uid_123",
    "email": "john@example.com",
    "name": "John Doe",
    "first_name": "John",
    "last_name": "Doe",
    "avatar_url": "https://example.com/avatar.jpg",
    "auth_provider": "google"
  }
}
```

### `GET /api/dashboard?recent_limit=5`

Also available as `GET /api/v1/dashboard?recent_limit=5`.

`recent_limit` is optional (`default: 5`, `max: 20`).

#### `200 OK`

```json
{
  "data": {
    "user": {
      "id": "google_uid_123",
      "name": "John Doe",
      "email": "john@example.com"
    },
    "summary": {
      "active_notes": 2,
      "archived_notes": 1,
      "recent_notes": [
        {
          "id": "550e8400-e29b-41d4-a716-446655440000",
          "title": "Sprint planning follow-up",
          "content": "Schedule planning session for next week",
          "archived": false,
          "inserted_at": "2026-02-13T17:54:34.599935Z",
          "updated_at": "2026-02-13T17:54:34.599935Z"
        }
      ]
    }
  }
}
```

## Notes APIs

### `GET /api/notes?archived=false&limit=50&offset=0&search=release`

Also available as `GET /api/v1/notes?...`.

All query params are optional.

#### `200 OK`

```json
{
  "data": [
    {
      "id": "550e8400-e29b-41d4-a716-446655440000",
      "title": "Sprint planning follow-up",
      "content": "Schedule planning session for next week",
      "archived": false,
      "inserted_at": "2026-02-13T17:54:34.599935Z",
      "updated_at": "2026-02-13T17:54:34.599935Z"
    }
  ],
  "meta": {
    "count": 1,
    "total": 3,
    "limit": 50,
    "offset": 0
  }
}
```

### `POST /api/notes`

#### Request

```json
{
  "title": "Release reminder",
  "content": "Prepare release notes before 8:00 PM"
}
```

#### `201 Created`

```json
{
  "data": {
    "id": "44de4cde-8d75-4d1d-b1af-31d4a9c7c4c8",
    "title": "Release reminder",
    "content": "Prepare release notes before 8:00 PM",
    "archived": false,
    "inserted_at": "2026-02-13T18:00:00.000000Z",
    "updated_at": "2026-02-13T18:00:00.000000Z"
  }
}
```

#### `422 Unprocessable Entity`

```json
{
  "error": "Validation failed",
  "details": {
    "title": [
      "can't be blank"
    ]
  }
}
```

### `PUT /api/notes/:id`

#### Request

```json
{
  "title": "Updated title",
  "content": "Updated note content"
}
```

#### `200 OK`

```json
{
  "data": {
    "id": "44de4cde-8d75-4d1d-b1af-31d4a9c7c4c8",
    "title": "Updated title",
    "content": "Updated note content",
    "archived": false,
    "inserted_at": "2026-02-13T18:00:00.000000Z",
    "updated_at": "2026-02-13T18:05:00.000000Z"
  }
}
```

### `POST /api/notes/:id/archive`

#### `200 OK`

```json
{
  "data": {
    "id": "44de4cde-8d75-4d1d-b1af-31d4a9c7c4c8",
    "archived": true
  }
}
```

### `POST /api/notes/:id/unarchive`

#### `200 OK`

```json
{
  "data": {
    "id": "44de4cde-8d75-4d1d-b1af-31d4a9c7c4c8",
    "archived": false
  }
}
```

### `DELETE /api/notes/:id`

#### `204 No Content`

No response body.

### Common Notes Errors

#### `404 Not Found`

```json
{
  "error": "Note not found"
}
```

## Upload APIs

### `POST /api/uploads/presign`

Also available as `POST /api/v1/uploads/presign`.

#### Request

```json
{
  "filename": "project-spec.pdf",
  "content_type": "application/pdf"
}
```

#### `200 OK`

```json
{
  "url": "https://your-bucket.s3.amazonaws.com",
  "key": "users/google_uid_123/uploads/1771005274_64ca3065_project-spec.pdf",
  "fields": {
    "key": "users/google_uid_123/uploads/1771005274_64ca3065_project-spec.pdf",
    "policy": "base64-policy",
    "x-amz-algorithm": "AWS4-HMAC-SHA256",
    "x-amz-credential": "AKIA.../20260213/us-east-1/s3/aws4_request",
    "x-amz-date": "20260213T120000Z",
    "x-amz-signature": "..."
  }
}
```

#### `400 Bad Request`

```json
{
  "error": "invalid_content_type",
  "message": "Content type not allowed",
  "allowed_types": [
    "image/jpeg",
    "image/png",
    "image/gif",
    "image/webp",
    "application/pdf",
    "text/plain"
  ]
}
```

### `GET /api/uploads`

Also available as `GET /api/v1/uploads`.

#### `200 OK`

```json
{
  "files": [
    {
      "key": "users/google_uid_123/uploads/1771005274_64ca3065_project-spec.pdf",
      "filename": "project-spec.pdf",
      "size": 245123,
      "content_type": "application/pdf",
      "last_modified": "2026-02-13T18:10:00Z"
    }
  ],
  "next_token": null
}
```

### `GET /api/uploads/:key/download`

Also available as `GET /api/v1/uploads/:key/download`.

#### `200 OK`

```json
{
  "url": "https://your-bucket.s3.amazonaws.com/...signed-download-url...",
  "key": "users/google_uid_123/uploads/1771005274_64ca3065_project-spec.pdf"
}
```

### `DELETE /api/uploads/:key`

#### `204 No Content`

No response body.

## Projects and Tasks (Golden Path Module)

### `POST /api/v1/projects`

#### Request

```json
{
  "name": "Platform",
  "description": "Core backend work"
}
```

#### `201 Created`

```json
{
  "data": {
    "id": "a8f05310-7fd7-4e5c-bf27-5fc98f29b4d7",
    "name": "Platform",
    "description": "Core backend work",
    "archived": false,
    "inserted_at": "2026-02-13T18:00:00.000000Z",
    "updated_at": "2026-02-13T18:00:00.000000Z"
  }
}
```

### `GET /api/v1/projects`

#### `200 OK`

```json
{
  "data": [
    {
      "id": "a8f05310-7fd7-4e5c-bf27-5fc98f29b4d7",
      "name": "Platform",
      "description": "Core backend work",
      "archived": false
    }
  ]
}
```

### `POST /api/v1/tasks`

#### Request

```json
{
  "project_id": "a8f05310-7fd7-4e5c-bf27-5fc98f29b4d7",
  "title": "Ship API governance",
  "status": "todo"
}
```

#### `201 Created`

```json
{
  "data": {
    "id": "a4f5f3ba-8139-4589-b4fd-f46a8c61ccf4",
    "project_id": "a8f05310-7fd7-4e5c-bf27-5fc98f29b4d7",
    "title": "Ship API governance",
    "status": "todo"
  }
}
```

### `GET /api/v1/tasks?project_id=:id&status=todo`

#### `200 OK`

```json
{
  "data": [
    {
      "id": "a4f5f3ba-8139-4589-b4fd-f46a8c61ccf4",
      "project_id": "a8f05310-7fd7-4e5c-bf27-5fc98f29b4d7",
      "title": "Ship API governance",
      "status": "todo"
    }
  ]
}
```

### Common Upload Errors

#### `403 Forbidden`

```json
{
  "error": "forbidden",
  "message": "You don't have access to this file"
}
```

#### `503 Service Unavailable`

```json
{
  "error": "service_unavailable",
  "message": "File uploads are not configured"
}
```
