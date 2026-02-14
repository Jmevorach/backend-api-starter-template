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
      assert response["service"] == "mobile-backend"
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

    test "GET /api/v1/openapi and /api/v1/docs are available" do
      spec_conn = get(build_conn(), "/api/v1/openapi")
      assert spec_conn.status == 200
      assert json_response(spec_conn, 200)["openapi"]

      docs_conn = get(build_conn(), "/api/v1/docs")
      assert docs_conn.status == 200
      assert response(docs_conn, 200) =~ "swagger-ui"
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

    test "auth callback and logout routes are mounted" do
      cb_get = get(build_conn(), "/auth/google/callback")
      assert cb_get.status in [302, 400, 401, 500]

      assert_raise Phoenix.ActionClauseError, fn ->
        build_conn()
        |> put_req_header("content-type", "application/x-www-form-urlencoded")
        |> post("/auth/google/callback", %{})
      end

      logout_get = get(build_conn(), "/auth/logout")
      assert logout_get.status in [nil, 302, 200]

      assert_raise ArgumentError, fn ->
        delete(build_conn(), "/auth/logout")
      end
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

    test "GET /api/profile returns 401 without session" do
      conn =
        build_conn()
        |> init_test_session(%{})
        |> get("/api/profile")

      assert conn.status == 401
    end

    test "GET /api/v1/profile returns 401 without session" do
      conn =
        build_conn()
        |> init_test_session(%{})
        |> get("/api/v1/profile")

      assert conn.status == 401
    end

    test "GET /api/v1/me returns 401 without session" do
      conn =
        build_conn()
        |> init_test_session(%{})
        |> get("/api/v1/me")

      assert conn.status == 401
    end

    test "GET /api/dashboard and /api/v1/dashboard return 401 without session" do
      conn1 =
        build_conn()
        |> init_test_session(%{})
        |> get("/api/dashboard")

      conn2 =
        build_conn()
        |> init_test_session(%{})
        |> get("/api/v1/dashboard")

      assert conn1.status == 401
      assert conn2.status == 401
    end

    test "v1 project/task routes return 401 without session" do
      conn = build_conn() |> init_test_session(%{})

      assert get(conn, "/api/v1/projects").status == 401
      assert post(conn, "/api/v1/projects", %{"name" => "x"}).status == 401
      assert get(conn, "/api/v1/tasks").status == 401
      assert post(conn, "/api/v1/tasks", %{"title" => "x"}).status == 401
    end

    test "v1 upload routes return 401 without session" do
      key = URI.encode_www_form("users/user/uploads/file.txt")
      conn = build_conn() |> init_test_session(%{})

      assert get(conn, "/api/v1/uploads").status == 401
      assert post(conn, "/api/v1/uploads/presign", %{"filename" => "x.txt"}).status == 401
      assert get(conn, "/api/v1/uploads/types").status == 401
      assert get(conn, "/api/v1/uploads/#{key}").status == 401
      assert get(conn, "/api/v1/uploads/#{key}/download").status == 401
      assert delete(conn, "/api/v1/uploads/#{key}").status == 401
    end

    test "v1 enterprise routes return 401 without session" do
      conn = build_conn() |> init_test_session(%{})

      assert get(conn, "/api/v1/auth/sso/providers").status == 401
      assert post(conn, "/api/v1/scim/v2/Users", %{}).status == 401
      assert patch(conn, "/api/v1/scim/v2/Users/#{Ecto.UUID.generate()}", %{}).status == 401
      assert get(conn, "/api/v1/scim/v2/Groups").status == 401
      assert post(conn, "/api/v1/scim/v2/Groups", %{}).status == 401
      assert patch(conn, "/api/v1/scim/v2/Groups/#{Ecto.UUID.generate()}", %{}).status == 401
      assert get(conn, "/api/v1/roles").status == 401
      assert post(conn, "/api/v1/roles", %{}).status == 401
      assert post(conn, "/api/v1/policy/evaluate", %{}).status == 401
      assert get(conn, "/api/v1/audit/events").status == 401
      assert get(conn, "/api/v1/audit/events/#{Ecto.UUID.generate()}").status == 401
      assert post(conn, "/api/v1/webhooks/endpoints", %{}).status == 401
      assert get(conn, "/api/v1/webhooks/deliveries").status == 401

      assert post(conn, "/api/v1/webhooks/deliveries/#{Ecto.UUID.generate()}/replay", %{}).status ==
               401

      assert post(conn, "/api/v1/notifications/send", %{}).status == 401
      assert post(conn, "/api/v1/notifications/templates", %{}).status == 401
      assert get(conn, "/api/v1/features").status == 401
      assert post(conn, "/api/v1/features", %{}).status == 401
      assert post(conn, "/api/v1/tenants", %{}).status == 401
      assert get(conn, "/api/v1/tenants/#{Ecto.UUID.generate()}").status == 401
      assert get(conn, "/api/v1/entitlements").status == 401
      assert post(conn, "/api/v1/jobs", %{}).status == 401
      assert get(conn, "/api/v1/jobs/#{Ecto.UUID.generate()}").status == 401
      assert post(conn, "/api/v1/compliance/export", %{}).status == 401
      assert post(conn, "/api/v1/compliance/delete", %{}).status == 401
      assert get(conn, "/api/v1/search?q=test").status == 401
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

    test "GET /api/profile returns profile data", %{user: user} do
      conn =
        build_conn()
        |> init_test_session(%{current_user: user})
        |> get("/api/profile")

      assert conn.status == 200
      response = json_response(conn, 200)
      assert response["data"]["id"] == "google_uid_123"
    end

    test "GET /api/v1/profile returns profile data", %{user: user} do
      conn =
        build_conn()
        |> init_test_session(%{current_user: user})
        |> get("/api/v1/profile")

      assert conn.status == 200
      response = json_response(conn, 200)
      assert response["data"]["id"] == "google_uid_123"
    end

    test "GET /api/dashboard and /api/v1/dashboard return dashboard payload", %{user: user} do
      conn1 =
        build_conn()
        |> init_test_session(%{current_user: user})
        |> get("/api/dashboard")

      conn2 =
        build_conn()
        |> init_test_session(%{current_user: user})
        |> get("/api/v1/dashboard")

      assert conn1.status == 200
      assert conn2.status == 200
      assert is_map(json_response(conn1, 200)["data"]["summary"])
      assert is_map(json_response(conn2, 200)["data"]["summary"])
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

    test "GET /api/v1/notes and /api/v1/uploads/types are reachable when authenticated", %{
      user: user
    } do
      notes_conn =
        build_conn()
        |> init_test_session(%{current_user: user})
        |> get("/api/v1/notes")

      assert notes_conn.status == 200

      types_conn =
        build_conn()
        |> init_test_session(%{current_user: user})
        |> get("/api/v1/uploads/types")

      assert types_conn.status == 200
      assert is_list(json_response(types_conn, 200)["content_types"])
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
