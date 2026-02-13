defmodule BackendWeb.Plugs.RateLimiterTest do
  use ExUnit.Case, async: false

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

  test "uses authenticated session identity when available" do
    conn =
      build_conn(:get, "/api/v1/projects")
      |> init_test_session(%{current_user: %{"provider_uid" => "rate_user_123"}})

    _ = RateLimiter.call(conn, limit: 10, window_seconds: 60)

    entries = :ets.tab2list(:backend_rate_limiter)

    assert Enum.any?(entries, fn
             {{"", _}, _} ->
               false

             {{identity, _bucket}, _count} when is_binary(identity) ->
               String.contains?(identity, "rate_user_123")

             _ ->
               false
           end)
  end

  test "uses x-forwarded-for as identity fallback" do
    conn =
      build_conn(:get, "/api/v1/projects")
      |> put_req_header("x-forwarded-for", "203.0.113.10, 10.0.0.1")

    _ = RateLimiter.call(conn, limit: 10, window_seconds: 60)

    entries = :ets.tab2list(:backend_rate_limiter)

    assert Enum.any?(entries, fn
             {{identity, _bucket}, _count} when is_binary(identity) ->
               String.contains?(identity, "203.0.113.10")

             _ ->
               false
           end)
  end

  test "sets remaining and reset headers on success and failure" do
    conn = build_conn(:get, "/api/v1/projects")
    first = RateLimiter.call(conn, limit: 1, window_seconds: 1)
    second = RateLimiter.call(conn, limit: 1, window_seconds: 1)

    assert get_resp_header(first, "x-ratelimit-remaining") == ["0"]
    assert [_reset] = get_resp_header(first, "x-ratelimit-reset")

    assert second.status == 429
    assert get_resp_header(second, "x-ratelimit-limit") == ["1"]
    assert get_resp_header(second, "x-ratelimit-remaining") == ["0"]
    assert %{"code" => "rate_limit_exceeded"} = Jason.decode!(second.resp_body)
  end

  test "falls back to unknown when remote_ip is missing" do
    conn =
      build_conn(:get, "/api/v1/projects")
      |> Map.put(:remote_ip, nil)

    _ = RateLimiter.call(conn, limit: 10, window_seconds: 60)

    entries = :ets.tab2list(:backend_rate_limiter)

    assert Enum.any?(entries, fn
             {{identity, _bucket}, _count} when is_binary(identity) ->
               String.contains?(identity, "unknown")

             _ ->
               false
           end)
  end

  test "truncates very long identity keys to keep ETS keys bounded" do
    long_path = "/" <> String.duplicate("a", 500)
    conn = build_conn(:get, long_path)

    _ = RateLimiter.call(conn, limit: 10, window_seconds: 60)

    entries = :ets.tab2list(:backend_rate_limiter)

    assert Enum.any?(entries, fn
             {{identity, _bucket}, _count} when is_binary(identity) ->
               byte_size(identity) <= 200

             _ ->
               false
           end)
  end
end
