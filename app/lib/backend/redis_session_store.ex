defmodule Backend.RedisSessionStore do
  @moduledoc """
  Redis/Valkey-backed session store for Plug.Session.

  This module implements the `Plug.Session.Store` behaviour to store session
  data in Redis/Valkey instead of cookies. This provides:

  - **Persistence**: Sessions survive container restarts and rebalancing
  - **Scalability**: Multiple containers can share sessions
  - **Security**: Session data is stored server-side, not in cookies
  - **Size**: No cookie size limits (4KB) for session data

  ## Configuration

  In `endpoint.ex`, configure the session plug:

      plug Plug.Session,
        store: Backend.RedisSessionStore,
        key: "_my_app_session",
        signing_salt: "random_salt",
        namespace: "my_app_session"

  ## Data Storage

  Sessions are stored as Redis keys with format: `{namespace}:{session_id}`

  The session data is serialized using Erlang's `:erlang.term_to_binary/1`
  which safely handles any Elixir data structure.

  ## TTL (Time To Live)

  Sessions expire after 7 days of inactivity. Each `put` operation resets
  the TTL, so active users maintain their session indefinitely.

  ## Graceful Degradation

  If Redis is unavailable, operations fail gracefully:
  - `get` returns empty session (user appears logged out)
  - `put` silently fails (session not persisted)
  - `delete` silently fails (session remains until TTL)
  """

  @behaviour Plug.Session.Store

  # Session TTL: 7 days in seconds
  # Sessions expire after this period of inactivity
  @ttl_seconds 60 * 60 * 24 * 7

  @doc """
  Initialize the session store with options.

  ## Options

  - `:namespace` - Prefix for Redis keys (default: "session")

  ## Returns

  The namespace string to use for key generation.
  """
  @impl true
  def init(opts) do
    Keyword.get(opts, :namespace, "session")
  end

  @doc """
  Retrieve session data from Redis.

  ## Parameters

  - `conn` - The connection (unused but required by behaviour)
  - `sid` - Session ID (cookie value)
  - `namespace` - Key prefix from init/1

  ## Returns

  - `{nil, %{}}` - If session doesn't exist or Redis is unavailable
  - `{sid, data}` - If session exists with its data
  """
  @impl true
  def get(_conn, nil, _namespace), do: {nil, %{}}

  def get(_conn, sid, namespace) do
    key = key(namespace, sid)

    case command(["GET", key]) do
      {:ok, nil} ->
        # Session doesn't exist
        {nil, %{}}

      {:ok, binary} ->
        # Deserialize session data, handling corrupted data gracefully
        data =
          try do
            :erlang.binary_to_term(binary)
          rescue
            _ -> %{}
          end

        {sid, data}

      {:error, _} ->
        # Redis error - return empty session
        {nil, %{}}
    end
  end

  @doc """
  Store session data in Redis.

  ## Parameters

  - `conn` - The connection (unused)
  - `sid` - Session ID (nil to generate new one)
  - `data` - Session data map to store
  - `namespace` - Key prefix from init/1

  ## Returns

  The session ID (existing or newly generated).
  """
  @impl true
  def put(_conn, nil, data, namespace) do
    # No existing session - generate new ID
    sid = generate_sid()
    put_session(sid, data, namespace)
    sid
  end

  def put(_conn, sid, data, namespace) do
    # Update existing session
    put_session(sid, data, namespace)
    sid
  end

  @doc """
  Delete session data from Redis.

  ## Parameters

  - `conn` - The connection (unused)
  - `sid` - Session ID to delete
  - `namespace` - Key prefix from init/1

  ## Returns

  Always returns `:ok` (deletion is best-effort).
  """
  @impl true
  def delete(_conn, nil, _namespace), do: :ok

  def delete(_conn, sid, namespace) do
    key = key(namespace, sid)
    # Fire and forget - don't fail if Redis is down
    _ = command(["DEL", key])
    :ok
  end

  # Store session data with TTL
  defp put_session(sid, data, namespace) do
    key = key(namespace, sid)
    # Serialize data to binary format
    binary = :erlang.term_to_binary(data)

    # SETEX key ttl value - sets key with expiration
    _ = command(["SETEX", key, Integer.to_string(@ttl_seconds), binary])
    :ok
  end

  # Build the full Redis key from namespace and session ID
  defp key(namespace, sid), do: "#{namespace}:#{sid}"

  # Generate a cryptographically secure session ID
  # 32 bytes = 256 bits of entropy, URL-safe base64 encoded
  defp generate_sid do
    32
    |> :crypto.strong_rand_bytes()
    |> Base.url_encode64(padding: false)
  end

  # Execute a Redis command with error handling
  # Catches process exits (e.g., when Redis is not running)
  defp command(args) do
    Redix.command(Backend.Valkey, args)
  catch
    :exit, _ -> {:error, :no_connection}
  end
end
