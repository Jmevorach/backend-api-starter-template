defmodule BackendWeb.RouterTest do
  @moduledoc """
  Tests for router endpoints to improve coverage.
  """

  use Backend.DataCase, async: true

  import Plug.Conn
  import Phoenix.ConnTest

  @endpoint BackendWeb.Endpoint

  describe "public routes" do
    test "GET / returns home page" do
      conn = get(build_conn(), "/")

      assert conn.status == 200
      response = json_response(conn, 200)
      assert response["status"] == "ok"
      assert response["service"] == "backend"
    end

    test "GET /healthz returns health status" do
      conn = get(build_conn(), "/healthz")

      assert conn.status in [200, 503]
      response = json_response(conn, conn.status)
      assert response["status"] in ["ok", "degraded"]
    end

    test "GET /api/openapi returns OpenAPI spec" do
      conn = get(build_conn(), "/api/openapi")

      assert conn.status == 200
      response = json_response(conn, 200)
      assert response["openapi"]
    end

    test "GET /api/docs returns SwaggerUI" do
      conn = get(build_conn(), "/api/docs")

      assert conn.status == 200
      body = response(conn, 200)
      assert body =~ "swagger-ui"
    end
  end

  describe "auth routes" do
    test "GET /auth/google redirects to OAuth provider" do
      conn = get(build_conn(), "/auth/google")

      # Should redirect to Google OAuth
      assert conn.status == 302
      location = get_resp_header(conn, "location") |> hd()
      assert location =~ "accounts.google.com" or location =~ "oauth"
    end

    # Note: /auth/logout is tested in auth_controller_test.exs
    # as it requires calling the controller directly due to
    # Ueberauth plug session requirements
  end

  describe "protected API routes without auth" do
    test "GET /api/me returns 401 without session" do
      conn =
        build_conn()
        |> init_test_session(%{})
        |> get("/api/me")

      assert conn.status == 401
      response = json_response(conn, 401)
      assert response["error"]
    end

    test "GET /api/notes returns 401 without session" do
      conn =
        build_conn()
        |> init_test_session(%{})
        |> get("/api/notes")

      assert conn.status == 401
    end

    test "POST /api/notes returns 401 without session" do
      conn =
        build_conn()
        |> init_test_session(%{})
        |> put_req_header("content-type", "application/json")
        |> post("/api/notes", Jason.encode!(%{title: "Test"}))

      assert conn.status == 401
    end
  end

  describe "protected API routes with auth" do
    setup do
      user = %{
        id: "test_user_123",
        email: "test@example.com",
        provider: "google",
        provider_uid: "google_uid_123"
      }

      {:ok, user: user}
    end

    test "GET /api/me returns user data", %{user: user} do
      conn =
        build_conn()
        |> init_test_session(%{current_user: user})
        |> get("/api/me")

      assert conn.status == 200
      response = json_response(conn, 200)
      assert response["authenticated"] == true
      assert response["user"]["email"] == "test@example.com"
    end

    test "GET /api/notes returns notes list", %{user: user} do
      conn =
        build_conn()
        |> init_test_session(%{current_user: user})
        |> get("/api/notes")

      assert conn.status == 200
      response = json_response(conn, 200)
      assert is_list(response["data"])
      assert is_map(response["meta"])
    end

    test "POST /api/notes creates a note", %{user: user} do
      conn =
        build_conn()
        |> init_test_session(%{current_user: user})
        |> put_req_header("content-type", "application/json")
        |> post("/api/notes", Jason.encode!(%{title: "Test Note", content: "Content"}))

      assert conn.status == 201
      response = json_response(conn, 201)
      assert response["data"]["title"] == "Test Note"
    end

    test "POST /api/notes returns 422 with invalid data", %{user: user} do
      conn =
        build_conn()
        |> init_test_session(%{current_user: user})
        |> put_req_header("content-type", "application/json")
        |> post("/api/notes", Jason.encode!(%{title: ""}))

      assert conn.status == 422
      response = json_response(conn, 422)
      assert response["error"] == "Validation failed"
      assert response["details"]["title"]
    end

    test "GET /api/notes/:id returns a note", %{user: user} do
      # First create a note
      create_conn =
        build_conn()
        |> init_test_session(%{current_user: user})
        |> put_req_header("content-type", "application/json")
        |> post("/api/notes", Jason.encode!(%{title: "Test"}))

      note_id = json_response(create_conn, 201)["data"]["id"]

      # Then fetch it
      conn =
        build_conn()
        |> init_test_session(%{current_user: user})
        |> get("/api/notes/#{note_id}")

      assert conn.status == 200
      response = json_response(conn, 200)
      assert response["data"]["id"] == note_id
    end

    test "GET /api/notes/:id returns 404 for non-existent note", %{user: user} do
      conn =
        build_conn()
        |> init_test_session(%{current_user: user})
        |> get("/api/notes/#{Ecto.UUID.generate()}")

      assert conn.status == 404
    end

    test "PUT /api/notes/:id updates a note", %{user: user} do
      # First create a note
      create_conn =
        build_conn()
        |> init_test_session(%{current_user: user})
        |> put_req_header("content-type", "application/json")
        |> post("/api/notes", Jason.encode!(%{title: "Original"}))

      note_id = json_response(create_conn, 201)["data"]["id"]

      # Then update it
      conn =
        build_conn()
        |> init_test_session(%{current_user: user})
        |> put_req_header("content-type", "application/json")
        |> put("/api/notes/#{note_id}", Jason.encode!(%{title: "Updated"}))

      assert conn.status == 200
      response = json_response(conn, 200)
      assert response["data"]["title"] == "Updated"
    end

    test "DELETE /api/notes/:id deletes a note", %{user: user} do
      # First create a note
      create_conn =
        build_conn()
        |> init_test_session(%{current_user: user})
        |> put_req_header("content-type", "application/json")
        |> post("/api/notes", Jason.encode!(%{title: "To Delete"}))

      note_id = json_response(create_conn, 201)["data"]["id"]

      # Then delete it
      conn =
        build_conn()
        |> init_test_session(%{current_user: user})
        |> delete("/api/notes/#{note_id}")

      assert conn.status == 204
    end

    test "POST /api/notes/:id/archive archives a note", %{user: user} do
      # First create a note
      create_conn =
        build_conn()
        |> init_test_session(%{current_user: user})
        |> put_req_header("content-type", "application/json")
        |> post("/api/notes", Jason.encode!(%{title: "To Archive"}))

      note_id = json_response(create_conn, 201)["data"]["id"]

      # Then archive it
      conn =
        build_conn()
        |> init_test_session(%{current_user: user})
        |> post("/api/notes/#{note_id}/archive")

      assert conn.status == 200
      response = json_response(conn, 200)
      assert response["data"]["archived"] == true
    end

    test "POST /api/notes/:id/unarchive unarchives a note", %{user: user} do
      # First create and archive a note
      create_conn =
        build_conn()
        |> init_test_session(%{current_user: user})
        |> put_req_header("content-type", "application/json")
        |> post("/api/notes", Jason.encode!(%{title: "To Unarchive"}))

      note_id = json_response(create_conn, 201)["data"]["id"]

      build_conn()
      |> init_test_session(%{current_user: user})
      |> post("/api/notes/#{note_id}/archive")

      # Then unarchive it
      conn =
        build_conn()
        |> init_test_session(%{current_user: user})
        |> post("/api/notes/#{note_id}/unarchive")

      assert conn.status == 200
      response = json_response(conn, 200)
      assert response["data"]["archived"] == false
    end
  end

  describe "404 handling" do
    test "unknown route returns 404" do
      conn = get(build_conn(), "/nonexistent/path")

      # Phoenix may return 404 or redirect depending on configuration
      assert conn.status in [404, 302]
    end
  end
end
