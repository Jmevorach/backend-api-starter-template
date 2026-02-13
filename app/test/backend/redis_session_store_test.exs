defmodule Backend.RedisSessionStoreTest do
  @moduledoc """
  Tests for the Redis/Valkey session store module.

  These tests verify the Plug.Session.Store behaviour implementation.
  Note: These are unit tests that don't require a running Redis instance.
  """

  use ExUnit.Case, async: true

  alias Backend.RedisSessionStore

  describe "init/1" do
    test "returns default namespace when not provided" do
      result = RedisSessionStore.init([])

      assert result == "session"
    end

    test "returns custom namespace when provided" do
      result = RedisSessionStore.init(namespace: "my_app_session")

      assert result == "my_app_session"
    end

    test "returns custom namespace with atoms" do
      result = RedisSessionStore.init(namespace: :custom_namespace)

      assert result == :custom_namespace
    end
  end

  describe "get/3" do
    test "returns empty session for nil session ID" do
      conn = %Plug.Conn{}

      {sid, data} = RedisSessionStore.get(conn, nil, "session")

      assert sid == nil
      assert data == %{}
    end

    test "returns empty session when Redis not available" do
      # When Redis is not running, command/1 catches the exit
      conn = %Plug.Conn{}

      {sid, data} = RedisSessionStore.get(conn, "nonexistent_sid", "session")

      # Should gracefully return nil/empty when Redis is unavailable
      assert sid == nil
      assert data == %{}
    end
  end

  describe "put/4" do
    test "generates new session ID when sid is nil" do
      conn = %Plug.Conn{}
      data = %{user_id: "123", role: "admin"}

      # This will fail to persist to Redis but should return a generated SID
      sid = RedisSessionStore.put(conn, nil, data, "session")

      # Should generate a base64url-encoded session ID
      assert is_binary(sid)
      assert String.length(sid) > 20
      # Should be URL-safe base64
      assert String.match?(sid, ~r/^[A-Za-z0-9_-]+$/)
    end

    test "returns same session ID when updating existing session" do
      conn = %Plug.Conn{}
      existing_sid = "existing_session_id_123"
      data = %{user_id: "456"}

      # Should return the same SID
      sid = RedisSessionStore.put(conn, existing_sid, data, "session")

      assert sid == existing_sid
    end

    test "generates unique session IDs" do
      conn = %Plug.Conn{}
      data = %{test: true}

      # Generate multiple session IDs
      sids =
        for _ <- 1..100 do
          RedisSessionStore.put(conn, nil, data, "session")
        end

      # All should be unique
      assert length(Enum.uniq(sids)) == 100
    end
  end

  describe "delete/3" do
    test "returns :ok for nil session ID" do
      conn = %Plug.Conn{}

      result = RedisSessionStore.delete(conn, nil, "session")

      assert result == :ok
    end

    test "returns :ok when deleting session" do
      conn = %Plug.Conn{}

      result = RedisSessionStore.delete(conn, "session_to_delete", "session")

      assert result == :ok
    end

    test "returns :ok even when Redis is unavailable" do
      conn = %Plug.Conn{}

      # Should not raise even if Redis is down
      result = RedisSessionStore.delete(conn, "any_session", "session")

      assert result == :ok
    end
  end

  describe "session ID generation" do
    test "generates cryptographically random session IDs" do
      conn = %Plug.Conn{}
      data = %{}

      # Generate session IDs and check for entropy
      sids =
        for _ <- 1..10 do
          RedisSessionStore.put(conn, nil, data, "session")
        end

      # Session IDs should all be different
      assert length(Enum.uniq(sids)) == 10

      # Each should be a reasonable length (32 bytes base64 encoded ~ 43 chars)
      for sid <- sids do
        assert String.length(sid) >= 40
      end
    end
  end

  describe "namespace handling" do
    test "init accepts string namespace" do
      assert RedisSessionStore.init(namespace: "prod_session") == "prod_session"
    end

    test "init accepts empty options" do
      assert RedisSessionStore.init([]) == "session"
    end
  end
end
