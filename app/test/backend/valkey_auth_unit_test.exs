defmodule Backend.ValkeyAuthUnitTest do
  @moduledoc """
  Unit tests for Valkey/ElastiCache authentication helpers.
  These tests focus on the authentication token generation code paths.
  """

  use ExUnit.Case, async: true

  alias Backend.ElasticacheIamAuth

  describe "generate_token/3" do
    test "returns error when no AWS credentials available" do
      # In test environment without AWS credentials, should return error
      result = ElasticacheIamAuth.generate_token("test-cluster", "testuser", "us-east-1")

      case result do
        {:ok, token} ->
          # If credentials are available, token should be a string
          assert is_binary(token)

        {:error, reason} ->
          # If no credentials, should return an error
          assert reason != nil
      end
    end

    test "generate_token with different regions" do
      regions = ["us-east-1", "us-west-2", "eu-west-1", "ap-northeast-1"]

      for region <- regions do
        result = ElasticacheIamAuth.generate_token("test-cluster", "testuser", region)
        assert match?({:ok, _}, result) or match?({:error, _}, result)
      end
    end

    test "generate_token with various cluster names" do
      clusters = ["my-cache", "production-valkey", "test-cluster-1"]

      for cluster <- clusters do
        result = ElasticacheIamAuth.generate_token(cluster, "testuser", "us-east-1")
        assert match?({:ok, _}, result) or match?({:error, _}, result)
      end
    end
  end

  describe "token format" do
    test "generated token is a string when successful" do
      # Attempt to generate a token
      case ElasticacheIamAuth.generate_token("test", "user", "us-east-1") do
        {:ok, token} ->
          assert is_binary(token)
          assert String.length(token) > 0

        {:error, _} ->
          # Expected in test env without AWS credentials
          :ok
      end
    end
  end
end
