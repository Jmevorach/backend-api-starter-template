defmodule BackendWeb.API.UserController do
  @moduledoc """
  User API controller for retrieving current user information.

  This controller provides a JSON API endpoint for clients to retrieve
  information about the currently authenticated user. It's typically used by:

  - Mobile apps checking authentication status
  - SPAs loading user profile data
  - API clients verifying session validity

  ## Authentication

  This endpoint is protected by the `EnsureAuthenticated` plug via the
  `:protected_api` pipeline in the router.

  ## Response Format

  Authenticated:
      {
        "user": {
          "email": "user@example.com",
          "name": "John Doe",
          "provider": "google",
          ...
        },
        "authenticated": true
      }

  Unauthenticated:
      {
        "error": "Authentication required"
      }
  """

  use Phoenix.Controller, formats: [:json]

  import Plug.Conn
  alias BackendWeb.ErrorResponse

  @doc """
  Returns the current user's information.

  ## Response

  - `200 OK` with user data if authenticated
  - `401 Unauthorized` if not authenticated (handled by the plug)

  ## Example Request

      GET /api/me
      Cookie: _backend_session=...

  ## Example Response (authenticated)

      {
        "user": {
          "email": "john@example.com",
          "name": "John Doe",
          "first_name": "John",
          "last_name": "Doe",
          "image": "https://...",
          "provider": "google",
          "provider_uid": "123456789"
        },
        "authenticated": true
      }

  ## Example Response (unauthenticated)

      {
        "error": "Not authenticated"
      }
  """
  def me(conn, _params) do
    # Get user from session (set during OAuth callback)
    user = get_session(conn, :current_user)

    case user do
      nil ->
        # No user in session - not authenticated
        conn
        |> ErrorResponse.send(
          :unauthorized,
          "authentication_required",
          "Authentication required"
        )

      user ->
        # Return user info with authentication flag
        json(conn, %{
          user: user,
          authenticated: true
        })
    end
  end
end
