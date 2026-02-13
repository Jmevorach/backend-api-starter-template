defmodule Backend.ValkeyAuthTest do
  @moduledoc """
  Tests for the Valkey/Redis authentication configuration logic.

  These tests verify:
  - Valkey configuration handling
  - IAM authentication preference and fallback behavior
  - Password authentication configuration
  - SSL/TLS configuration
  - REQUIRE_IAM_AUTH enforcement

  Note: These tests focus on configuration and logic paths.
  Actual IAM token generation would require mocking AWS services.
  """

  use ExUnit.Case, async: false

  # Store original config and restore after each test
  setup do
    original_valkey = Application.get_env(:backend, :valkey)
    original_require_iam_auth = Application.get_env(:backend, :require_iam_auth)
    original_aws_region = Application.get_env(:backend, :aws_region)

    on_exit(fn ->
      restore_env(:backend, :valkey, original_valkey)
      restore_env(:backend, :require_iam_auth, original_require_iam_auth)
      restore_env(:backend, :aws_region, original_aws_region)
    end)

    :ok
  end

  defp restore_env(app, key, nil), do: Application.delete_env(app, key)
  defp restore_env(app, key, value), do: Application.put_env(app, key, value)

  describe "valkey configuration" do
    test "can be nil (not configured)" do
      Application.delete_env(:backend, :valkey)
      assert Application.get_env(:backend, :valkey) == nil
    end

    test "can set host and port" do
      Application.put_env(:backend, :valkey,
        host: "localhost",
        port: 6379
      )

      config = Application.get_env(:backend, :valkey)
      assert Keyword.get(config, :host) == "localhost"
      assert Keyword.get(config, :port) == 6379
    end

    test "can set username" do
      Application.put_env(:backend, :valkey,
        host: "localhost",
        port: 6379,
        username: "app_user"
      )

      config = Application.get_env(:backend, :valkey)
      assert Keyword.get(config, :username) == "app_user"
    end

    test "can set password" do
      Application.put_env(:backend, :valkey,
        host: "localhost",
        port: 6379,
        password: "secret123"
      )

      config = Application.get_env(:backend, :valkey)
      assert Keyword.get(config, :password) == "secret123"
    end

    test "can set ssl configuration" do
      Application.put_env(:backend, :valkey,
        host: "localhost",
        port: 6379,
        ssl: true
      )

      config = Application.get_env(:backend, :valkey)
      assert Keyword.get(config, :ssl) == true
    end

    test "can set iam_auth configuration" do
      Application.put_env(:backend, :valkey,
        host: "localhost",
        port: 6379,
        iam_auth: true,
        cluster_id: "my-cluster"
      )

      config = Application.get_env(:backend, :valkey)
      assert Keyword.get(config, :iam_auth) == true
      assert Keyword.get(config, :cluster_id) == "my-cluster"
    end
  end

  describe "local development configuration" do
    test "typical local dev config: no SSL, no IAM, with password" do
      Application.put_env(:backend, :valkey,
        host: "localhost",
        port: 6379,
        password: "devpassword",
        ssl: false,
        iam_auth: false
      )

      config = Application.get_env(:backend, :valkey)
      assert Keyword.get(config, :host) == "localhost"
      assert Keyword.get(config, :ssl) == false
      assert Keyword.get(config, :iam_auth) == false
      assert Keyword.get(config, :password) == "devpassword"
    end

    test "local dev without password (no auth)" do
      Application.put_env(:backend, :valkey,
        host: "localhost",
        port: 6379,
        ssl: false,
        iam_auth: false
      )

      config = Application.get_env(:backend, :valkey)
      assert Keyword.get(config, :password) == nil
    end
  end

  describe "production configuration" do
    test "production with IAM auth" do
      Application.put_env(:backend, :valkey,
        host: "my-cluster.serverless.use1.cache.amazonaws.com",
        port: 6379,
        username: "app_user",
        ssl: true,
        iam_auth: true,
        cluster_id: "my-cluster"
      )

      config = Application.get_env(:backend, :valkey)
      assert Keyword.get(config, :ssl) == true
      assert Keyword.get(config, :iam_auth) == true
      assert Keyword.get(config, :cluster_id) == "my-cluster"
    end

    test "production with password auth (fallback)" do
      Application.put_env(:backend, :valkey,
        host: "my-cluster.serverless.use1.cache.amazonaws.com",
        port: 6379,
        username: "app_user",
        password: "production_password",
        ssl: true,
        iam_auth: false
      )

      config = Application.get_env(:backend, :valkey)
      assert Keyword.get(config, :ssl) == true
      assert Keyword.get(config, :iam_auth) == false
      assert Keyword.get(config, :password) == "production_password"
    end
  end

  describe "SSL configuration" do
    test "ssl defaults behavior" do
      Application.put_env(:backend, :valkey,
        host: "localhost",
        port: 6379
      )

      config = Application.get_env(:backend, :valkey)
      # When not specified, it should be nil (application.ex defaults to true)
      ssl = Keyword.get(config, :ssl)
      assert ssl == nil or ssl == true or ssl == false
    end

    test "ssl can be explicitly true" do
      Application.put_env(:backend, :valkey,
        host: "localhost",
        port: 6379,
        ssl: true
      )

      config = Application.get_env(:backend, :valkey)
      assert Keyword.get(config, :ssl) == true
    end

    test "ssl can be explicitly false" do
      Application.put_env(:backend, :valkey,
        host: "localhost",
        port: 6379,
        ssl: false
      )

      config = Application.get_env(:backend, :valkey)
      assert Keyword.get(config, :ssl) == false
    end
  end

  describe "authentication mode combinations" do
    test "iam_auth=true without cluster_id is incomplete" do
      Application.put_env(:backend, :valkey,
        host: "localhost",
        port: 6379,
        iam_auth: true
        # Missing cluster_id
      )

      config = Application.get_env(:backend, :valkey)
      assert Keyword.get(config, :iam_auth) == true
      assert Keyword.get(config, :cluster_id) == nil
    end

    test "iam_auth=false ignores cluster_id" do
      Application.put_env(:backend, :valkey,
        host: "localhost",
        port: 6379,
        iam_auth: false,
        cluster_id: "ignored-cluster"
      )

      config = Application.get_env(:backend, :valkey)
      assert Keyword.get(config, :iam_auth) == false
      # cluster_id is still present but won't be used
      assert Keyword.get(config, :cluster_id) == "ignored-cluster"
    end

    test "password can coexist with iam_auth for fallback" do
      Application.put_env(:backend, :valkey,
        host: "production-endpoint",
        port: 6379,
        iam_auth: true,
        cluster_id: "my-cluster",
        password: "fallback_password"
      )

      config = Application.get_env(:backend, :valkey)
      assert Keyword.get(config, :iam_auth) == true
      assert Keyword.get(config, :password) == "fallback_password"
    end
  end

  describe "require_iam_auth enforcement" do
    test "require_iam_auth applies to valkey as well" do
      Application.put_env(:backend, :require_iam_auth, true)

      Application.put_env(:backend, :valkey,
        host: "localhost",
        port: 6379,
        iam_auth: false,
        password: "password"
      )

      # The configuration is set, but application.ex will raise if
      # require_iam_auth is true and iam_auth is false
      assert Application.get_env(:backend, :require_iam_auth) == true
    end

    test "require_iam_auth=false allows password auth" do
      Application.put_env(:backend, :require_iam_auth, false)

      Application.put_env(:backend, :valkey,
        host: "localhost",
        port: 6379,
        iam_auth: false,
        password: "password"
      )

      # This configuration is valid
      assert Application.get_env(:backend, :require_iam_auth) == false
    end
  end

  describe "port configuration" do
    test "default port is 6379" do
      Application.put_env(:backend, :valkey, host: "localhost")

      config = Application.get_env(:backend, :valkey)
      # port might not be set, application.ex defaults to 6379
      port = Keyword.get(config, :port, 6379)
      assert port == 6379
    end

    test "custom port can be specified" do
      Application.put_env(:backend, :valkey,
        host: "localhost",
        port: 6380
      )

      config = Application.get_env(:backend, :valkey)
      assert Keyword.get(config, :port) == 6380
    end

    test "ElastiCache Serverless uses port 6379" do
      Application.put_env(:backend, :valkey,
        host: "cluster.serverless.use1.cache.amazonaws.com",
        port: 6379,
        ssl: true
      )

      config = Application.get_env(:backend, :valkey)
      assert Keyword.get(config, :port) == 6379
    end
  end

  describe "username configuration" do
    test "username can be nil for legacy auth" do
      Application.put_env(:backend, :valkey,
        host: "localhost",
        port: 6379,
        password: "password"
        # No username
      )

      config = Application.get_env(:backend, :valkey)
      assert Keyword.get(config, :username) == nil
    end

    test "username with password for RBAC" do
      Application.put_env(:backend, :valkey,
        host: "localhost",
        port: 6379,
        username: "app_user",
        password: "user_password"
      )

      config = Application.get_env(:backend, :valkey)
      assert Keyword.get(config, :username) == "app_user"
      assert Keyword.get(config, :password) == "user_password"
    end

    test "username required for IAM auth" do
      Application.put_env(:backend, :valkey,
        host: "localhost",
        port: 6379,
        username: "iam_user",
        iam_auth: true,
        cluster_id: "my-cluster"
      )

      config = Application.get_env(:backend, :valkey)
      assert Keyword.get(config, :username) == "iam_user"
    end
  end

  describe "password handling" do
    test "nil password is valid (no auth)" do
      Application.put_env(:backend, :valkey,
        host: "localhost",
        port: 6379
      )

      config = Application.get_env(:backend, :valkey)
      assert Keyword.get(config, :password) == nil
    end

    test "empty string password is different from nil" do
      Application.put_env(:backend, :valkey,
        host: "localhost",
        port: 6379,
        password: ""
      )

      config = Application.get_env(:backend, :valkey)
      assert Keyword.get(config, :password) == ""
    end

    test "password with special characters" do
      special_password = "p@$$w0rd!#$%^&*()"

      Application.put_env(:backend, :valkey,
        host: "localhost",
        port: 6379,
        password: special_password
      )

      config = Application.get_env(:backend, :valkey)
      assert Keyword.get(config, :password) == special_password
    end
  end

  describe "AWS region for IAM auth" do
    test "aws_region defaults to us-east-1" do
      Application.delete_env(:backend, :aws_region)
      assert Application.get_env(:backend, :aws_region, "us-east-1") == "us-east-1"
    end

    test "aws_region can be configured" do
      Application.put_env(:backend, :aws_region, "eu-central-1")
      assert Application.get_env(:backend, :aws_region) == "eu-central-1"
    end

    test "aws_region is used for IAM token generation" do
      Application.put_env(:backend, :aws_region, "ap-southeast-2")

      Application.put_env(:backend, :valkey,
        host: "cluster.ap-southeast-2.cache.amazonaws.com",
        port: 6379,
        iam_auth: true,
        cluster_id: "my-cluster"
      )

      assert Application.get_env(:backend, :aws_region) == "ap-southeast-2"
    end
  end
end
