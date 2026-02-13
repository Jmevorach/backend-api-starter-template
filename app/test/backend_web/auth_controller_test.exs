defmodule BackendWeb.AuthControllerTest do
  use ExUnit.Case, async: true

  import Phoenix.ConnTest
  import Plug.Conn

  alias BackendWeb.AuthController

  describe "callback/2 with successful auth" do
    test "stores user info in session and redirects to home" do
      # Build a mock Ueberauth auth struct
      auth = %Ueberauth.Auth{
        uid: "123456789",
        info: %Ueberauth.Auth.Info{
          email: "test@example.com",
          name: "Test User",
          first_name: "Test",
          last_name: "User",
          image: "https://example.com/avatar.jpg"
        }
      }

      conn =
        build_conn(:get, "/auth/google/callback")
        |> init_test_session(%{})
        |> assign(:ueberauth_auth, auth)
        |> AuthController.callback(%{})

      # Should redirect to home
      assert redirected_to(conn) == "/"

      # Should store user info in session
      user = get_session(conn, :current_user)
      assert user.email == "test@example.com"
      assert user.name == "Test User"
      assert user.first_name == "Test"
      assert user.last_name == "User"
      assert user.image == "https://example.com/avatar.jpg"
      assert user.provider == "google"
      assert user.provider_uid == "123456789"
    end

    test "handles user with only first/last name (no full name)" do
      auth = %Ueberauth.Auth{
        uid: "987654321",
        info: %Ueberauth.Auth.Info{
          email: "jane@example.com",
          name: nil,
          first_name: "Jane",
          last_name: "Doe",
          image: nil
        }
      }

      conn =
        build_conn(:get, "/auth/apple/callback")
        |> init_test_session(%{})
        |> assign(:ueberauth_auth, auth)
        |> AuthController.callback(%{})

      user = get_session(conn, :current_user)
      assert user.name == "Jane Doe"
      assert user.provider == "apple"
    end
  end

  describe "callback/2 with failed auth" do
    test "redirects to home" do
      failure = %Ueberauth.Failure{
        errors: [%Ueberauth.Failure.Error{message: "User cancelled"}]
      }

      conn =
        build_conn(:get, "/auth/google/callback")
        |> init_test_session(%{})
        |> assign(:ueberauth_failure, failure)
        |> AuthController.callback(%{})

      assert redirected_to(conn) == "/"
    end
  end

  describe "logout/2" do
    test "clears session and redirects to home" do
      conn =
        build_conn(:get, "/auth/logout")
        |> init_test_session(%{current_user: %{email: "test@example.com"}})
        |> AuthController.logout(%{})

      assert redirected_to(conn) == "/"
      # Session should be marked for dropping
      assert conn.private[:plug_session_info] == :drop
    end
  end

  describe "request/2" do
    test "returns conn (Ueberauth handles actual redirect)" do
      conn =
        build_conn(:get, "/auth/google")
        |> init_test_session(%{})
        |> AuthController.request(%{})

      # Without Ueberauth plug, just returns the conn
      assert conn.state == :unset
    end
  end
end
