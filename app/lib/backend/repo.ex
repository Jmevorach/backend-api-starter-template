defmodule Backend.Repo do
  @moduledoc """
  Ecto Repository for database access with IAM authentication.

  This module provides the interface to PostgreSQL through Ecto. It handles:

  - Connection pooling (configurable via `pool_size`)
  - Query execution and result mapping
  - Transaction management
  - Database migrations
  - **IAM authentication** for RDS Proxy connections
  - **Password fallback** for local development and non-IAM environments

  ## Authentication Modes

  The repo supports multiple authentication modes with the following priority:

  1. **IAM Authentication** (production default): When `DB_IAM_AUTH=true`,
     generates short-lived IAM tokens for RDS Proxy connections.

  2. **Password Authentication** (fallback): When IAM is disabled or fails,
     uses `DB_PASSWORD` if available.

  3. **No Authentication**: For local development without passwords.

  ## Security Lockdown

  In production, set `REQUIRE_IAM_AUTH=true` to disable password fallback.
  This ensures that only IAM authentication is used, providing:

  - No passwords to manage or rotate
  - Credentials tied to IAM role (ECS task role)
  - Short-lived tokens (15 min) auto-generated
  - Better security posture

  ## Configuration

  Database configuration is set in `config/runtime.exs` and includes:

  - `DB_HOST` - Database hostname (RDS Proxy endpoint)
  - `DB_NAME` - Database name
  - `DB_USERNAME` - Database user
  - `DB_PASSWORD` - Database password (optional, for non-IAM environments)
  - `DB_IAM_AUTH` - Enable IAM authentication (true/false)
  - `REQUIRE_IAM_AUTH` - Require IAM auth, disable password fallback (true/false)
  - `AWS_REGION` - AWS region for token generation
  - `DB_POOL_SIZE` - Connection pool size (default: 10)

  ## Usage

      # Query all users
      Backend.Repo.all(User)

      # Insert a record
      Backend.Repo.insert(%User{name: "John"})

      # Run in transaction
      Backend.Repo.transaction(fn ->
        # ... multiple operations
      end)
  """

  use Ecto.Repo,
    otp_app: :backend,
    adapter: Ecto.Adapters.Postgres

  require Logger

  @doc """
  Initialize the repository configuration.

  Handles authentication with the following logic:

  1. If `DB_IAM_AUTH=true`, attempt to generate IAM token
  2. If IAM succeeds, use the token as password
  3. If IAM fails and `REQUIRE_IAM_AUTH=true`, raise an error
  4. If IAM fails/disabled and password is configured, use password
  5. Otherwise, proceed without authentication (local dev)
  """
  @impl true
  def init(_context, config) do
    iam_auth_enabled? = Application.get_env(:backend, :db_iam_auth, false)
    require_iam_auth? = Application.get_env(:backend, :require_iam_auth, false)
    db_password = Application.get_env(:backend, :db_password)

    config = resolve_authentication(config, iam_auth_enabled?, require_iam_auth?, db_password)
    {:ok, config}
  end

  defp resolve_authentication(config, true = _iam_enabled?, require_iam?, db_password) do
    # IAM auth is enabled - try to generate token
    case generate_iam_token(config) do
      {:ok, token} ->
        Keyword.put(config, :password, token)

      {:error, reason} ->
        Logger.error("Failed to generate RDS IAM auth token: #{inspect(reason)}")

        if require_iam? do
          raise """
          IAM authentication is required but token generation failed.

          Error: #{inspect(reason)}

          This can happen if:
          - AWS credentials are not available (check ECS task role)
          - The IAM role doesn't have rds-db:connect permission
          - Network connectivity issues with AWS STS

          Set REQUIRE_IAM_AUTH=false to allow password fallback (not recommended for production).
          """
        else
          # Fall back to password if available
          fallback_to_password(config, db_password)
        end
    end
  end

  defp resolve_authentication(_config, false = _iam_enabled?, true = _require_iam?, _password) do
    # IAM auth required but not enabled - this is a configuration error
    raise """
    IAM authentication is required (REQUIRE_IAM_AUTH=true) but not enabled (DB_IAM_AUTH=false).

    Either:
    - Set DB_IAM_AUTH=true to enable IAM authentication
    - Set REQUIRE_IAM_AUTH=false to allow password authentication
    """
  end

  defp resolve_authentication(config, false = _iam_enabled?, false = _require_iam?, db_password) do
    # IAM auth not enabled, use password if available
    fallback_to_password(config, db_password)
  end

  defp fallback_to_password(config, nil) do
    # No password configured - proceed without (local dev with trust auth)
    Logger.debug("No database password configured, using trust authentication")
    config
  end

  defp fallback_to_password(config, password) when is_binary(password) do
    Logger.debug("Using password authentication for database")
    Keyword.put(config, :password, password)
  end

  defp generate_iam_token(config) do
    hostname = Keyword.get(config, :hostname)
    port = Keyword.get(config, :port, 5432)
    username = Keyword.get(config, :username)
    region = Application.get_env(:backend, :aws_region, "us-east-1")

    case Backend.RdsIamAuth.generate_token(hostname, port, username, region) do
      {:ok, token} ->
        Logger.debug("Generated RDS IAM auth token for #{username}@#{hostname}")
        {:ok, token}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
