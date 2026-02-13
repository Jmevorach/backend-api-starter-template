defmodule BackendWeb.Plugs.EnsureAuthenticatedTest do
  @moduledoc """
  Tests for the EnsureAuthenticated plug.
  """

  use ExUnit.Case, async: true

  import Plug.Conn
  import Phoenix.ConnTest

  alias BackendWeb.Plugs.EnsureAuthenticated

  describe "init/1" do
    test "returns opts unchanged" do
      assert EnsureAuthenticated.init([]) == []
      assert EnsureAuthenticated.init(key: "value") == [key: "value"]
    end
  end

  describe "call/2" do
    test "halts with 401 when no user in session" do
      conn =
        build_conn(:get, "/api/test")
        |> init_test_session(%{})
        |> EnsureAuthenticated.call([])

      assert conn.halted == true
      assert conn.status == 401
      body = json_response(conn, 401)
      assert body["error"] == "Authentication required"
    end

    test "allows request when user is in session" do
      user = %{id: "123", email: "test@example.com"}

      conn =
        build_conn(:get, "/api/test")
        |> init_test_session(%{})
        |> put_session(:current_user, user)
        |> EnsureAuthenticated.call([])

      assert conn.halted == false
      refute conn.status == 401
    end

    test "allows request with minimal user data" do
      conn =
        build_conn(:get, "/api/test")
        |> init_test_session(%{})
        |> put_session(:current_user, %{id: "1"})
        |> EnsureAuthenticated.call([])

      assert conn.halted == false
    end

    test "allows request with string user data" do
      conn =
        build_conn(:get, "/api/test")
        |> init_test_session(%{})
        |> put_session(:current_user, "user_id_string")
        |> EnsureAuthenticated.call([])

      assert conn.halted == false
    end
  end
end
