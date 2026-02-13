defmodule BackendWeb.API.UserControllerTest do
  use ExUnit.Case, async: true

  import Phoenix.ConnTest
  alias BackendWeb.API.UserController

  @endpoint BackendWeb.Endpoint

  describe "GET /api/me" do
    test "returns user data when authenticated" do
      user = %{
        email: "test@example.com",
        name: "Test User",
        first_name: "Test",
        last_name: "User",
        image: "https://example.com/avatar.jpg",
        provider: "google",
        provider_uid: "123456789"
      }

      conn =
        build_conn()
        |> init_test_session(%{current_user: user})
        |> get("/api/me")

      assert conn.status == 200

      response = json_response(conn, 200)
      assert response["authenticated"] == true
      assert response["user"]["email"] == "test@example.com"
      assert response["user"]["name"] == "Test User"
      assert response["user"]["provider"] == "google"
    end

    test "returns 401 when not authenticated" do
      conn =
        build_conn()
        |> init_test_session(%{})
        |> get("/api/me")

      assert conn.status == 401

      response = json_response(conn, 401)
      assert response["error"] == "Authentication required"
    end

    test "returns 401 when session has nil user" do
      conn =
        build_conn()
        |> init_test_session(%{current_user: nil})
        |> get("/api/me")

      assert conn.status == 401
      assert json_response(conn, 401)["error"] == "Authentication required"
    end
  end

  describe "UserController.me/2 direct invocation" do
    test "handles nil session user branch directly" do
      conn =
        build_conn()
        |> init_test_session(%{})

      conn = UserController.me(conn, %{})
      assert conn.status == 401
      assert Jason.decode!(conn.resp_body)["code"] == "authentication_required"
    end
  end
end
