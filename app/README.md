## Phoenix API Backend

This directory contains a **production-ready Phoenix API service** designed as a
starting point for mobile app backends. It intentionally avoids app-specific
business logic so you can plug in your own domain features.

### Table of Contents

- [Core Endpoints](#core-endpoints)
- [Features](#features)
- [Configuration](#configuration)
- [Local Development (Conceptual)](#local-development-conceptual)
- [Adding Your Own Endpoints](#adding-your-own-endpoints)
- [Sessions and Authentication](#sessions-and-authentication)
- [Testing](#testing)

### Core Endpoints

- `GET /` – Service metadata (name, version, key endpoints)
- `GET /healthz` – Health check for ALB/ECS/GA
- `GET /api/me` – Example authenticated endpoint
- `GET /auth/:provider` – Start OAuth flow (Google, Apple)
- `GET /auth/:provider/callback` – OAuth callback

**File Uploads API:**
- `POST /api/uploads/presign` – Get presigned URL for S3 upload
- `GET /api/uploads` – List user's uploaded files
- `GET /api/uploads/:key` – Get file metadata
- `GET /api/uploads/:key/download` – Get presigned download URL
- `DELETE /api/uploads/:key` – Delete a file
- `GET /api/uploads/types` – List allowed content types

### Features

- JSON-only responses
- OAuth via Ueberauth (Google, Apple)
- Session storage in Valkey/Redis for multi-container environments
- Ecto + PostgreSQL (Aurora friendly)
- Health checks for database and cache connectivity
- **S3 file uploads with presigned URLs** – Direct client-to-S3 uploads

### Configuration

All environment variables are documented in the root `ENVIRONMENT.md` file.
OAuth redirect behavior can be customized with `AUTH_SUCCESS_REDIRECT`,
`AUTH_FAILURE_REDIRECT`, and `AUTH_LOGOUT_REDIRECT`.

### Local Development (Conceptual)

For a full local dev workflow (Postgres + Valkey), see `docs/LOCAL_DEV.md`.

```bash
cd app
mix deps.get
mix phx.server
```

The API listens on `http://localhost:4000` by default.

If you want database support locally, run Postgres and set:

- `TEST_DB_HOST`
- `TEST_DB_USERNAME`
- `TEST_DB_PASSWORD`
- `TEST_DB_NAME`

### Adding Your Own Endpoints

Controllers live in `lib/backend_web/controllers`. For authenticated routes,
attach them to the `:protected_api` pipeline in `router.ex`.

Example:

```elixir
scope "/api", BackendWeb.API, as: :api do
  pipe_through(:protected_api)
  get "/profile", ProfileController, :show
end
```

### Sessions and Authentication

- Sessions are stored server-side in Valkey/Redis via `Backend.RedisSessionStore`.
- OAuth providers are optional; if credentials are missing, the provider is
  effectively disabled.
- Use `GET /api/me` to validate session behavior from a mobile client.

### Testing

```bash
cd app
mix test              # Run all tests
mix test --cover      # Run with coverage report
```

**Test Suite Features:**
- 650+ tests with 90% code coverage
- Mocked API tests (Stripe, Checkr, Google Maps) that run without credentials
- Live integration tests (optional, requires network access)
- Database tests using Ecto sandbox isolation

**Running Without Database:**
Most tests run without a database. For database-dependent tests:
```bash
docker compose up -d postgres
mix ecto.setup
mix test
```

See `test/README.md` for comprehensive test documentation.
