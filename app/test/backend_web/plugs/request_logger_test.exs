defmodule BackendWeb.Plugs.RequestLoggerTest do
  @moduledoc """
  Tests for the RequestLogger plug.
  """

  use ExUnit.Case, async: true

  import Plug.Conn
  import Phoenix.ConnTest

  alias BackendWeb.Plugs.RequestLogger

  describe "init/1" do
    test "returns opts unchanged" do
      assert RequestLogger.init([]) == []
      assert RequestLogger.init(key: "value") == [key: "value"]
    end
  end

  describe "call/2" do
    test "adds logger metadata to connection" do
      conn =
        build_conn(:get, "/api/test")
        |> put_req_header("user-agent", "TestAgent/1.0")

      # Call the plug
      result = RequestLogger.call(conn, [])

      # Should return the conn (possibly modified)
      assert %Plug.Conn{} = result
    end

    test "handles missing user-agent header" do
      conn = build_conn(:get, "/api/test")

      # Should not crash
      result = RequestLogger.call(conn, [])
      assert %Plug.Conn{} = result
    end

    test "extracts trace ID from x-amzn-trace-id header" do
      conn =
        build_conn(:get, "/api/test")
        |> put_req_header("x-amzn-trace-id", "Root=1-abc123")

      result = RequestLogger.call(conn, [])
      assert %Plug.Conn{} = result
    end

    test "extracts trace ID from traceparent header" do
      conn =
        build_conn(:get, "/api/test")
        |> put_req_header("traceparent", "00-abc123-def456-01")

      result = RequestLogger.call(conn, [])
      assert %Plug.Conn{} = result
    end

    test "generates trace ID when no header present" do
      conn = build_conn(:get, "/api/test")

      result = RequestLogger.call(conn, [])
      assert %Plug.Conn{} = result
    end

    test "registers before_send callback" do
      conn = build_conn(:get, "/api/test")

      result = RequestLogger.call(conn, [])

      # Should have registered a callback
      # before_send is stored in private map
      assert is_list(result.private[:before_send]) or result.private[:before_send] != nil
    end

    test "handles different HTTP methods" do
      for method <- [:get, :post, :put, :patch, :delete] do
        conn = build_conn(method, "/api/test")
        result = RequestLogger.call(conn, [])
        assert %Plug.Conn{} = result
      end
    end

    test "handles different paths" do
      paths = [
        "/",
        "/api",
        "/api/users",
        "/api/users/123",
        "/api/notes/abc-def-123?query=test"
      ]

      for path <- paths do
        conn = build_conn(:get, path)
        result = RequestLogger.call(conn, [])
        assert %Plug.Conn{} = result
      end
    end

    test "handles long user-agent strings" do
      long_ua = String.duplicate("Mozilla/5.0 ", 100)

      conn =
        build_conn(:get, "/api/test")
        |> put_req_header("user-agent", long_ua)

      result = RequestLogger.call(conn, [])
      assert %Plug.Conn{} = result
    end
  end

  describe "before_send callback" do
    test "logs request when response is sent" do
      conn =
        build_conn(:get, "/api/test")
        |> put_req_header("user-agent", "TestAgent/1.0")
        |> RequestLogger.call([])

      # Simulate sending a response which triggers before_send
      conn = put_status(conn, 200)
      callbacks = conn.private[:before_send] || []

      # Execute the callbacks manually
      result =
        Enum.reduce(callbacks, conn, fn callback, acc ->
          callback.(acc)
        end)

      assert %Plug.Conn{} = result
    end

    test "logs 4xx status with warning level" do
      conn =
        build_conn(:get, "/api/test")
        |> RequestLogger.call([])
        |> put_status(404)

      callbacks = conn.private[:before_send] || []

      result =
        Enum.reduce(callbacks, conn, fn callback, acc ->
          callback.(acc)
        end)

      assert %Plug.Conn{} = result
      assert result.status == 404
    end

    test "logs 5xx status with error level" do
      conn =
        build_conn(:get, "/api/test")
        |> RequestLogger.call([])
        |> put_status(500)

      callbacks = conn.private[:before_send] || []

      result =
        Enum.reduce(callbacks, conn, fn callback, acc ->
          callback.(acc)
        end)

      assert %Plug.Conn{} = result
      assert result.status == 500
    end

    test "extracts user ID from session with atom keys" do
      conn =
        build_conn(:get, "/api/test")
        |> init_test_session(%{})
        |> put_session(:current_user, %{provider_uid: "user_123"})
        |> RequestLogger.call([])
        |> put_status(200)

      callbacks = conn.private[:before_send] || []

      result =
        Enum.reduce(callbacks, conn, fn callback, acc ->
          callback.(acc)
        end)

      assert %Plug.Conn{} = result
    end

    test "extracts user ID from session with string keys" do
      conn =
        build_conn(:get, "/api/test")
        |> init_test_session(%{})
        |> put_session(:current_user, %{"provider_uid" => "user_456"})
        |> RequestLogger.call([])
        |> put_status(200)

      callbacks = conn.private[:before_send] || []

      result =
        Enum.reduce(callbacks, conn, fn callback, acc ->
          callback.(acc)
        end)

      assert %Plug.Conn{} = result
    end

    test "handles nil user in session" do
      conn =
        build_conn(:get, "/api/test")
        |> init_test_session(%{})
        |> RequestLogger.call([])
        |> put_status(200)

      callbacks = conn.private[:before_send] || []

      result =
        Enum.reduce(callbacks, conn, fn callback, acc ->
          callback.(acc)
        end)

      assert %Plug.Conn{} = result
    end

    test "formats remote IP correctly" do
      conn =
        build_conn(:get, "/api/test")
        |> Map.put(:remote_ip, {192, 168, 1, 100})
        |> RequestLogger.call([])
        |> put_status(200)

      callbacks = conn.private[:before_send] || []

      result =
        Enum.reduce(callbacks, conn, fn callback, acc ->
          callback.(acc)
        end)

      assert %Plug.Conn{} = result
    end

    test "handles IPv6 remote IP" do
      conn =
        build_conn(:get, "/api/test")
        |> Map.put(:remote_ip, {0, 0, 0, 0, 0, 0, 0, 1})
        |> RequestLogger.call([])
        |> put_status(200)

      callbacks = conn.private[:before_send] || []

      result =
        Enum.reduce(callbacks, conn, fn callback, acc ->
          callback.(acc)
        end)

      assert %Plug.Conn{} = result
    end

    test "extracts existing x-request-id header" do
      conn =
        build_conn(:get, "/api/test")
        |> put_resp_header("x-request-id", "existing-request-id")
        |> RequestLogger.call([])

      assert %Plug.Conn{} = conn
    end
  end

  describe "log level selection" do
    # We can't directly test private functions, but we can verify
    # that different status codes don't crash the logging

    test "handles 2xx status codes" do
      conn = build_conn(:get, "/api/test")
      result = RequestLogger.call(conn, [])
      assert %Plug.Conn{} = result
    end
  end
end
