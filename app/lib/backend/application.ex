defmodule Backend.Application do
  @moduledoc """
  OTP Application module for the Backend.

  This module is the entry point for the application and is responsible for
  starting and supervising all child processes. The supervision tree includes:

  - `Backend.Repo` - Ecto database connection pool (IAM or password auth)
  - `Phoenix.PubSub` - PubSub system for real-time features
  - `BackendWeb.Endpoint` - Phoenix HTTP endpoint
  - `Backend.ValkeyConnection` (optional) - Valkey connection with IAM or password auth

  ## Authentication Modes

  Both database and Valkey support multiple authentication modes:

  1. **IAM Authentication** (production default): Uses short-lived tokens
  2. **Password Authentication** (fallback): Uses configured passwords
  3. **No Authentication** (local dev): For local Docker containers

  Set `REQUIRE_IAM_AUTH=true` in production to disable password fallback.

  ## Configuration

  Environment variables (set via ECS task definition):

  - `VALKEY_HOST` - ElastiCache Serverless endpoint
  - `VALKEY_PORT` - Port (default 6379)
  - `VALKEY_USER` - Username for RBAC
  - `VALKEY_PASSWORD` - Password (optional, for non-IAM environments)
  - `VALKEY_IAM_AUTH` - Enable IAM auth (true/false)
  - `VALKEY_SSL` - Enable SSL (default true, set to "false" to disable)
  """

  use Application

  require Logger

  @impl true
  def start(_type, _args) do
    # Build the supervision tree with required and optional children
    children =
      [
        # Database connection pool - handles PostgreSQL via Ecto with IAM auth
        Backend.Repo,
        # PubSub system for Phoenix channels and LiveView
        {Phoenix.PubSub, name: Backend.PubSub},
        # HTTP endpoint - starts the web server
        BackendWeb.Endpoint
      ] ++ valkey_children()

    # Start supervisor with one-for-one strategy:
    # If a child crashes, only that child is restarted
    opts = [strategy: :one_for_one, name: Backend.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Returns the Valkey/Redis child spec if configured, otherwise empty list
  defp valkey_children do
    config = Application.get_env(:backend, :valkey)

    case config do
      nil ->
        # Valkey not configured - sessions will not persist
        []

      config ->
        host = Keyword.get(config, :host)
        port = Keyword.get(config, :port, 6379)
        username = Keyword.get(config, :username)
        password = Keyword.get(config, :password)
        ssl = Keyword.get(config, :ssl, true)
        iam_auth = Keyword.get(config, :iam_auth, false)

        # Build Redix connection options
        opts = [
          name: Backend.Valkey,
          host: host,
          port: port,
          ssl: ssl,
          socket_opts: if(ssl, do: [verify: :verify_none], else: [])
        ]

        # Add authentication (IAM or password)
        opts = resolve_valkey_auth(opts, config, username, password, iam_auth)

        # Return child spec for Redix process
        [{Redix, opts}]
    end
  end

  # Resolve Valkey authentication: IAM > Password > No auth
  defp resolve_valkey_auth(opts, config, username, password, true = _iam_auth) do
    cluster_id = Keyword.get(config, :cluster_id)
    region = Application.get_env(:backend, :aws_region, "us-east-1")
    require_iam_auth? = Application.get_env(:backend, :require_iam_auth, false)

    case Backend.ElasticacheIamAuth.generate_token(cluster_id, username, region) do
      {:ok, token} ->
        Logger.debug("Using IAM authentication for Valkey")

        opts
        |> Keyword.put(:username, username)
        |> Keyword.put(:password, token)

      {:error, reason} ->
        Logger.error("Failed to generate Valkey IAM auth token: #{inspect(reason)}")

        if require_iam_auth? do
          raise """
          IAM authentication is required but Valkey token generation failed.

          Error: #{inspect(reason)}

          Set REQUIRE_IAM_AUTH=false to allow password fallback (not recommended for production).
          """
        else
          # Fall back to password if available
          fallback_to_valkey_password(opts, username, password)
        end
    end
  end

  defp resolve_valkey_auth(opts, _config, username, password, false = _iam_auth) do
    require_iam_auth? = Application.get_env(:backend, :require_iam_auth, false)

    if require_iam_auth? do
      raise """
      IAM authentication is required (REQUIRE_IAM_AUTH=true) but VALKEY_IAM_AUTH is not enabled.

      Either:
      - Set VALKEY_IAM_AUTH=true to enable IAM authentication
      - Set REQUIRE_IAM_AUTH=false to allow password authentication
      """
    else
      fallback_to_valkey_password(opts, username, password)
    end
  end

  defp fallback_to_valkey_password(opts, _username, nil) do
    Logger.debug("No Valkey password configured, connecting without authentication")
    opts
  end

  defp fallback_to_valkey_password(opts, username, password) when is_binary(password) do
    Logger.debug("Using password authentication for Valkey")

    opts =
      if username do
        Keyword.put(opts, :username, username)
      else
        opts
      end

    Keyword.put(opts, :password, password)
  end

  @impl true
  def config_change(changed, _new, removed) do
    # Notify the endpoint of configuration changes (for hot code reloading)
    BackendWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
