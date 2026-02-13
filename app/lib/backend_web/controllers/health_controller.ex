defmodule BackendWeb.HealthController do
  @moduledoc """
  Health check endpoint for infrastructure monitoring.

  This controller provides health status information used by:

  - **ALB Target Groups**: Determines if traffic should be routed to this instance
  - **ECS Service**: Decides whether to restart unhealthy containers
  - **Global Accelerator**: Routes traffic away from unhealthy endpoints
  - **Monitoring Systems**: Alerts when services are degraded

  ## Endpoints

  - `GET /healthz` - Quick health check (returns "ok" or "degraded")
  - `GET /healthz?detailed=true` - Detailed component status

  ## Health Checks

  The endpoint checks connectivity to:

  1. **Database (PostgreSQL)**: Executes `SELECT 1` query
  2. **Valkey/Redis**: Sends `PING` command (if configured)

  ## Response Codes

  - `200 OK` - All checks passed
  - `503 Service Unavailable` - One or more checks failed

  ## Response Format

  Simple response:
      {"status": "ok"}

  Detailed response:
      {
        "status": "ok",
        "checks": {
          "database": {"status": "ok", "message": "connected"},
          "valkey": {"status": "ok", "message": "not configured"}
        },
        "timestamp": "2024-01-15T10:30:00Z"
      }

  ## Usage in Infrastructure

  The ALB health check is configured to hit `/healthz` every 30 seconds.
  If 3 consecutive checks fail, the target is marked unhealthy and
  removed from the load balancer rotation.
  """

  use Phoenix.Controller, formats: [:json]

  alias Backend.Repo
  alias Ecto.Adapters.SQL

  @doc """
  Returns health status including database connectivity check.

  ## Parameters

  - `params["detailed"]` - If "true", returns component-level status

  ## Returns

  - `200` with `{"status": "ok"}` if all checks pass
  - `503` with `{"status": "degraded"}` if any check fails
  """
  def index(conn, params) do
    # Determine response detail level
    detailed = params["detailed"] == "true"

    # Run all health checks
    checks = %{
      database: check_database(),
      valkey: check_valkey()
    }

    # Aggregate status - all must be ok for overall health
    all_healthy = Enum.all?(checks, fn {_k, v} -> v.status == :ok end)

    # Build response based on detail level
    response =
      if detailed do
        %{
          status: if(all_healthy, do: "ok", else: "degraded"),
          checks: format_checks(checks),
          timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
        }
      else
        %{status: if(all_healthy, do: "ok", else: "degraded")}
      end

    # Return appropriate HTTP status code
    status_code = if all_healthy, do: 200, else: 503

    conn
    |> put_status(status_code)
    |> json(response)
  end

  # Check database connectivity by executing a simple query
  # Times out after 5 seconds to avoid blocking the health check
  defp check_database do
    case SQL.query(Repo, "SELECT 1", [], timeout: 5_000) do
      {:ok, _result} ->
        %{status: :ok, message: "connected"}

      {:error, error} ->
        %{status: :error, message: Exception.message(error)}
    end
  rescue
    # Handle exceptions (e.g., connection refused)
    e ->
      %{status: :error, message: Exception.message(e)}
  catch
    # Handle process exits (e.g., timeout)
    :exit, reason ->
      %{status: :error, message: inspect(reason)}
  end

  # Check Valkey/Redis connectivity if configured
  # Returns "not configured" status if Valkey is not set up
  defp check_valkey do
    case Process.whereis(Backend.Valkey) do
      nil ->
        # Valkey process not started - this is OK if not configured
        %{status: :ok, message: "not configured"}

      _pid ->
        # Valkey is configured - check connectivity with PING
        case Redix.command(Backend.Valkey, ["PING"], timeout: 5_000) do
          {:ok, "PONG"} ->
            %{status: :ok, message: "connected"}

          {:error, error} ->
            %{status: :error, message: Exception.message(error)}
        end
    end
  rescue
    e ->
      %{status: :error, message: Exception.message(e)}
  catch
    :exit, _ ->
      %{status: :error, message: "connection failed"}
  end

  # Format check results for JSON response
  defp format_checks(checks) do
    Map.new(checks, fn {name, check} ->
      {name, %{status: Atom.to_string(check.status), message: check.message}}
    end)
  end
end
