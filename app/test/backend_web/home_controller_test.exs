defmodule BackendWeb.HomeControllerTest do
  use ExUnit.Case, async: true

  import Phoenix.ConnTest

  @endpoint BackendWeb.Endpoint

  test "GET / returns service metadata" do
    conn = get(build_conn(), "/")

    assert conn.status == 200

    response = json_response(conn, 200)
    assert response["status"] == "ok"
    assert response["service"] == "mobile-backend"
    assert Map.has_key?(response, "version")
    assert Map.has_key?(response, "endpoints")
  end
end
