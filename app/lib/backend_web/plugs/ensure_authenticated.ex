defmodule BackendWeb.Plugs.EnsureAuthenticated do
  @moduledoc """
  Plug that ensures the request is from an authenticated user.

  This plug checks for a valid user session and halts the request with a
  `401 Unauthorized` response if no user is found. It's used to protect
  API endpoints that require authentication.

  ## Usage

  In the router, add this plug to a pipeline:

      pipeline :protected_api do
        plug :accepts, ["json"]
        plug BackendWeb.Plugs.EnsureAuthenticated
      end

  Or in a specific controller:

      plug BackendWeb.Plugs.EnsureAuthenticated when action in [:create, :update, :delete]

  ## How It Works

  1. Checks `conn` for `:current_user` in session
  2. If present, allows request to continue to controller
  3. If absent, returns `401` JSON error and halts pipeline

  ## Response

  When authentication fails:

      HTTP/1.1 401 Unauthorized
      Content-Type: application/json

      {"error": "Authentication required"}

  ## Notes

  - This plug does NOT perform any database lookup - it only checks the session
  - Session validity is determined by the session store (Redis TTL)
  - For token-based auth, you would extend this to verify JWTs
  """

  import Plug.Conn
  alias BackendWeb.ErrorResponse

  @doc """
  Initialize the plug with options.

  Currently no options are supported, but this follows the Plug convention.

  ## Parameters

  - `opts` - Options passed from the router (unused)

  ## Returns

  The options unchanged.
  """
  def init(opts), do: opts

  @doc """
  Check for authenticated user in session.

  ## Parameters

  - `conn` - The connection struct
  - `_opts` - Options from init/1 (unused)

  ## Returns

  - `conn` unchanged if user is authenticated
  - Halted `conn` with 401 response if not authenticated
  """
  def call(conn, _opts) do
    conn = maybe_fetch_session(conn)

    case get_session(conn, :current_user) do
      nil ->
        # No user in session - reject the request
        conn
        |> ErrorResponse.send(
          :unauthorized,
          "authentication_required",
          "Authentication required"
        )
        |> halt()

      _user ->
        # User is authenticated - continue to controller
        conn
    end
  end

  defp maybe_fetch_session(conn) do
    case conn.private[:plug_session_fetch] do
      :done -> conn
      _ -> fetch_session(conn)
    end
  rescue
    ArgumentError ->
      conn
  end
end
