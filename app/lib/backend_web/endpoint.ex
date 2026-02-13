defmodule BackendWeb.Endpoint do
  @moduledoc """
  Phoenix Endpoint for the Backend application.

  The endpoint is the entry point for all HTTP requests. It handles:

  - Request/response lifecycle management
  - Plug pipeline for common transformations
  - Session management (via Redis or cookies)
  - Telemetry and request tracking

  ## Request Flow

  1. Request arrives at endpoint
  2. Plug.RequestId assigns unique ID for tracing
  3. Plug.Telemetry emits timing metrics
  4. Plug.Parsers decodes request body
  5. Plug.Session loads/saves session data
  6. Router dispatches to controller

  ## Session Configuration

  Sessions are stored in Redis/Valkey by default (for multi-container support).
  The session store is configured via the `:session_opts` application config.

  Default options:
  - `store: Backend.RedisSessionStore` - Redis-backed sessions
  - `key: "_backend_session"` - Cookie name
  - `signing_salt: "..."` - Salt for cookie signing
  - `namespace: "backend_session"` - Redis key prefix

  ## Configuration

  Endpoint configuration is in `config/runtime.exs`:

      config :backend, BackendWeb.Endpoint,
        url: [host: "example.com", port: 443],
        https: [port: 443, ...]
  """

  use Phoenix.Endpoint, otp_app: :backend

  # Session options - using Redis for session storage by default
  # This enables session persistence across container restarts and load balancing
  # Can be overridden via config :backend, BackendWeb.Endpoint, session_opts: [...]
  @session_opts Application.compile_env(:backend, __MODULE__, [])[:session_opts] ||
                  [
                    store: Backend.RedisSessionStore,
                    key: "_backend_session",
                    signing_salt: "backendSessionSignSalt",
                    namespace: "backend_session"
                  ]

  # ---------------------------------------------------------------------------
  # Plug Pipeline
  # ---------------------------------------------------------------------------
  # These plugs run for every request in order.

  # Assign unique request ID for distributed tracing
  # Available as Logger metadata and in conn.assigns
  plug(Plug.RequestId)

  # Emit telemetry events for request timing
  # Events: [:phoenix, :endpoint, :start] and [:phoenix, :endpoint, :stop]
  plug(Plug.Telemetry, event_prefix: [:phoenix, :endpoint])

  # Parse request bodies based on content-type
  # Supports: application/x-www-form-urlencoded, multipart/form-data, application/json
  parser_length =
    Application.compile_env(:backend, __MODULE__, [])[:max_request_body_bytes] || 2_000_000

  plug(Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"],
    length: parser_length,
    json_decoder: Phoenix.json_library()
  )

  # Support _method parameter for PUT/PATCH/DELETE in forms
  plug(Plug.MethodOverride)

  # Convert HEAD requests to GET (response body discarded)
  plug(Plug.Head)

  # Session management - loads session data from Redis
  plug(Plug.Session, @session_opts)

  # Dispatch to router
  plug(BackendWeb.Router)
end
