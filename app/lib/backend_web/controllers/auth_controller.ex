defmodule BackendWeb.AuthController do
  @moduledoc """
  OAuth authentication controller.

  This controller handles the OAuth 2.0 authentication flow for Google and Apple
  Sign-In using the Ueberauth library. It manages:

  - Initiating OAuth redirects to providers
  - Processing OAuth callbacks
  - Extracting user information from provider responses
  - Establishing user sessions
  - Handling logout

  ## Authentication Flow

  1. User clicks "Login with Google/Apple"
  2. `request/2` redirects to OAuth provider
  3. User authenticates with provider
  4. Provider redirects to `callback/2` with auth code
  5. Ueberauth exchanges code for user info
  6. Session is created with user data
  7. User is redirected to a configurable URL

  ## Session Data

  After successful authentication, the session contains:

      %{
        email: "user@example.com",
        name: "John Doe",
        first_name: "John",
        last_name: "Doe",
        image: "https://...",
        provider: "google",
        provider_uid: "123456789"
      }

  ## Error Handling

  If authentication fails (user cancels, provider error), the user is
  redirected to the configured failure URL.

  ## Configuration

  OAuth credentials are configured in `config/runtime.exs` and pulled
  from environment variables (via Secrets Manager in production).

  Redirects can be customized via:
  - `AUTH_SUCCESS_REDIRECT`
  - `AUTH_FAILURE_REDIRECT`
  - `AUTH_LOGOUT_REDIRECT`
  """

  use Phoenix.Controller, formats: [:html]

  import Plug.Conn

  # Ueberauth plug handles OAuth redirects and callbacks automatically
  plug(Ueberauth)

  @doc """
  Initiates the OAuth authentication flow.

  This action is intercepted by the Ueberauth plug, which redirects the user
  to the OAuth provider's authorization page. The provider is determined
  by the `:provider` path parameter.

  ## Parameters

  - `provider` - OAuth provider name ("google" or "apple")

  ## Example

      GET /auth/google -> Redirects to Google OAuth consent screen
  """
  def request(conn, _params) do
    # Ueberauth plug handles the redirect automatically
    # This function body is only reached if Ueberauth is not configured
    conn
  end

  @doc """
  Handles OAuth callback from provider.

  This function has two clauses:

  1. **Success** (`ueberauth_auth` present): Extracts user info from the auth
     struct and stores it in the session, then redirects to the configured URL.

  2. **Failure** (`ueberauth_failure` present): Redirects to the configured
     failure URL.

  ## Parameters

  - `conn.assigns.ueberauth_auth` - Ueberauth auth struct (on success)
  - `conn.assigns.ueberauth_failure` - Ueberauth failure struct (on failure)

  ## Response

  Redirects to a configurable URL (with session on success, with error on failure).
  """
  def callback(conn, params)

  def callback(%{assigns: %{ueberauth_auth: auth}} = conn, _params) do
    # Extract provider name from the URL path
    provider = extract_provider(conn)

    # Build normalized user info map from provider-specific data
    user_info = %{
      email: auth.info.email,
      # Some providers return full name, others split first/last
      name: auth.info.name || "#{auth.info.first_name} #{auth.info.last_name}" |> String.trim(),
      first_name: auth.info.first_name,
      last_name: auth.info.last_name,
      image: auth.info.image,
      provider: provider,
      provider_uid: auth.uid
    }

    conn
    |> put_session(:current_user, user_info)
    |> redirect(to: success_redirect())
  end

  def callback(%{assigns: %{ueberauth_failure: _failure}} = conn, _params) do
    conn
    |> redirect(to: failure_redirect())
  end

  # Extract provider name from the callback URL
  # URL format: /auth/:provider/callback
  defp extract_provider(conn) do
    conn.request_path
    |> String.split("/")
    |> Enum.at(2, "unknown")
  end

  @doc """
  Logs out the current user.

  Destroys the session, removing all session data including the user info.
  Works with both GET and DELETE HTTP methods for flexibility.

  ## Response

  Redirects to a configurable URL with a clean session.
  """
  def logout(conn, _params) do
    conn
    |> configure_session(drop: true)
    |> redirect(to: logout_redirect())
  end

  defp success_redirect do
    System.get_env("AUTH_SUCCESS_REDIRECT") || "/"
  end

  defp failure_redirect do
    System.get_env("AUTH_FAILURE_REDIRECT") || "/"
  end

  defp logout_redirect do
    System.get_env("AUTH_LOGOUT_REDIRECT") || "/"
  end
end
