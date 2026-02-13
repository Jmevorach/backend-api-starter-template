## Customization Guide

This repo is intentionally generic. Use this document to tailor it to your
product while keeping the production baseline intact.

### Table of Contents

- [Rename the Service](#rename-the-service)
- [Add Your API Routes](#add-your-api-routes)
- [Data Models and Migrations](#data-models-and-migrations)
- [Authentication Providers](#authentication-providers)
- [Sessions](#sessions)
- [Third-Party API Integrations](#third-party-api-integrations)
- [TLS/SSL Configuration](#tlsssl-configuration)
- [Infrastructure Adjustments](#infrastructure-adjustments)
- [Mobile-Specific Extensions](#mobile-specific-extensions)
- [Keep It Maintainable](#keep-it-maintainable)

### Rename the Service

- Update the `project_name` variable for resource naming.
- Update the root endpoint output in `HomeController`.
- Adjust ECR repository name and GitHub variables.

### Add Your API Routes

- Create controllers in `app/lib/backend_web/controllers`.
- Wire routes in `app/lib/backend_web/router.ex`.
- Use `:protected_api` for authenticated endpoints.

Example:

```elixir
scope "/api", BackendWeb.API, as: :api do
  pipe_through(:protected_api)
  resources "/projects", ProjectController, only: [:index, :create]
end
```

### Data Models and Migrations

- Add schemas in `app/lib/backend`.
- Create migrations under `app/priv/repo/migrations`.
- Run `mix ecto.migrate` locally or via CI.

### Authentication Providers

- OAuth providers are optional.
- Provide credentials via Secrets Manager and set the ARN variables in Terraform.
- Update redirect URLs via `AUTH_*` env vars.

### Sessions

- Sessions are stored in Valkey when `VALKEY_HOST` is set.
- If you prefer stateless auth, replace session usage with JWTs.

### Third-Party API Integrations

The project includes pre-built client modules for common APIs:

- **Stripe** (`Backend.Stripe`) - Payments, subscriptions, customers
- **Checkr** (`Backend.Checkr`) - Background checks
- **Google Maps** (`Backend.GoogleMaps`) - Geocoding, places, distance matrix

To use these integrations:

1. **Get your API key** from the provider's dashboard
2. **Store in Secrets Manager** (recommended for production):
   ```bash
   aws secretsmanager create-secret \
     --name "myapp/stripe-api-key" \
     --secret-string "sk_live_..."
   ```
3. **Set the Terraform variable** to inject the secret:
   ```hcl
   stripe_api_key_secret_arn = "arn:aws:secretsmanager:us-east-1:123456789:secret:myapp/stripe-api-key"
   ```
4. **Use the module** in your controllers:
   ```elixir
   def create(conn, %{"email" => email}) do
     case Backend.Stripe.create_customer(%{email: email}) do
       {:ok, customer} -> json(conn, customer)
       {:error, reason} -> # handle error
     end
   end
   ```

For local development, set the environment variable directly:
```bash
export STRIPE_API_KEY="sk_test_..."
```

To add your own API integrations, see [CONTRIBUTING.md](../CONTRIBUTING.md#adding-api-client-modules).

### TLS/SSL Configuration

The application automatically configures TLS based on the environment:

**Production (ECS)**
- TLS is **enabled by default** for both PostgreSQL and Valkey connections
- The application uses `ssl: true` for all database connections
- Valkey connections use TLS unless explicitly disabled via `VALKEY_SSL=false`

**Local Development**
- TLS is **disabled by default** for local Docker containers
- PostgreSQL and Valkey containers don't require SSL setup

**How It Works**

The detection is based on `MIX_ENV`:
- `MIX_ENV=prod` (ECS): TLS enabled, IAM auth preferred
- `MIX_ENV=dev` (local): TLS disabled, password auth

Configuration is in:
- `app/config/runtime.exs` - Production TLS settings
- `app/config/dev.exs` - Development settings (TLS disabled)

**Customizing TLS**

To disable TLS for Valkey in production (not recommended):
```bash
VALKEY_SSL=false
```

To use custom SSL certificates for PostgreSQL, modify `runtime.exs`:
```elixir
config :backend, Backend.Repo,
  ssl: true,
  ssl_opts: [
    cacertfile: "/path/to/ca-cert.pem",
    verify: :verify_peer,
    server_name_indication: ~c"your-rds-endpoint.rds.amazonaws.com"
  ]
```

### Infrastructure Adjustments

The infrastructure is defined in Terraform under `infra/`. Here's how to make
common modifications.

#### Scaling

Edit `infra/ecs.tf` to adjust ECS scaling:

```hcl
# Minimum and maximum tasks
resource "aws_appautoscaling_target" "ecs_target" {
  min_capacity = 2   # Always run at least 2 tasks
  max_capacity = 20  # Scale up to 20 tasks
}

# CPU scaling threshold
resource "aws_appautoscaling_policy" "ecs_cpu" {
  target_tracking_scaling_policy_configuration {
    target_value = 70.0  # Scale when CPU exceeds 70%
  }
}
```

Edit `infra/rds.tf` to adjust database scaling:

```hcl
resource "aws_rds_cluster" "app" {
  serverlessv2_scaling_configuration {
    min_capacity = 0.5   # Minimum ACUs
    max_capacity = 32.0  # Maximum ACUs
  }
}
```

#### Network

Edit `infra/network.tf` to modify networking:

- Change VPC CIDR blocks
- Add or remove subnets
- Modify security group rules
- Add VPC peering or transit gateways

#### Adding New Secrets

1. Create the secret in Secrets Manager
2. Add a variable in `infra/variables.tf`:
   ```hcl
   variable "my_secret_arn" {
     type    = string
     default = ""
   }
   ```
3. Add to ECS task secrets in `infra/ecs.tf`
4. Add IAM permissions in `infra/iam.tf`
5. Read in `app/config/runtime.exs`

#### Adding New AWS Services

For example, to add SQS:

1. Create `infra/sqs.tf`:
   ```hcl
   resource "aws_sqs_queue" "jobs" {
     name = "${local.name_prefix}-jobs"
     # ... configuration
   }
   ```
2. Add IAM permissions to `infra/iam.tf`
3. Add queue URL to ECS environment in `infra/ecs.tf`
4. Add Elixir client code in `app/lib/backend/`

For detailed infrastructure modification guidance, see [CONTRIBUTING.md](../CONTRIBUTING.md#modifying-aws-infrastructure).

### Mobile-Specific Extensions

Typical additions:

- Push notification workers (APNs, FCM)
- Background job processing (e.g., Oban + SQS)
- Image upload and processing (S3 + Lambda)
- Rate limiting and abuse protection (WAF)
- Real-time features (Phoenix Channels, WebSockets)

### Keep It Maintainable

- Avoid hardcoding product-specific data in shared modules.
- Keep infra changes well documented in `docs/`.
- Prefer environment variables and Secrets Manager for runtime config.
- Follow patterns established in existing code.
- Run `make app-credo` to catch code quality issues.
- Use `make terraform-security` before deploying infrastructure changes.
