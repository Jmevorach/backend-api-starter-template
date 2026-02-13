defmodule BackendWeb.HealthControllerTest do
  use ExUnit.Case, async: true

  import Phoenix.ConnTest

  @endpoint BackendWeb.Endpoint

  describe "GET /healthz" do
    test "returns valid JSON response format" do
      conn = get(build_conn(), "/healthz")

      # Should return either 200 (healthy) or 503 (degraded)
      assert conn.status in [200, 503]

      response = json_response(conn, conn.status)
      assert Map.has_key?(response, "status")
      assert response["status"] in ["ok", "degraded"]
    end

    test "returns detailed status when requested" do
      conn = get(build_conn(), "/healthz", detailed: "true")

      # Should return either 200 (healthy) or 503 (degraded)
      assert conn.status in [200, 503]

      response = json_response(conn, conn.status)
      assert Map.has_key?(response, "status")
      assert Map.has_key?(response, "checks")
      assert Map.has_key?(response, "timestamp")

      # Verify checks structure
      checks = response["checks"]
      assert Map.has_key?(checks, "database")
      assert Map.has_key?(checks, "valkey")

      # Each check should have status and message
      for {_name, check} <- checks do
        assert Map.has_key?(check, "status")
        assert Map.has_key?(check, "message")
      end
    end

    test "simple response has no checks or timestamp" do
      conn = get(build_conn(), "/healthz")

      response = json_response(conn, conn.status)

      # Simple response should only have status
      assert Map.has_key?(response, "status")
      # Should NOT have detailed fields
      refute Map.has_key?(response, "checks")
      refute Map.has_key?(response, "timestamp")
    end

    test "detailed=false returns simple response" do
      conn = get(build_conn(), "/healthz", detailed: "false")

      response = json_response(conn, conn.status)
      refute Map.has_key?(response, "checks")
    end

    test "timestamp is valid ISO8601" do
      conn = get(build_conn(), "/healthz", detailed: "true")

      response = json_response(conn, conn.status)
      timestamp = response["timestamp"]

      # Should be valid ISO8601 datetime
      assert {:ok, _, _} = DateTime.from_iso8601(timestamp)
    end

    test "check status values are strings" do
      conn = get(build_conn(), "/healthz", detailed: "true")

      response = json_response(conn, conn.status)

      for {_name, check} <- response["checks"] do
        assert is_binary(check["status"])
        assert check["status"] in ["ok", "error"]
        assert is_binary(check["message"])
      end
    end
  end

  describe "health check responses" do
    test "database check returns connected message when healthy" do
      conn = get(build_conn(), "/healthz", detailed: "true")

      response = json_response(conn, conn.status)

      # If database is connected, should say "connected"
      db_check = response["checks"]["database"]

      if db_check["status"] == "ok" do
        assert db_check["message"] == "connected"
      end
    end

    test "valkey check returns appropriate message" do
      conn = get(build_conn(), "/healthz", detailed: "true")

      response = json_response(conn, conn.status)

      # Valkey check should have a message
      valkey_check = response["checks"]["valkey"]

      assert is_binary(valkey_check["message"])
      # Message could be "connected", "not configured", or an error message
    end
  end
end
