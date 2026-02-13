# Test Suite Documentation

This test suite validates the backend baseline for an open-source patient app.
It focuses on authentication, protected APIs, patient dashboard/profile behavior,
uploads, and notes.

## Coverage Focus

- Auth flows and protected route enforcement
- Patient-oriented endpoints:
  - `GET /api/patient/profile`
  - `GET /api/patient/dashboard`
- Notes CRUD/caching behavior
- Upload presign and object management flows
- Infra-related runtime/auth helpers (RDS/Valkey IAM auth)

## Key Directories

```text
test/
├── backend/                         # Contexts, infra helpers, auth, cache tests
├── backend_web/
│   ├── api/                         # API controller tests
│   ├── controllers/api/             # Route-level notes/patient tests
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
mix test test/backend_web/controllers/api/patient_controller_test.exs
```

## Notes

- The suite uses `Mox` for HTTP client mocking where external requests are needed.
- Database tests run through Ecto SQL sandbox for isolation.
- Keep tests deterministic and avoid relying on live third-party APIs.
