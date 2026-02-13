defmodule BackendWeb.Plugs.RequestLogger do
  @moduledoc """
  Plug for logging HTTP requests with structured metadata.

  This plug captures request details and timing information, logging them
  in a format suitable for analysis and monitoring.

  ## Features

  - Request timing (duration in milliseconds)
  - Request metadata (method, path, status, user agent)
  - User identification (from session)
  - Trace ID propagation

  ## Usage

  Add to your endpoint or router:

      plug BackendWeb.Plugs.RequestLogger

  ## Log Output

  Each request produces a log entry like:

      {
        "message": "GET /api/notes 200 in 15ms",
        "metadata": {
          "request_id": "abc123",
          "method": "GET",
          "path": "/api/notes",
          "status": 200,
          "duration_ms": 15.2,
          "user_id": "user123",
          "user_agent": "Mozilla/5.0..."
        }
      }
  """

  @behaviour Plug

  require Logger

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    start_time = System.monotonic_time()

    # Extract or generate trace ID
    trace_id = get_trace_id(conn)

    # Add metadata for all logs in this request
    Logger.metadata(
      request_id: get_request_id(conn),
      trace_id: trace_id,
      method: conn.method,
      path: conn.request_path
    )

    # Register callback to log after response is sent
    Plug.Conn.register_before_send(conn, fn conn ->
      duration = System.monotonic_time() - start_time
      duration_ms = System.convert_time_unit(duration, :native, :microsecond) / 1000

      log_request(conn, duration_ms)

      conn
    end)
  end

  defp get_request_id(conn) do
    case Plug.Conn.get_resp_header(conn, "x-request-id") do
      [id | _] -> id
      [] -> Ecto.UUID.generate()
    end
  end

  defp get_trace_id(conn) do
    # Check for distributed tracing headers (X-Ray, OpenTelemetry, etc.)
    case Plug.Conn.get_req_header(conn, "x-amzn-trace-id") do
      [trace_id | _] ->
        trace_id

      [] ->
        case Plug.Conn.get_req_header(conn, "traceparent") do
          [trace_id | _] -> trace_id
          [] -> Ecto.UUID.generate()
        end
    end
  end

  defp log_request(conn, duration_ms) do
    status = conn.status
    method = conn.method
    path = conn.request_path

    # Get user ID from session if available
    user_id = get_user_id(conn)

    # Log level based on status code
    level = log_level_for_status(status)

    metadata = [
      status: status,
      duration_ms: Float.round(duration_ms, 2),
      user_id: user_id,
      user_agent: get_user_agent(conn),
      remote_ip: format_remote_ip(conn)
    ]

    Logger.log(level, "#{method} #{path} #{status} in #{round(duration_ms)}ms", metadata)
  end

  defp get_user_id(conn) do
    case Plug.Conn.get_session(conn, :current_user) do
      %{"provider_uid" => uid} -> uid
      %{provider_uid: uid} -> uid
      _ -> nil
    end
  rescue
    _ -> nil
  end

  defp get_user_agent(conn) do
    case Plug.Conn.get_req_header(conn, "user-agent") do
      # Truncate long UAs
      [ua | _] -> String.slice(ua, 0, 200)
      [] -> nil
    end
  end

  defp format_remote_ip(conn) do
    conn.remote_ip
    |> :inet.ntoa()
    |> to_string()
  end

  defp log_level_for_status(status) when status >= 500, do: :error
  defp log_level_for_status(status) when status >= 400, do: :warning
  defp log_level_for_status(_status), do: :info
end
