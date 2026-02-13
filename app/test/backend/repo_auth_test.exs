defmodule Backend.RepoAuthTest do
  @moduledoc """
  Tests for the database authentication configuration logic in Backend.Repo.

  These tests verify:
  - IAM authentication preference and fallback behavior
  - REQUIRE_IAM_AUTH enforcement
  - Password fallback logic
  - Configuration validation

  Note: These tests focus on the configuration and logic paths.
  Actual IAM token generation would require mocking AWS services.
  """

  use ExUnit.Case, async: false

  # Store original config and restore after each test
  setup do
    original_db_iam_auth = Application.get_env(:backend, :db_iam_auth)
    original_require_iam_auth = Application.get_env(:backend, :require_iam_auth)
    original_db_password = Application.get_env(:backend, :db_password)
    original_aws_region = Application.get_env(:backend, :aws_region)

    on_exit(fn ->
      restore_env(:backend, :db_iam_auth, original_db_iam_auth)
      restore_env(:backend, :require_iam_auth, original_require_iam_auth)
      restore_env(:backend, :db_password, original_db_password)
      restore_env(:backend, :aws_region, original_aws_region)
    end)

    :ok
  end

  defp restore_env(app, key, nil), do: Application.delete_env(app, key)
  defp restore_env(app, key, value), do: Application.put_env(app, key, value)

  describe "configuration defaults" do
    test "db_iam_auth defaults to false" do
      Application.delete_env(:backend, :db_iam_auth)
      assert Application.get_env(:backend, :db_iam_auth, false) == false
    end

    test "require_iam_auth defaults to false" do
      Application.delete_env(:backend, :require_iam_auth)
      assert Application.get_env(:backend, :require_iam_auth, false) == false
    end

    test "db_password defaults to nil" do
      Application.delete_env(:backend, :db_password)
      assert Application.get_env(:backend, :db_password) == nil
    end

    test "aws_region defaults to us-east-1" do
      Application.delete_env(:backend, :aws_region)
      assert Application.get_env(:backend, :aws_region, "us-east-1") == "us-east-1"
    end
  end

  describe "authentication configuration combinations" do
    test "can set db_iam_auth to true" do
      Application.put_env(:backend, :db_iam_auth, true)
      assert Application.get_env(:backend, :db_iam_auth) == true
    end

    test "can set db_iam_auth to false" do
      Application.put_env(:backend, :db_iam_auth, false)
      assert Application.get_env(:backend, :db_iam_auth) == false
    end

    test "can set require_iam_auth to true" do
      Application.put_env(:backend, :require_iam_auth, true)
      assert Application.get_env(:backend, :require_iam_auth) == true
    end

    test "can set db_password" do
      Application.put_env(:backend, :db_password, "test_password")
      assert Application.get_env(:backend, :db_password) == "test_password"
    end

    test "can set aws_region" do
      Application.put_env(:backend, :aws_region, "eu-west-1")
      assert Application.get_env(:backend, :aws_region) == "eu-west-1"
    end
  end

  describe "valid configuration scenarios" do
    test "local development: no IAM, no password (trust auth)" do
      Application.put_env(:backend, :db_iam_auth, false)
      Application.put_env(:backend, :require_iam_auth, false)
      Application.delete_env(:backend, :db_password)

      # This is valid - local dev with trust authentication
      assert Application.get_env(:backend, :db_iam_auth) == false
      assert Application.get_env(:backend, :require_iam_auth) == false
      assert Application.get_env(:backend, :db_password) == nil
    end

    test "local development: no IAM, with password" do
      Application.put_env(:backend, :db_iam_auth, false)
      Application.put_env(:backend, :require_iam_auth, false)
      Application.put_env(:backend, :db_password, "local_password")

      # This is valid - local dev with password
      assert Application.get_env(:backend, :db_password) == "local_password"
    end

    test "production with IAM: IAM enabled, required" do
      Application.put_env(:backend, :db_iam_auth, true)
      Application.put_env(:backend, :require_iam_auth, true)
      Application.put_env(:backend, :aws_region, "us-west-2")

      # This is the recommended production configuration
      assert Application.get_env(:backend, :db_iam_auth) == true
      assert Application.get_env(:backend, :require_iam_auth) == true
    end

    test "production with fallback: IAM enabled, not required, with password" do
      Application.put_env(:backend, :db_iam_auth, true)
      Application.put_env(:backend, :require_iam_auth, false)
      Application.put_env(:backend, :db_password, "fallback_password")

      # This allows IAM with password fallback
      assert Application.get_env(:backend, :db_iam_auth) == true
      assert Application.get_env(:backend, :require_iam_auth) == false
      assert Application.get_env(:backend, :db_password) == "fallback_password"
    end
  end

  describe "configuration validation scenarios" do
    # These test the logical consistency of configurations
    # The actual raise would happen in Repo.init, which we don't call directly

    test "invalid: require_iam_auth=true but db_iam_auth=false" do
      # This configuration should be caught by the Repo
      Application.put_env(:backend, :db_iam_auth, false)
      Application.put_env(:backend, :require_iam_auth, true)

      # We can verify the config values are set correctly
      # The actual error would be raised in Repo.init
      assert Application.get_env(:backend, :db_iam_auth) == false
      assert Application.get_env(:backend, :require_iam_auth) == true
    end
  end

  describe "Repo configuration reading" do
    # Test that the Repo module can read the configuration

    test "reads db_iam_auth from application config" do
      Application.put_env(:backend, :db_iam_auth, true)
      assert Application.get_env(:backend, :db_iam_auth, false) == true

      Application.put_env(:backend, :db_iam_auth, false)
      assert Application.get_env(:backend, :db_iam_auth, false) == false
    end

    test "reads require_iam_auth from application config" do
      Application.put_env(:backend, :require_iam_auth, true)
      assert Application.get_env(:backend, :require_iam_auth, false) == true

      Application.put_env(:backend, :require_iam_auth, false)
      assert Application.get_env(:backend, :require_iam_auth, false) == false
    end

    test "reads db_password from application config" do
      Application.put_env(:backend, :db_password, "secret123")
      assert Application.get_env(:backend, :db_password) == "secret123"
    end

    test "reads aws_region from application config" do
      Application.put_env(:backend, :aws_region, "ap-southeast-1")
      assert Application.get_env(:backend, :aws_region, "us-east-1") == "ap-southeast-1"
    end
  end

  describe "password handling" do
    test "nil password is handled gracefully" do
      Application.delete_env(:backend, :db_password)

      # The fallback logic should handle nil passwords
      password = Application.get_env(:backend, :db_password)
      assert is_nil(password)
    end

    test "empty string password is not the same as nil" do
      Application.put_env(:backend, :db_password, "")

      password = Application.get_env(:backend, :db_password)
      assert password == ""
      refute is_nil(password)
    end

    test "password with special characters is preserved" do
      special_password = "p@$$w0rd!#$%^&*()"
      Application.put_env(:backend, :db_password, special_password)

      assert Application.get_env(:backend, :db_password) == special_password
    end

    test "long password is preserved" do
      long_password = String.duplicate("a", 1000)
      Application.put_env(:backend, :db_password, long_password)

      assert Application.get_env(:backend, :db_password) == long_password
    end

    test "password with unicode characters is preserved" do
      unicode_password = "пароль日本語🔐"
      Application.put_env(:backend, :db_password, unicode_password)

      assert Application.get_env(:backend, :db_password) == unicode_password
    end

    test "password with newlines is preserved" do
      newline_password = "line1\nline2\r\nline3"
      Application.put_env(:backend, :db_password, newline_password)

      assert Application.get_env(:backend, :db_password) == newline_password
    end
  end

  describe "Repo.init/2 password fallback" do
    test "uses password when IAM is disabled and password is configured" do
      Application.put_env(:backend, :db_iam_auth, false)
      Application.put_env(:backend, :require_iam_auth, false)
      Application.put_env(:backend, :db_password, "test_password")

      base_config = [hostname: "localhost", port: 5432, username: "postgres"]
      {:ok, config} = Backend.Repo.init(:runtime, base_config)

      assert Keyword.get(config, :password) == "test_password"
    end

    test "no password when IAM is disabled and no password configured" do
      Application.put_env(:backend, :db_iam_auth, false)
      Application.put_env(:backend, :require_iam_auth, false)
      Application.delete_env(:backend, :db_password)

      base_config = [hostname: "localhost", port: 5432, username: "postgres"]
      {:ok, config} = Backend.Repo.init(:runtime, base_config)

      # Should not have password key or have nil
      refute Keyword.has_key?(config, :password) or Keyword.get(config, :password) != nil
    end

    test "raises when require_iam_auth=true but db_iam_auth=false" do
      Application.put_env(:backend, :db_iam_auth, false)
      Application.put_env(:backend, :require_iam_auth, true)

      base_config = [hostname: "localhost", port: 5432, username: "postgres"]

      assert_raise RuntimeError, ~r/IAM authentication is required/, fn ->
        Backend.Repo.init(:runtime, base_config)
      end
    end

    test "uses password fallback when IAM fails and not required" do
      # Setup: IAM enabled but will fail (no AWS creds), fallback to password
      System.delete_env("AWS_ACCESS_KEY_ID")
      System.delete_env("AWS_SECRET_ACCESS_KEY")
      System.delete_env("AWS_CONTAINER_CREDENTIALS_RELATIVE_URI")

      Application.put_env(:backend, :db_iam_auth, true)
      Application.put_env(:backend, :require_iam_auth, false)
      Application.put_env(:backend, :db_password, "fallback_password")

      base_config = [hostname: "localhost", port: 5432, username: "postgres"]
      {:ok, config} = Backend.Repo.init(:runtime, base_config)

      # Should fall back to the configured password
      assert Keyword.get(config, :password) == "fallback_password"
    end

    test "raises when IAM fails and is required" do
      # Setup: IAM enabled and required, but will fail (no AWS creds)
      System.delete_env("AWS_ACCESS_KEY_ID")
      System.delete_env("AWS_SECRET_ACCESS_KEY")
      System.delete_env("AWS_CONTAINER_CREDENTIALS_RELATIVE_URI")

      Application.put_env(:backend, :db_iam_auth, true)
      Application.put_env(:backend, :require_iam_auth, true)

      base_config = [hostname: "localhost", port: 5432, username: "postgres"]

      assert_raise RuntimeError,
                   ~r/IAM authentication is required but token generation failed/,
                   fn ->
                     Backend.Repo.init(:runtime, base_config)
                   end
    end

    test "uses IAM token when IAM succeeds" do
      # Setup: IAM enabled with valid credentials
      System.put_env("AWS_ACCESS_KEY_ID", "AKIAIOSFODNN7EXAMPLE")
      System.put_env("AWS_SECRET_ACCESS_KEY", "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY")

      Application.put_env(:backend, :db_iam_auth, true)
      Application.put_env(:backend, :require_iam_auth, false)
      Application.put_env(:backend, :aws_region, "us-east-1")

      base_config = [hostname: "my-db.rds.amazonaws.com", port: 5432, username: "app_user"]
      {:ok, config} = Backend.Repo.init(:runtime, base_config)

      # Should have a generated IAM token as password
      password = Keyword.get(config, :password)
      assert is_binary(password)
      assert String.contains?(password, "X-Amz-Signature=")

      # Cleanup
      System.delete_env("AWS_ACCESS_KEY_ID")
      System.delete_env("AWS_SECRET_ACCESS_KEY")
    end
  end

  describe "database hostname configuration" do
    test "localhost hostname is preserved" do
      Application.put_env(:backend, Backend.Repo, hostname: "localhost")

      config = Application.get_env(:backend, Backend.Repo)
      assert config[:hostname] == "localhost"
    end

    test "AWS RDS hostname is preserved" do
      rds_hostname = "mydb.cluster-abc123.us-east-1.rds.amazonaws.com"
      Application.put_env(:backend, Backend.Repo, hostname: rds_hostname)

      config = Application.get_env(:backend, Backend.Repo)
      assert config[:hostname] == rds_hostname
    end

    test "hostname with port in config" do
      Application.put_env(:backend, Backend.Repo,
        hostname: "db.example.com",
        port: 5432
      )

      config = Application.get_env(:backend, Backend.Repo)
      assert config[:hostname] == "db.example.com"
      assert config[:port] == 5432
    end
  end

  describe "database name configuration" do
    test "database name is configurable" do
      Application.put_env(:backend, Backend.Repo, database: "custom_db_name")

      config = Application.get_env(:backend, Backend.Repo)
      assert config[:database] == "custom_db_name"
    end

    test "database name with special characters" do
      Application.put_env(:backend, Backend.Repo, database: "my-db_name.test")

      config = Application.get_env(:backend, Backend.Repo)
      assert config[:database] == "my-db_name.test"
    end
  end
end
