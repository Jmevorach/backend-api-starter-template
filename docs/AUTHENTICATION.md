# Authentication and Security Guide

This guide covers database and cache authentication, TLS configuration, and security
best practices for the mobile backend baseline.

## Table of Contents

- [Overview](#overview)
- [Database Authentication](#database-authentication)
- [Valkey/Redis Authentication](#valkeyredis-authentication)
- [TLS Configuration](#tls-configuration)
- [Production Security Lockdown](#production-security-lockdown)
- [Local Development Setup](#local-development-setup)
- [Troubleshooting](#troubleshooting)

## Overview

The backend supports multiple authentication modes to balance security and ease of use:

| Mode | Security | Use Case |
|------|----------|----------|
| IAM Authentication | Highest | Production (recommended) |
| Password Authentication | Medium | Development, legacy systems |
| No Authentication | Low | Local development only |

### Authentication Priority

Both database and Valkey follow this priority:

1. **IAM Authentication** (if enabled): Generate short-lived tokens using AWS IAM
2. **Password Fallback** (if IAM fails/disabled): Use configured password
3. **No Authentication** (if no password): Trust-based (local dev only)

## Database Authentication

### IAM Authentication (Recommended for Production)

IAM authentication uses AWS credentials to generate short-lived database tokens,
eliminating the need to manage database passwords.

**Benefits:**
- No passwords to manage or rotate
- Credentials tied to ECS task role
- Short-lived tokens (15 minutes)
- Better audit trail via CloudTrail

**Configuration:**

```bash
# Enable IAM authentication
DB_IAM_AUTH=true

# AWS region for token generation
AWS_REGION=us-east-1

# Database connection (RDS Proxy endpoint)
DB_HOST=my-proxy.proxy-xxx.us-east-1.rds.amazonaws.com
DB_NAME=myapp
DB_USERNAME=app_user
```

**Required IAM Permissions:**

The ECS task role needs `rds-db:connect` permission:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": "rds-db:connect",
      "Resource": "arn:aws:rds-db:us-east-1:123456789:dbuser:cluster-xxx/app_user"
    }
  ]
}
```

### Password Authentication

Password authentication uses a static password stored in Secrets Manager.

**Configuration:**

```bash
# Disable IAM (or leave unset)
DB_IAM_AUTH=false

# Set password
DB_PASSWORD=your_secure_password
```

**Terraform:**

```hcl
# Store password in Secrets Manager
resource "aws_secretsmanager_secret" "db_password" {
  name = "myapp/db-password"
}

# Reference in ECS task
db_password_secret_arn = aws_secretsmanager_secret.db_password.arn
```

### Fallback Behavior

When IAM authentication is enabled but fails (e.g., network issues), the system
can fall back to password authentication:

```
IAM Enabled + Password Set → Try IAM, fall back to password on failure
IAM Enabled + No Password → Try IAM, fail if token generation fails
IAM Disabled + Password Set → Use password only
IAM Disabled + No Password → No authentication (local dev)
```

## Valkey/Redis Authentication

### IAM Authentication

Similar to RDS, ElastiCache supports IAM authentication:

**Configuration:**

```bash
# Enable IAM authentication
VALKEY_IAM_AUTH=true

# Cluster ID for token generation
VALKEY_CLUSTER_ID=my-cluster

# Connection details
VALKEY_HOST=my-cluster.serverless.use1.cache.amazonaws.com
VALKEY_PORT=6379
VALKEY_USER=app_user

# Enable TLS (required for IAM auth)
VALKEY_SSL=true
```

**Required IAM Permissions:**

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": "elasticache:Connect",
      "Resource": [
        "arn:aws:elasticache:us-east-1:123456789:serverlesscache:my-cluster",
        "arn:aws:elasticache:us-east-1:123456789:user:app_user"
      ]
    }
  ]
}
```

### Password Authentication

For environments without IAM support or for development:

```bash
# Disable IAM
VALKEY_IAM_AUTH=false

# Set password
VALKEY_PASSWORD=your_secure_password

# Username (optional, for RBAC)
VALKEY_USER=app_user
```

## TLS Configuration

### Automatic TLS in Production

When running in production (`MIX_ENV=prod`), TLS is automatically enabled:

**Database (PostgreSQL):**
- `ssl: true` is set by default
- Uses `verify: :verify_none` for RDS connections
- No additional configuration needed

**Valkey:**
- TLS enabled by default (`VALKEY_SSL` defaults to `true`)
- Can be explicitly disabled with `VALKEY_SSL=false`
- Required for IAM authentication

### Local Development (TLS Disabled)

In development, TLS is disabled for local Docker containers:

```elixir
# config/dev.exs
config :backend, Backend.Repo,
  ssl: false,
  # ... other config

config :backend, :valkey,
  ssl: false,
  # ... other config
```

### Custom TLS Configuration

For custom certificate verification:

```elixir
# config/runtime.exs
config :backend, Backend.Repo,
  ssl: true,
  ssl_opts: [
    cacertfile: "/path/to/ca-bundle.crt",
    verify: :verify_peer,
    server_name_indication: ~c"your-rds-endpoint.rds.amazonaws.com"
  ]
```

## Production Security Lockdown

### REQUIRE_IAM_AUTH Flag

The `REQUIRE_IAM_AUTH` environment variable enforces IAM-only authentication
in production, preventing password fallback:

```bash
# Strict mode - IAM only, no password fallback
REQUIRE_IAM_AUTH=true
DB_IAM_AUTH=true
VALKEY_IAM_AUTH=true
```

**Behavior when `REQUIRE_IAM_AUTH=true`:**

| Scenario | Result |
|----------|--------|
| IAM enabled + token succeeds | ✅ Connection established |
| IAM enabled + token fails | ❌ Error raised (no fallback) |
| IAM disabled | ❌ Error raised |
| Password configured | Ignored |

**Error Messages:**

If IAM authentication fails with `REQUIRE_IAM_AUTH=true`:

```
** (RuntimeError) IAM authentication is required but token generation failed.

Error: {:error, :credentials_not_available}

This can happen if:
- AWS credentials are not available (check ECS task role)
- The IAM role doesn't have rds-db:connect permission
- Network connectivity issues with AWS STS

Set REQUIRE_IAM_AUTH=false to allow password fallback (not recommended for production).
```

If IAM is disabled but required:

```
** (RuntimeError) IAM authentication is required (REQUIRE_IAM_AUTH=true) but not enabled.

Either:
- Set DB_IAM_AUTH=true to enable IAM authentication
- Set REQUIRE_IAM_AUTH=false to allow password authentication
```

### Recommended Production Configuration

```bash
# Strict IAM mode
REQUIRE_IAM_AUTH=true

# Database - IAM only
DB_IAM_AUTH=true
DB_HOST=proxy.xxx.rds.amazonaws.com
DB_NAME=production
DB_USERNAME=app_user
# DB_PASSWORD not set (or ignored)

# Valkey - IAM only
VALKEY_IAM_AUTH=true
VALKEY_HOST=cluster.serverless.cache.amazonaws.com
VALKEY_USER=app_user
VALKEY_CLUSTER_ID=my-cluster
VALKEY_SSL=true
# VALKEY_PASSWORD not set (or ignored)

# TLS automatically enabled in prod
```

### Terraform Configuration

```hcl
# variables.tf values for production
require_iam_auth = true

# No password secrets needed with IAM-only mode
db_password_secret_arn     = ""  # Not used
valkey_password_secret_arn = ""  # Not used
```

## Local Development Setup

### Docker Compose Configuration

The `compose.yaml` sets up local Postgres and Valkey with password authentication:

```yaml
services:
  db:
    image: postgres:17
    environment:
      POSTGRES_USER: postgres
      POSTGRES_PASSWORD: postgres
      POSTGRES_DB: backend_dev

  valkey:
    image: valkey/valkey:8
    command: valkey-server --requirepass devpassword
```

### Development Configuration

```elixir
# config/dev.exs
config :backend, Backend.Repo,
  username: "postgres",
  password: "postgres",
  database: "backend_dev",
  hostname: "localhost",
  ssl: false

config :backend, :valkey,
  host: "localhost",
  port: 6379,
  password: "devpassword",
  ssl: false,
  iam_auth: false
```

### Starting Local Development

```bash
# Start services
make dev-up

# Run the application
cd app && mix phx.server

# Or with iex
cd app && iex -S mix phx.server
```

## Troubleshooting

### IAM Token Generation Fails

**Symptoms:**
- Error: "Failed to generate RDS IAM auth token"
- Error: "credentials_not_available"

**Solutions:**
1. Verify ECS task role has correct permissions
2. Check AWS region is set correctly
3. Verify network connectivity to AWS STS
4. Check CloudWatch logs for detailed errors

### Database Connection Refused

**Symptoms:**
- Error: "connection refused"
- Error: "timeout"

**Solutions:**
1. Verify security group allows inbound traffic
2. Check DB_HOST is correct (use RDS Proxy endpoint)
3. Verify database is running and accessible
4. Check VPC configuration and routing

### Valkey TLS Errors

**Symptoms:**
- Error: "ssl_error"
- Error: "certificate_verify_failed"

**Solutions:**
1. Ensure `VALKEY_SSL=true` for ElastiCache
2. Verify the endpoint supports TLS
3. For IAM auth, TLS is required
4. Check security group allows port 6379

### Password Authentication Fails

**Symptoms:**
- Error: "authentication failed"
- Error: "invalid password"

**Solutions:**
1. Verify password is correctly set in Secrets Manager
2. Check ECS task can access the secret
3. Verify username matches database user
4. Check for special characters in password (may need escaping)

### REQUIRE_IAM_AUTH Errors

**Symptoms:**
- Application won't start
- Error mentions REQUIRE_IAM_AUTH

**Solutions:**
1. Either enable IAM auth (`DB_IAM_AUTH=true`, `VALKEY_IAM_AUTH=true`)
2. Or disable strict mode (`REQUIRE_IAM_AUTH=false`) for non-production
3. Verify all IAM permissions are configured

### Checking Current Configuration

```elixir
# In IEx console
Application.get_env(:backend, :db_iam_auth)
Application.get_env(:backend, :require_iam_auth)
Application.get_env(:backend, :valkey)
```

### Logs to Check

```bash
# ECS task logs
aws logs tail /ecs/myapp --follow

# Look for:
# - "Using IAM authentication for database"
# - "Using password authentication for database"
# - "Failed to generate RDS IAM auth token"
```
