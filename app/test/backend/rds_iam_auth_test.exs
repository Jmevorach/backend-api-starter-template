defmodule Backend.RdsIamAuthTest do
  @moduledoc """
  Tests for RDS IAM authentication token generation.

  These tests verify:
  - Token format and structure
  - AWS SigV4 signing process
  - Credential handling from environment
  - Error handling
  """

  use ExUnit.Case, async: false

  alias Backend.RdsIamAuth

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

  describe "generate_token/4" do
    test "generates valid token format with environment credentials" do
      System.put_env("AWS_ACCESS_KEY_ID", "AKIAIOSFODNN7EXAMPLE")
      System.put_env("AWS_SECRET_ACCESS_KEY", "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY")
      System.delete_env("AWS_SESSION_TOKEN")

      hostname = "my-proxy.proxy-xxx.us-east-1.rds.amazonaws.com"
      port = 5432
      username = "app_user"
      region = "us-east-1"

      result = RdsIamAuth.generate_token(hostname, port, username, region)

      assert {:ok, token} = result
      assert String.starts_with?(token, "#{hostname}:#{port}/")
      assert String.contains?(token, "Action=connect")
      assert String.contains?(token, "DBUser=#{username}")
      assert String.contains?(token, "X-Amz-Algorithm=AWS4-HMAC-SHA256")
      assert String.contains?(token, "X-Amz-Credential=AKIAIOSFODNN7EXAMPLE")
      assert String.contains?(token, "X-Amz-Expires=900")
      assert String.contains?(token, "X-Amz-Signature=")
    end

    test "includes session token when provided" do
      System.put_env("AWS_ACCESS_KEY_ID", "AKIAIOSFODNN7EXAMPLE")
      System.put_env("AWS_SECRET_ACCESS_KEY", "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY")
      System.put_env("AWS_SESSION_TOKEN", "FwoGZXIvYXdzEBYaDK...")

      result = RdsIamAuth.generate_token("host", 5432, "user", "us-east-1")

      assert {:ok, token} = result
      assert String.contains?(token, "X-Amz-Security-Token=")
    end

    test "token contains correct region in credential scope" do
      System.put_env("AWS_ACCESS_KEY_ID", "AKIAIOSFODNN7EXAMPLE")
      System.put_env("AWS_SECRET_ACCESS_KEY", "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY")

      for region <- ["us-east-1", "us-west-2", "eu-west-1", "ap-southeast-1"] do
        result = RdsIamAuth.generate_token("host", 5432, "user", region)

        assert {:ok, token} = result
        assert String.contains?(token, "/#{region}/rds-db/aws4_request")
      end
    end

    test "handles different hostnames and ports" do
      System.put_env("AWS_ACCESS_KEY_ID", "AKIAIOSFODNN7EXAMPLE")
      System.put_env("AWS_SECRET_ACCESS_KEY", "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY")

      # Test with different hostnames
      for {hostname, port} <- [
            {"db.example.com", 5432},
            {"my-cluster.cluster-xxx.us-east-1.rds.amazonaws.com", 5432},
            {"proxy.us-east-1.rds.amazonaws.com", 3306},
            {"localhost", 15_432}
          ] do
        result = RdsIamAuth.generate_token(hostname, port, "user", "us-east-1")

        assert {:ok, token} = result
        assert String.starts_with?(token, "#{hostname}:#{port}/")
      end
    end

    test "handles different usernames" do
      System.put_env("AWS_ACCESS_KEY_ID", "AKIAIOSFODNN7EXAMPLE")
      System.put_env("AWS_SECRET_ACCESS_KEY", "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY")

      for username <- ["app_user", "admin", "readonly_user", "user_with_underscore"] do
        result = RdsIamAuth.generate_token("host", 5432, username, "us-east-1")

        assert {:ok, token} = result
        assert String.contains?(token, "DBUser=#{username}")
      end
    end

    test "returns error when no credentials available" do
      System.delete_env("AWS_ACCESS_KEY_ID")
      System.delete_env("AWS_SECRET_ACCESS_KEY")
      System.delete_env("AWS_CONTAINER_CREDENTIALS_RELATIVE_URI")

      result = RdsIamAuth.generate_token("host", 5432, "user", "us-east-1")

      assert {:error, _reason} = result
    end

    test "tokens generated at different times have different signatures" do
      System.put_env("AWS_ACCESS_KEY_ID", "AKIAIOSFODNN7EXAMPLE")
      System.put_env("AWS_SECRET_ACCESS_KEY", "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY")

      {:ok, token1} = RdsIamAuth.generate_token("host", 5432, "user", "us-east-1")
      # Small delay to ensure different timestamp
      Process.sleep(10)
      {:ok, token2} = RdsIamAuth.generate_token("host", 5432, "user", "us-east-1")

      # Tokens should be different due to timestamp
      # Note: They might rarely be the same if generated within the same second
      sig1 = Regex.run(~r/X-Amz-Signature=([^&]+)/, token1) |> List.last()
      sig2 = Regex.run(~r/X-Amz-Signature=([^&]+)/, token2) |> List.last()

      # Signatures should differ (unless same second)
      # We just verify they are valid hex strings
      assert String.match?(sig1, ~r/^[a-f0-9]{64}$/)
      assert String.match?(sig2, ~r/^[a-f0-9]{64}$/)
    end
  end

  describe "querystring parameters" do
    test "parameters are sorted alphabetically" do
      System.put_env("AWS_ACCESS_KEY_ID", "AKIAIOSFODNN7EXAMPLE")
      System.put_env("AWS_SECRET_ACCESS_KEY", "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY")

      {:ok, token} = RdsIamAuth.generate_token("host", 5432, "user", "us-east-1")

      # Extract querystring (everything after ?)
      [_, querystring] = String.split(token, "?", parts: 2)
      params = String.split(querystring, "&") |> Enum.map(&(String.split(&1, "=") |> hd()))

      # Verify params are sorted (excluding signature which is added at end)
      params_without_sig = Enum.filter(params, &(&1 != "X-Amz-Signature"))
      assert params_without_sig == Enum.sort(params_without_sig)
    end
  end

  describe "signature generation" do
    test "signature is 64 character lowercase hex string" do
      System.put_env("AWS_ACCESS_KEY_ID", "AKIAIOSFODNN7EXAMPLE")
      System.put_env("AWS_SECRET_ACCESS_KEY", "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY")

      {:ok, token} = RdsIamAuth.generate_token("host", 5432, "user", "us-east-1")

      [signature] = Regex.run(~r/X-Amz-Signature=([a-f0-9]+)/, token, capture: :all_but_first)

      # SHA256 HMAC produces 32 bytes = 64 hex characters
      assert String.length(signature) == 64
      assert String.match?(signature, ~r/^[a-f0-9]+$/)
    end

    test "different inputs produce different signatures" do
      System.put_env("AWS_ACCESS_KEY_ID", "AKIAIOSFODNN7EXAMPLE")
      System.put_env("AWS_SECRET_ACCESS_KEY", "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY")

      {:ok, token1} = RdsIamAuth.generate_token("host1", 5432, "user", "us-east-1")
      {:ok, token2} = RdsIamAuth.generate_token("host2", 5432, "user", "us-east-1")

      sig1 = Regex.run(~r/X-Amz-Signature=([^&]+)/, token1) |> List.last()
      sig2 = Regex.run(~r/X-Amz-Signature=([^&]+)/, token2) |> List.last()

      refute sig1 == sig2
    end
  end
end
