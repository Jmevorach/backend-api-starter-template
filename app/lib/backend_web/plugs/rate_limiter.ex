defmodule BackendWeb.Plugs.RateLimiter do
  @moduledoc """
  Lightweight in-memory rate limiter for API endpoints.

  Uses ETS counters per identity + time window.
  """

  @behaviour Plug

  import Plug.Conn

  alias BackendWeb.ErrorResponse

  @table :backend_rate_limiter
  @default_limit 120
  @default_window_seconds 60

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, opts) do
    ensure_table!()

    limit = Keyword.get(opts, :limit, @default_limit)
    window_seconds = Keyword.get(opts, :window_seconds, @default_window_seconds)

    identity = conn |> identity_key() |> truncate_key()
    bucket = current_bucket(window_seconds)
    key = {identity, bucket}

    count = :ets.update_counter(@table, key, {2, 1}, {key, 0})
    expires_at = System.system_time(:second) + window_seconds
    true = :ets.insert(@table, {{:expires, key}, expires_at})

    prune_expired()

    conn =
      conn
      |> put_resp_header("x-ratelimit-limit", Integer.to_string(limit))
      |> put_resp_header("x-ratelimit-remaining", Integer.to_string(max(limit - count, 0)))
      |> put_resp_header(
        "x-ratelimit-reset",
        Integer.to_string(window_reset_epoch(window_seconds))
      )

    if count > limit do
      conn
      |> ErrorResponse.send(
        :too_many_requests,
        "rate_limit_exceeded",
        "Too many requests",
        %{limit: limit, window_seconds: window_seconds}
      )
      |> halt()
    else
      conn
    end
  end

  defp ensure_table! do
    case :ets.whereis(@table) do
      :undefined ->
        try do
          _ =
            :ets.new(@table, [
              :named_table,
              :set,
              :public,
              read_concurrency: true,
              write_concurrency: true
            ])
        rescue
          ArgumentError -> :ok
        end

        :ok

      _ ->
        :ok
    end
  end

  defp identity_key(conn) do
    user =
      if session_fetched?(conn) do
        get_session(conn, :current_user) || %{}
      else
        %{}
      end

    user_id =
      user["provider_uid"] || user[:provider_uid] || user["id"] || user[:id] ||
        first_header(conn, "x-forwarded-for") || ip(conn.remote_ip)

    "#{conn.request_path}:#{user_id}"
  end

  defp session_fetched?(conn) do
    conn.private[:plug_session_fetch] == :done
  end

  defp truncate_key(key) when byte_size(key) > 200 do
    binary_part(key, 0, 200)
  end

  defp truncate_key(key), do: key

  defp first_header(conn, name) do
    case get_req_header(conn, name) do
      [value | _] -> String.split(value, ",") |> List.first() |> String.trim()
      _ -> nil
    end
  end

  defp ip(tuple) when is_tuple(tuple), do: tuple |> Tuple.to_list() |> Enum.join(".")
  defp ip(_), do: "unknown"

  defp current_bucket(window_seconds) do
    System.system_time(:second)
    |> Kernel.div(window_seconds)
  end

  defp window_reset_epoch(window_seconds) do
    (current_bucket(window_seconds) + 1) * window_seconds
  end

  defp prune_expired do
    now = System.system_time(:second)

    for {{:expires, key}, expires_at} <- :ets.match_object(@table, {{:expires, :_}, :_}),
        expires_at < now do
      :ets.delete(@table, {:expires, key})
      :ets.delete(@table, key)
    end
  end
end
