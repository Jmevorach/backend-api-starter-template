# Contributing Guide

This guide explains how to extend the backend API starter baseline with new API
integrations and how to modify the AWS infrastructure.

## Table of Contents

- [Philosophy](#philosophy)
- [Adding API Client Modules](#adding-api-client-modules)
- [Modifying AWS Infrastructure](#modifying-aws-infrastructure)
- [Security Considerations](#security-considerations)
- [Testing](#testing)
- [API Contract Drift Policy](#api-contract-drift-policy)
- [Pull Request Guidelines](#pull-request-guidelines)

## Philosophy

This project aims to be a **batteries-included** starting point for backend development.
Users should be able to:

1. Clone the repo
2. Configure their auth/integration secrets
3. Write routes
4. Ship to production

When contributing, keep this philosophy in mind. New integrations should:

- Work out of the box with minimal configuration
- Be **optional** (the app should start without them)
- Follow established patterns in the codebase
- Include clear documentation

## Adding API Client Modules

The project includes optional API clients (Stripe, Checkr, Google Maps) and
supports adding more integrations with the same patterns below.

### Step 1: Create the Client Module

Create a new module in `app/lib/backend/` following this structure:

```elixir
defmodule Backend.YourApi do
  @moduledoc """
  Client module for the YourApi API.

  This module provides functions for [describe what it does].

  ## Configuration

  Set the following environment variables:
  - `YOUR_API_KEY` - Your API key from [provider]

  ## Usage

      # Example usage
      Backend.YourApi.do_something("param")
  """

  @base_url "https://api.yourservice.com/v1"

  # Make configuration optional - module works when configured
  defp api_key do
    case Application.get_env(:backend, :your_api) do
      nil -> nil
      config -> Keyword.get(config, :api_key)
    end
  end

  defp configured? do
    api_key() != nil
  end

  @doc """
  Example function that calls the API.

  Returns `{:ok, result}` on success, `{:error, reason}` on failure,
  or `{:error, :not_configured}` if API key is not set.
  """
  def do_something(param) do
    if configured?() do
      request(:get, "/endpoint/#{param}")
    else
      {:error, :not_configured}
    end
  end

  # Private HTTP helpers
  defp http_client do
    Application.get_env(:backend, :http_client, Backend.HTTPClient.Impl)
  end

  defp request(method, path, body \\ nil) do
    url = @base_url <> path

    headers = [
      {"Authorization", "Bearer #{api_key()}"},
      {"Content-Type", "application/json"}
    ]

    request_opts = [headers: headers]
    request_opts = if body, do: Keyword.put(request_opts, :json, body), else: request_opts

    case apply(http_client(), method, [url, request_opts]) do
      {:ok, %{status: status, body: body}} when status in 200..299 ->
        {:ok, body}

      {:ok, %{status: status, body: body}} ->
        {:error, %{status: status, body: body}}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
```

### Step 2: Add Configuration in runtime.exs

Add conditional configuration in `app/config/runtime.exs`:

```elixir
# YourApi configuration (optional)
your_api_key = System.get_env("YOUR_API_KEY")

if your_api_key do
  config :backend, :your_api, api_key: your_api_key
end
```

### Step 3: Add Terraform Variables (Optional)

If the API key will be stored in AWS Secrets Manager, add to `infra/variables.tf`:

```hcl
variable "your_api_key_secret_arn" {
  description = "ARN of the Secrets Manager secret containing the YourApi API key"
  type        = string
  default     = ""
}
```

Then update `infra/ecs.tf` to inject the secret:

```hcl
# In the local.ecs_app_secrets concat block
concat(
  # ... existing secrets ...
  var.your_api_key_secret_arn != "" ? [{
    name      = "YOUR_API_KEY"
    valueFrom = var.your_api_key_secret_arn
  }] : [],
)
```

And update IAM permissions in `infra/iam.tf` to allow reading the secret.

### Step 4: Document the Integration

1. Add environment variables to `ENVIRONMENT.md`
2. Add usage examples to your module's `@moduledoc`
3. Consider adding a section to `docs/CUSTOMIZATION.md`

### Step 5: Add Tests

Create tests in `app/test/backend/your_api_test.exs`:

```elixir
defmodule Backend.YourApiTest do
  use ExUnit.Case, async: true

  describe "when not configured" do
    test "returns :not_configured error" do
      assert {:error, :not_configured} = Backend.YourApi.do_something("test")
    end
  end

  # Add more tests with mocked HTTP responses
end
```

## Modifying AWS Infrastructure

The infrastructure is defined in Terraform under `infra/`. Here's how to make common modifications.

### Understanding the Structure

```
infra/
├── main.tf              # Provider configuration, locals
├── variables.tf         # Input variables
├── outputs.tf           # Output values
├── network.tf           # VPC, subnets, security groups
├── ecs.tf               # ECS cluster, service, task definition
├── rds.tf               # Aurora PostgreSQL cluster
├── elasticache.tf       # Valkey/Redis cluster
├── iam.tf               # IAM roles and policies
├── secrets.tf           # Secrets Manager secrets
├── secret-rotation.tf   # Lambda rotation functions
├── monitoring.tf        # CloudWatch dashboards and alarms
├── logging.tf           # CloudWatch log groups
├── kms.tf               # KMS encryption keys
├── ecr.tf               # Container registry
├── backup.tf            # AWS Backup configuration
├── cost-monitoring.tf   # Budgets and cost alerts
└── lambdas/             # Python Lambda functions
```

### Common Modifications

#### Scaling ECS

Edit `infra/ecs.tf`:

```hcl
# Change minimum/maximum task count
resource "aws_appautoscaling_target" "ecs_target" {
  min_capacity = 2   # Minimum tasks
  max_capacity = 10  # Maximum tasks
  # ...
}

# Adjust CPU scaling threshold
resource "aws_appautoscaling_policy" "ecs_cpu" {
  # ...
  target_tracking_scaling_policy_configuration {
    target_value = 70.0  # Scale when CPU exceeds 70%
  }
}
```

#### Database Sizing

Edit `infra/rds.tf`:

```hcl
resource "aws_rds_cluster" "app" {
  # ...
  serverlessv2_scaling_configuration {
    min_capacity = 0.5   # Minimum ACUs (can go to 0.5 for cost savings)
    max_capacity = 16.0  # Maximum ACUs
  }
}
```

#### Adding Environment Variables

1. For non-sensitive values, add to the container definition in `infra/ecs.tf`:

```hcl
environment = [
  # ... existing vars ...
  {
    name  = "MY_NEW_VAR"
    value = var.my_new_var
  }
]
```

2. For secrets, add to `local.ecs_app_secrets` and update IAM permissions.

#### Modifying Security Groups

Edit `infra/network.tf` to adjust ingress/egress rules:

```hcl
resource "aws_security_group_rule" "new_rule" {
  type              = "ingress"
  from_port         = 8080
  to_port           = 8080
  protocol          = "tcp"
  cidr_blocks       = ["10.0.0.0/8"]
  security_group_id = aws_security_group.app.id
}
```

#### Adding New AWS Services

1. Create a new `.tf` file (e.g., `infra/sqs.tf`)
2. Define the resources
3. Add any required IAM permissions to `infra/iam.tf`
4. Add variables to `infra/variables.tf`
5. Output any needed values in `infra/outputs.tf`

### Testing Infrastructure Changes

```bash
# Format check
terraform fmt -check -recursive infra/

# Validate syntax
cd infra && terraform validate

# Preview changes
./scripts/deploy.sh --plan-only

# Run security scans
make terraform-security
```

### Infrastructure Best Practices

1. **Use variables** for anything that might change between environments
2. **Tag all resources** using `local.tags` for cost tracking
3. **Enable encryption** for any new data stores (use the existing KMS key)
4. **Follow least privilege** when adding IAM permissions
5. **Add monitoring** for new services in `monitoring.tf`
6. **Document changes** in `docs/ARCHITECTURE.md`

## Security Considerations

When adding new integrations:

1. **Never hardcode secrets** - Use environment variables and Secrets Manager
2. **Validate webhook signatures** using constant-time comparison
3. **Use TLS** - All external API calls should use HTTPS
4. **Implement rate limiting** - Consider adding rate limiting for new endpoints
5. **Log carefully** - Don't log sensitive data (API keys, tokens, PII)
6. **Follow OWASP guidelines** - Review [docs/SECURITY.md](docs/SECURITY.md)

## Testing

### Running Tests

```bash
# Elixir tests
cd app && mix test

# With coverage (minimum gate is enforced in CI; keep it trending upward)
cd app && mix test --cover

# Specific test file
cd app && mix test test/backend/your_api_test.exs

# Include live API tests (requires network)
cd app && mix test --include live_api
```

### Test Categories

The test suite includes three types of tests:

1. **Unit Tests** - Test modules in isolation
2. **Mocked Tests** - Use Mox to simulate HTTP responses
3. **Live Tests** - Make real API calls with invalid credentials

### Mocking HTTP Requests with Mox

API client modules use `Backend.HTTPClient` which can be mocked with Mox:

```elixir
defmodule Backend.YourApiMockedTest do
  use ExUnit.Case, async: true

  import Mox

  setup :verify_on_exit!

  setup do
    Application.put_env(:backend, :your_api, api_key: "test_key")
    on_exit(fn -> Application.delete_env(:backend, :your_api) end)
    :ok
  end

  describe "do_something/1" do
    test "returns data on success" do
      expect(Backend.HTTPClientMock, :get, fn url, _opts ->
        assert url =~ "/endpoint/param"
        {:ok, %{status: 200, body: %{"data" => "value"}}}
      end)

      assert {:ok, %{"data" => "value"}} = Backend.YourApi.do_something("param")
    end

    test "handles API errors" do
      expect(Backend.HTTPClientMock, :get, fn _url, _opts ->
        {:ok, %{status: 400, body: %{"error" => "invalid request"}}}
      end)

      assert {:error, %{status: 400}} = Backend.YourApi.do_something("bad")
    end
  end
end
```

### Using the HTTPClient Behavior

New API client modules should use `Backend.HTTPClient` instead of calling `Req` directly:

```elixir
defmodule Backend.YourApi do
  # Use HTTPClient for mockable HTTP requests
  defp http_client do
    Application.get_env(:backend, :http_client, Backend.HTTPClient.Impl)
  end

  defp request(method, path, body \\ nil) do
    url = @base_url <> path
    opts = [headers: headers()]
    opts = if body, do: Keyword.put(opts, :json, body), else: opts

    apply(http_client(), method, [url, opts])
  end
end
```

See `test/README.md` for comprehensive testing documentation.

## API Contract Drift Policy

When a PR changes any API behavior used by client applications, keep the contract
artifacts in sync in the same PR.

Update these files together:

1. `docs/API_CONTRACT.md` (request/response examples and status codes)
2. `contracts/frontend-api.ts` (TypeScript interfaces consumed by API clients)
3. `docs/FRONTEND_INTEGRATION.md` (flow or usage guidance when needed)

### What counts as a contract change

- New endpoint, removed endpoint, or route rename
- Request body/query/path parameter changes
- Response shape changes (new/removed/renamed fields)
- Status code or error payload changes

### Required local checks

Run these before opening a PR:

```bash
make verify
make contract-validate
make contract-typecheck
```

CI enforces the same checks through `Frontend Contract CI`. If these fail, treat
it as contract drift and update docs/types before merging.

### OpenAPI governance

OpenAPI is treated as a first-class contract artifact.

Run locally before PR:

```bash
make openapi-lint
make openapi-breakcheck
make openapi-breakcheck-test
```

`API Governance CI` enforces the same policy and flags potentially breaking contract changes.

## Pull Request Guidelines

1. **One feature per PR** - Keep changes focused
2. **Include tests** - New code should have test coverage
3. **Update documentation** - Update relevant docs and ENVIRONMENT.md
4. **Run CI checks locally** first:
   ```bash
   make verify
   make openapi-breakcheck-test
   make terraform-security
   ```
5. **Write clear commit messages** - Explain what and why
6. **Link related issues** - Reference any related GitHub issues

### PR Checklist

- [ ] Tests pass locally
- [ ] Documentation updated
- [ ] API contract updated (`docs/API_CONTRACT.md` + `contracts/frontend-api.ts`) if endpoint behavior changed
- [ ] ENVIRONMENT.md updated (if new env vars)
- [ ] Security considerations addressed
- [ ] Terraform validates (`terraform validate`)
- [ ] No hardcoded secrets or credentials
