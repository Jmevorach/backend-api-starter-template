defmodule BackendWeb.API.OpenApiControllerTest do
  @moduledoc """
  Tests for the OpenAPI controller.
  """

  use ExUnit.Case, async: true

  import Plug.Conn
  import Phoenix.ConnTest

  @endpoint BackendWeb.Endpoint

  describe "GET /api/openapi" do
    test "returns OpenAPI spec as JSON" do
      conn = get(build_conn(), "/api/openapi")

      assert conn.status == 200
      assert get_resp_header(conn, "content-type") |> hd() =~ "application/json"

      response = json_response(conn, 200)

      # Verify it's a valid OpenAPI spec
      assert response["openapi"] =~ "3."
      assert response["info"]["title"]
      assert response["paths"]
    end

    test "includes API paths" do
      conn = get(build_conn(), "/api/openapi")
      response = json_response(conn, 200)

      # Should have a paths object (may be empty if no specs defined)
      assert is_map(response["paths"])
    end

    test "includes server information" do
      conn = get(build_conn(), "/api/openapi")
      response = json_response(conn, 200)

      assert is_list(response["servers"]) or response["info"]
    end
  end

  describe "GET /api/docs" do
    test "returns SwaggerUI HTML page" do
      conn = get(build_conn(), "/api/docs")

      assert conn.status == 200
      assert get_resp_header(conn, "content-type") |> hd() =~ "text/html"

      body = response(conn, 200)

      # Verify it contains SwaggerUI elements
      assert body =~ "swagger-ui"
      assert body =~ "SwaggerUIBundle"
      assert body =~ "/api/openapi"
    end

    test "includes proper HTML structure" do
      conn = get(build_conn(), "/api/docs")
      body = response(conn, 200)

      assert body =~ "<!DOCTYPE html>"
      assert body =~ "<html"
      assert body =~ "</html>"
      assert body =~ "<title>"
    end

    test "includes SwaggerUI CSS and JS" do
      conn = get(build_conn(), "/api/docs")
      body = response(conn, 200)

      assert body =~ "swagger-ui.css"
      assert body =~ "swagger-ui-bundle.js"
    end
  end
end
