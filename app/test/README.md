# Test Suite Documentation

This document describes the organization, structure, and usage of the test suite for the Backend API Accelerator.

## Table of Contents

- [Overview](#overview)
- [Directory Structure](#directory-structure)
- [Test Categories](#test-categories)
  - [Unit Tests](#unit-tests)
  - [Mocked Tests](#mocked-tests)
  - [Live Integration Tests](#live-integration-tests)
  - [Controller Tests](#controller-tests)
- [Test Support Modules](#test-support-modules)
- [Running Tests](#running-tests)
- [Test Configuration](#test-configuration)
- [Mocking Strategy](#mocking-strategy)
- [Writing New Tests](#writing-new-tests)

---

## Overview

The test suite uses ExUnit with the following key technologies:

- **Mox** - For mocking HTTP clients and external dependencies
- **Ecto.Adapters.SQL.Sandbox** - For database isolation between tests
- **Phoenix.ConnTest** - For testing HTTP endpoints

**Current Stats:**
- 650+ tests
- 90% code coverage
- All tests pass without external API credentials

---

## Directory Structure

```
test/
├── README.md                    # This file
├── test_helper.exs              # Test configuration and setup
├── support/                     # Test case templates and helpers
│   ├── conn_case.ex             # Phoenix connection test case
│   └── data_case.ex             # Ecto database test case
├── backend/                     # Backend module tests
│   ├── application_test.exs     # Application startup tests
│   ├── application_config_test.exs  # Configuration path tests
│   ├── checkr_test.exs          # Checkr unit tests
│   ├── checkr_mocked_test.exs   # Checkr mocked API tests
│   ├── checkr_live_test.exs     # Checkr live API tests
│   ├── elasticache_iam_auth_test.exs
│   ├── google_maps_test.exs     # Google Maps unit tests
│   ├── google_maps_mocked_test.exs  # Google Maps mocked tests
│   ├── google_maps_live_test.exs    # Google Maps live tests
│   ├── google_maps_edge_cases_test.exs  # Additional edge cases
│   ├── http_client_test.exs     # HTTP client wrapper tests
│   ├── logger_json_test.exs
│   ├── notes_test.exs           # Notes CRUD tests
│   ├── notes_cache_test.exs     # Notes caching tests
│   ├── notes_edge_cases_test.exs    # Notes edge case tests
│   ├── rds_iam_auth_test.exs
│   ├── redis_session_store_test.exs
│   ├── repo_auth_test.exs
│   ├── stripe_test.exs          # Stripe unit tests
│   ├── stripe_mocked_test.exs   # Stripe mocked API tests
│   ├── stripe_live_test.exs     # Stripe live API tests
│   ├── valkey_auth_test.exs
│   └── valkey_auth_unit_test.exs
├── backend_web/                 # Web layer tests
│   ├── api/
│   │   ├── notes_controller_test.exs
│   │   ├── openapi_controller_test.exs
│   │   └── user_controller_test.exs
│   ├── controllers/
│   │   └── api/
│   │       └── notes_controller_test.exs
│   ├── plugs/
│   │   ├── ensure_authenticated_test.exs
│   │   └── request_logger_test.exs
│   ├── auth_controller_test.exs
│   ├── error_json_test.exs
│   ├── fallback_controller_test.exs
│   ├── health_controller_test.exs
│   ├── home_controller_test.exs
│   ├── router_test.exs
│   └── schemas_test.exs
└── backend_web_test.exs         # BackendWeb module macros
```

---

## Test Categories

### Unit Tests

Unit tests verify individual modules in isolation without external dependencies.

| File | Module Under Test | Description |
|------|-------------------|-------------|
| `backend/application_test.exs` | `Backend.Application` | Application startup and supervision tree |
| `backend/logger_json_test.exs` | `Backend.LoggerJSON` | JSON log formatting |
| `backend/notes_test.exs` | `Backend.Notes` | Notes CRUD operations (requires DB) |
| `backend/redis_session_store_test.exs` | `Backend.RedisSessionStore` | Session storage behavior |
| `backend/rds_iam_auth_test.exs` | `Backend.RdsIamAuth` | RDS IAM token generation |
| `backend/elasticache_iam_auth_test.exs` | `Backend.ElasticacheIamAuth` | ElastiCache IAM auth |
| `backend/repo_auth_test.exs` | `Backend.Repo` | Database authentication |
| `backend/valkey_auth_test.exs` | `Backend.ValkeyAuth` | Valkey/Redis authentication |
| `backend_web_test.exs` | `BackendWeb` | Phoenix module macros |
| `backend_web/schemas_test.exs` | `BackendWeb.Schemas` | OpenAPI schema definitions |
| `backend_web/error_json_test.exs` | `BackendWeb.ErrorJSON` | Error response formatting |

### Mocked Tests

Mocked tests use **Mox** to simulate HTTP responses with realistic API data. They test full code paths without making real network calls.

| File | API Client | Test Count | Description |
|------|------------|------------|-------------|
| `backend/google_maps_mocked_test.exs` | `Backend.GoogleMaps` | 30+ | Geocoding, places, distance matrix |
| `backend/stripe_mocked_test.exs` | `Backend.Stripe` | 25+ | Customers, payments, subscriptions |
| `backend/checkr_mocked_test.exs` | `Backend.Checkr` | 25+ | Candidates, invitations, reports |

**Key Features:**
- Realistic response fixtures based on actual API documentation
- Tests all success and error paths
- Verifies request parameter construction
- No network calls required

### Live Integration Tests

Live tests make real HTTP requests with invalid credentials to verify request formatting.

| File | API | Purpose |
|------|-----|---------|
| `backend/google_maps_live_test.exs` | Google Maps | Verify REQUEST_DENIED (not INVALID_REQUEST) |
| `backend/stripe_live_test.exs` | Stripe | Verify auth errors (not malformed request) |
| `backend/checkr_live_test.exs` | Checkr | Verify "Bad authentication" errors |

**Why Live Tests Matter:**
- Prove request structure is correct (APIs return auth errors, not format errors)
- Verify URL construction and parameter encoding
- Confirm special characters and unicode handling

**Running Live Tests:**
```bash
# Live tests are excluded by default
mix test --include live_api

# Run specific live test file
mix test test/backend/stripe_live_test.exs --include live_api
```

### Controller Tests

Controller tests verify HTTP endpoints using Phoenix.ConnTest.

| File | Controller | Endpoints Tested |
|------|------------|------------------|
| `backend_web/auth_controller_test.exs` | `AuthController` | OAuth callbacks, logout |
| `backend_web/health_controller_test.exs` | `HealthController` | `/healthz`, `/readyz` |
| `backend_web/home_controller_test.exs` | `HomeController` | `/` |
| `backend_web/api/notes_controller_test.exs` | `NotesController` | CRUD for `/api/notes` |
| `backend_web/api/user_controller_test.exs` | `UserController` | `/api/me` |
| `backend_web/api/openapi_controller_test.exs` | `OpenApiController` | `/api/openapi`, `/api/docs` |
| `backend_web/router_test.exs` | `Router` | Route configuration |
| `backend_web/fallback_controller_test.exs` | `FallbackController` | Error handling |

### Plug Tests

| File | Plug | Description |
|------|------|-------------|
| `backend_web/plugs/ensure_authenticated_test.exs` | `EnsureAuthenticated` | Auth enforcement |
| `backend_web/plugs/request_logger_test.exs` | `RequestLogger` | Request/response logging |

---

## Test Support Modules

### `BackendWeb.ConnCase`

Use for tests that need HTTP connections:

```elixir
defmodule MyControllerTest do
  use BackendWeb.ConnCase

  test "GET /endpoint", %{conn: conn} do
    conn = get(conn, "/endpoint")
    assert json_response(conn, 200)
  end
end
```

**Provides:**
- `@endpoint BackendWeb.Endpoint`
- `Phoenix.ConnTest` functions
- `Plug.Conn` helpers
- Database sandbox isolation

### `Backend.DataCase`

Use for tests that need database access without HTTP:

```elixir
defmodule MyContextTest do
  use Backend.DataCase

  test "creates a record" do
    {:ok, record} = MyContext.create(%{name: "test"})
    assert record.name == "test"
  end
end
```

**Provides:**
- `Backend.Repo` alias
- `Ecto` query helpers
- `errors_on/1` helper for changeset testing
- Database sandbox isolation

---

## Running Tests

### Basic Commands

```bash
# Run all tests
mix test

# Run with coverage report
mix test --cover

# Run specific file
mix test test/backend/stripe_test.exs

# Run specific test by line number
mix test test/backend/stripe_test.exs:42

# Run tests matching a pattern
mix test --only describe:"when not configured"
```

### Makefile Targets

```bash
# Run unit tests only (no database required)
make app-test-unit

# Start Docker, run all tests, stop Docker
make app-test-all

# Run with coverage report
make app-test-cover
```

### Excluding/Including Tags

```bash
# Exclude live API tests (default)
mix test --exclude live_api

# Include live API tests
mix test --include live_api

# Run only live API tests
mix test --only live_api
```

---

## Test Configuration

### test_helper.exs

The test helper configures:

1. **Mox Mock** - Defines `Backend.HTTPClientMock` for HTTP mocking
2. **HTTP Client** - Sets mock as default HTTP client
3. **Database Sandbox** - Configures Ecto sandbox mode

```elixir
# Configure Mox for API client testing
Mox.defmock(Backend.HTTPClientMock, for: Backend.HTTPClient)

# Set the mock as the default HTTP client in test environment
Application.put_env(:backend, :http_client, Backend.HTTPClientMock)
```

### Environment Variables

Tests can run without external services:

| Dependency | Behavior When Unavailable |
|------------|---------------------------|
| PostgreSQL | Warning printed, DB tests may fail |
| Valkey/Redis | Session tests use mock behavior |
| AWS Credentials | IAM token tests show expected errors |
| API Keys | Mocked responses used |

---

## Mocking Strategy

### HTTP Client Mocking

All external API clients use `Backend.HTTPClient` which can be mocked:

```elixir
# In test setup
import Mox
setup :verify_on_exit!

# Stub for all HTTP calls (returns generic error)
stub(Backend.HTTPClientMock, :get, fn _url, _opts ->
  {:ok, %{status: 401, body: %{"error" => "unauthorized"}}}
end)

# Expect specific call with verification
expect(Backend.HTTPClientMock, :post, fn url, opts ->
  assert url =~ "api.stripe.com/v1/customers"
  assert opts[:form][:email] == "test@example.com"
  {:ok, %{status: 200, body: %{"id" => "cus_123"}}}
end)
```

### Live Tests Override

Live tests use the real HTTP client:

```elixir
setup do
  # Use real HTTP client for live tests
  Application.put_env(:backend, :http_client, Backend.HTTPClient.Impl)

  on_exit(fn ->
    # Restore mock for other tests
    Application.put_env(:backend, :http_client, Backend.HTTPClientMock)
  end)
end
```

---

## Writing New Tests

### Adding Unit Tests

1. Create file matching the module: `test/backend/my_module_test.exs`
2. Use appropriate test case:

```elixir
defmodule Backend.MyModuleTest do
  use ExUnit.Case, async: true  # or async: false if modifying global state

  alias Backend.MyModule

  describe "function_name/1" do
    test "does something" do
      assert MyModule.function_name(:input) == :expected
    end
  end
end
```

### Adding Mocked API Tests

1. Create file: `test/backend/api_client_mocked_test.exs`
2. Import Mox and set up expectations:

```elixir
defmodule Backend.ApiClientMockedTest do
  use ExUnit.Case, async: true

  import Mox

  setup :verify_on_exit!

  setup do
    Application.put_env(:backend, :api_client, api_key: "test_key")
    on_exit(fn -> Application.delete_env(:backend, :api_client) end)
    :ok
  end

  describe "api_call/1" do
    test "returns data on success" do
      expect(Backend.HTTPClientMock, :get, fn url, _opts ->
        assert url =~ "expected-endpoint"
        {:ok, %{status: 200, body: %{"data" => "value"}}}
      end)

      assert {:ok, %{"data" => "value"}} = ApiClient.api_call(:param)
    end
  end
end
```

### Adding Controller Tests

1. Create file in appropriate directory
2. Use `BackendWeb.ConnCase`:

```elixir
defmodule BackendWeb.MyControllerTest do
  use BackendWeb.ConnCase

  describe "GET /my-endpoint" do
    test "returns 200", %{conn: conn} do
      conn = get(conn, "/my-endpoint")
      assert json_response(conn, 200)["status"] == "ok"
    end

    test "requires authentication", %{conn: conn} do
      conn = get(conn, "/api/protected")
      assert json_response(conn, 401)
    end
  end
end
```

---

## Coverage Goals

| Category | Target | Current |
|----------|--------|---------|
| API Clients (Stripe, Checkr, Google Maps) | 95%+ | 95%+ |
| Controllers | 80%+ | 90%+ |
| Plugs | 100% | 100% |
| Core Business Logic | 80%+ | 90%+ |
| Overall | 80%+ | 90% |

Run coverage report:
```bash
mix test --cover
```

**Coverage Configuration:**

The `coveralls.json` file excludes certain files from coverage calculation:
- `lib/backend/application.ex` - OTP application startup code that runs once at boot

This is a common pattern for Elixir projects since application module code is inherently difficult to unit test without integration testing the full supervision tree.

---

## Troubleshooting

### Database Connection Errors

```
** (DBConnection.ConnectionError) connection not available
```

**Solution:** Start the database:
```bash
docker compose up -d postgres
mix ecto.create
mix ecto.migrate
```

### Mox Unexpected Call Errors

```
** (Mox.UnexpectedCallError) no expectation defined for Backend.HTTPClientMock.get/2
```

**Solution:** Add a stub or expectation in your test setup:
```elixir
stub(Backend.HTTPClientMock, :get, fn _url, _opts ->
  {:ok, %{status: 200, body: %{}}}
end)
```

### Tests Modifying Global State

If tests fail intermittently, ensure:
1. Use `async: false` for tests modifying `Application.put_env`
2. Always restore original config in `on_exit/1`
3. Use unique identifiers for test data
