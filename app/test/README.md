# Test Suite Documentation

This test suite validates the backend baseline for API-driven products.
It focuses on authentication, protected APIs, dashboard/profile behavior,
uploads, notes, and optional third-party API clients.

## Table of Contents

- [Coverage Focus](#coverage-focus)
- [Key Directories](#key-directories)
- [Running Tests](#running-tests)
- [Notes](#notes)

## Coverage Focus

- Auth flows and protected route enforcement
- Profile/dashboard endpoints:
  - `GET /api/profile`
  - `GET /api/dashboard`
- Notes CRUD/caching behavior
- Example module APIs (`/api/v1/projects`, `/api/v1/tasks`)
- Upload presign and object management flows
- Infra-related runtime/auth helpers (RDS/Valkey IAM auth)

## Key Directories

```text
test/
├── backend/                         # Contexts, infra helpers, auth, cache tests
├── backend_web/
│   ├── api/                         # API controller tests
│   ├── controllers/api/             # Route-level notes/profile tests
│   ├── plugs/                       # Plug behavior tests
│   └── *.exs                        # Router/auth/health/schema tests
└── support/                         # ConnCase/DataCase helpers
```

## Running Tests

```bash
cd app
mix test
mix test --cover
```

Run a specific file:

```bash
mix test test/backend_web/controllers/api/profile_controller_test.exs
```

## Notes

- The suite uses `Mox` for HTTP client mocking where external requests are needed.
- Database tests run through Ecto SQL sandbox for isolation.
- Keep tests deterministic and avoid relying on live third-party APIs.
