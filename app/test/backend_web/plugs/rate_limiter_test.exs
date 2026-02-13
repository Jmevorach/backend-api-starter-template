defmodule BackendWeb.Plugs.RateLimiterTest do
  use ExUnit.Case, async: true

  import Phoenix.ConnTest
  import Plug.Conn

  alias BackendWeb.Plugs.RateLimiter

  setup do
    case :ets.whereis(:backend_rate_limiter) do
      :undefined -> :ok
      table -> :ets.delete(table)
    end

    :ok
  end

  test "allows requests within limit" do
    conn = build_conn(:get, "/api/v1/projects")
    conn = RateLimiter.call(conn, limit: 2, window_seconds: 60)
    refute conn.halted
    assert get_resp_header(conn, "x-ratelimit-limit") == ["2"]
  end

  test "halts when over limit" do
    conn = build_conn(:get, "/api/v1/projects")
    _ = RateLimiter.call(conn, limit: 1, window_seconds: 60)
    blocked = RateLimiter.call(conn, limit: 1, window_seconds: 60)

    assert blocked.halted
    assert blocked.status == 429
  end
end
