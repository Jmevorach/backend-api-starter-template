defmodule Backend.ElasticacheIamAuthTest do
  @moduledoc """
  Tests for ElastiCache IAM authentication token generation.

  These tests verify:
  - Token format and structure
  - AWS SigV4 signing process for ElastiCache
  - Credential handling from environment
  - Error handling
  """

  use ExUnit.Case, async: false

  alias Backend.ElasticacheIamAuth

  # Store original env vars and restore after each test
  setup do
    original_access_key = System.get_env("AWS_ACCESS_KEY_ID")
    original_secret_key = System.get_env("AWS_SECRET_ACCESS_KEY")
    original_session_token = System.get_env("AWS_SESSION_TOKEN")
    original_container_uri = System.get_env("AWS_CONTAINER_CREDENTIALS_RELATIVE_URI")

    on_exit(fn ->
      if original_access_key,
        do: System.put_env("AWS_ACCESS_KEY_ID", original_access_key),
        else: System.delete_env("AWS_ACCESS_KEY_ID")

      if original_secret_key,
        do: System.put_env("AWS_SECRET_ACCESS_KEY", original_secret_key),
        else: System.delete_env("AWS_SECRET_ACCESS_KEY")

      if original_session_token,
        do: System.put_env("AWS_SESSION_TOKEN", original_session_token),
        else: System.delete_env("AWS_SESSION_TOKEN")

      if original_container_uri,
        do: System.put_env("AWS_CONTAINER_CREDENTIALS_RELATIVE_URI", original_container_uri),
        else: System.delete_env("AWS_CONTAINER_CREDENTIALS_RELATIVE_URI")
    end)

    :ok
  end

  describe "generate_token/3" do
    test "generates valid token format with environment credentials" do
      System.put_env("AWS_ACCESS_KEY_ID", "AKIAIOSFODNN7EXAMPLE")
      System.put_env("AWS_SECRET_ACCESS_KEY", "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY")
      System.delete_env("AWS_SESSION_TOKEN")

      cluster_id = "my-cache"
      username = "app_user"
      region = "us-east-1"

      result = ElasticacheIamAuth.generate_token(cluster_id, username, region)

      assert {:ok, token} = result
      assert String.starts_with?(token, "#{cluster_id}/")
      assert String.contains?(token, "Action=connect")
      assert String.contains?(token, "User=#{username}")
      assert String.contains?(token, "X-Amz-Algorithm=AWS4-HMAC-SHA256")
      assert String.contains?(token, "X-Amz-Credential=AKIAIOSFODNN7EXAMPLE")
      assert String.contains?(token, "X-Amz-Expires=900")
      assert String.contains?(token, "X-Amz-Signature=")
    end

    test "includes session token when provided" do
      System.put_env("AWS_ACCESS_KEY_ID", "AKIAIOSFODNN7EXAMPLE")
      System.put_env("AWS_SECRET_ACCESS_KEY", "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY")
      System.put_env("AWS_SESSION_TOKEN", "FwoGZXIvYXdzEBYaDK...")

      result = ElasticacheIamAuth.generate_token("cache", "user", "us-east-1")

      assert {:ok, token} = result
      assert String.contains?(token, "X-Amz-Security-Token=")
    end

    test "token contains correct region in credential scope" do
      System.put_env("AWS_ACCESS_KEY_ID", "AKIAIOSFODNN7EXAMPLE")
      System.put_env("AWS_SECRET_ACCESS_KEY", "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY")

      for region <- ["us-east-1", "us-west-2", "eu-west-1", "ap-southeast-1"] do
        result = ElasticacheIamAuth.generate_token("cache", "user", region)

        assert {:ok, token} = result
        # ElastiCache uses "elasticache" service name
        assert String.contains?(token, "/#{region}/elasticache/aws4_request")
      end
    end

    test "handles different cluster IDs" do
      System.put_env("AWS_ACCESS_KEY_ID", "AKIAIOSFODNN7EXAMPLE")
      System.put_env("AWS_SECRET_ACCESS_KEY", "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY")

      for cluster_id <- [
            "my-cache",
            "production-valkey",
            "test-cluster-123",
            "cache-with-dashes"
          ] do
        result = ElasticacheIamAuth.generate_token(cluster_id, "user", "us-east-1")

        assert {:ok, token} = result
        assert String.starts_with?(token, "#{cluster_id}/")
      end
    end

    test "handles different usernames" do
      System.put_env("AWS_ACCESS_KEY_ID", "AKIAIOSFODNN7EXAMPLE")
      System.put_env("AWS_SECRET_ACCESS_KEY", "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY")

      for username <- ["app_user", "admin", "default", "cache_user"] do
        result = ElasticacheIamAuth.generate_token("cache", username, "us-east-1")

        assert {:ok, token} = result
        assert String.contains?(token, "User=#{username}")
      end
    end

    test "returns error when no credentials available" do
      System.delete_env("AWS_ACCESS_KEY_ID")
      System.delete_env("AWS_SECRET_ACCESS_KEY")
      System.delete_env("AWS_CONTAINER_CREDENTIALS_RELATIVE_URI")

      result = ElasticacheIamAuth.generate_token("cache", "user", "us-east-1")

      assert {:error, _reason} = result
    end
  end

  describe "querystring parameters" do
    test "parameters are sorted alphabetically" do
      System.put_env("AWS_ACCESS_KEY_ID", "AKIAIOSFODNN7EXAMPLE")
      System.put_env("AWS_SECRET_ACCESS_KEY", "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY")

      {:ok, token} = ElasticacheIamAuth.generate_token("cache", "user", "us-east-1")

      # Extract querystring (everything after ?)
      [_, querystring] = String.split(token, "?", parts: 2)
      params = String.split(querystring, "&") |> Enum.map(&(String.split(&1, "=") |> hd()))

      # Verify params are sorted (excluding signature which is added at end)
      params_without_sig = Enum.filter(params, &(&1 != "X-Amz-Signature"))
      assert params_without_sig == Enum.sort(params_without_sig)
    end

    test "uses User parameter instead of DBUser" do
      System.put_env("AWS_ACCESS_KEY_ID", "AKIAIOSFODNN7EXAMPLE")
      System.put_env("AWS_SECRET_ACCESS_KEY", "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY")

      {:ok, token} = ElasticacheIamAuth.generate_token("cache", "myuser", "us-east-1")

      # ElastiCache uses "User" not "DBUser"
      assert String.contains?(token, "User=myuser")
      refute String.contains?(token, "DBUser=")
    end
  end

  describe "signature generation" do
    test "signature is 64 character lowercase hex string" do
      System.put_env("AWS_ACCESS_KEY_ID", "AKIAIOSFODNN7EXAMPLE")
      System.put_env("AWS_SECRET_ACCESS_KEY", "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY")

      {:ok, token} = ElasticacheIamAuth.generate_token("cache", "user", "us-east-1")

      [signature] = Regex.run(~r/X-Amz-Signature=([a-f0-9]+)/, token, capture: :all_but_first)

      # SHA256 HMAC produces 32 bytes = 64 hex characters
      assert String.length(signature) == 64
      assert String.match?(signature, ~r/^[a-f0-9]+$/)
    end

    test "different inputs produce different signatures" do
      System.put_env("AWS_ACCESS_KEY_ID", "AKIAIOSFODNN7EXAMPLE")
      System.put_env("AWS_SECRET_ACCESS_KEY", "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY")

      {:ok, token1} = ElasticacheIamAuth.generate_token("cache1", "user", "us-east-1")
      {:ok, token2} = ElasticacheIamAuth.generate_token("cache2", "user", "us-east-1")

      sig1 = Regex.run(~r/X-Amz-Signature=([^&]+)/, token1) |> List.last()
      sig2 = Regex.run(~r/X-Amz-Signature=([^&]+)/, token2) |> List.last()

      refute sig1 == sig2
    end

    test "different secret keys produce different signatures" do
      System.put_env("AWS_ACCESS_KEY_ID", "AKIAIOSFODNN7EXAMPLE")

      System.put_env("AWS_SECRET_ACCESS_KEY", "key1key1key1key1key1key1key1key1key1key1")
      {:ok, token1} = ElasticacheIamAuth.generate_token("cache", "user", "us-east-1")

      System.put_env("AWS_SECRET_ACCESS_KEY", "key2key2key2key2key2key2key2key2key2key2")
      {:ok, token2} = ElasticacheIamAuth.generate_token("cache", "user", "us-east-1")

      sig1 = Regex.run(~r/X-Amz-Signature=([^&]+)/, token1) |> List.last()
      sig2 = Regex.run(~r/X-Amz-Signature=([^&]+)/, token2) |> List.last()

      refute sig1 == sig2
    end
  end

  describe "service differences from RDS" do
    test "uses elasticache service name in credential scope" do
      System.put_env("AWS_ACCESS_KEY_ID", "AKIAIOSFODNN7EXAMPLE")
      System.put_env("AWS_SECRET_ACCESS_KEY", "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY")

      {:ok, token} = ElasticacheIamAuth.generate_token("cache", "user", "us-east-1")

      # Should use "elasticache" not "rds-db"
      assert String.contains?(token, "/elasticache/aws4_request")
      refute String.contains?(token, "/rds-db/")
    end
  end
end
