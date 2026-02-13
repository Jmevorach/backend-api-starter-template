import Config

if config_env() == :prod do
  # Required configuration
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      This is set via AWS Secrets Manager and injected into the ECS task definition.
      """

  port = String.to_integer(System.get_env("PORT") || "443")

  max_request_body_bytes =
    String.to_integer(System.get_env("MAX_REQUEST_BODY_BYTES") || "2000000")

  db_host =
    System.get_env("DB_HOST") ||
      raise "environment variable DB_HOST is missing."

  db_name =
    System.get_env("DB_NAME") ||
      raise "environment variable DB_NAME is missing."

  db_user =
    System.get_env("DB_USERNAME") ||
      raise "environment variable DB_USERNAME is missing."

  # IAM authentication for database
  db_iam_auth = System.get_env("DB_IAM_AUTH") == "true"
  db_password = System.get_env("DB_PASSWORD")
  require_iam_auth = System.get_env("REQUIRE_IAM_AUTH") == "true"
  aws_region = System.get_env("AWS_REGION") || "us-east-1"

  ssl_keyfile = System.get_env("SSL_KEYFILE") || "/etc/ssl/private/selfsigned.key"
  ssl_certfile = System.get_env("SSL_CERTFILE") || "/etc/ssl/certs/selfsigned.crt"

  # Endpoint configuration
  config :backend, BackendWeb.Endpoint,
    server: true,
    url: [host: System.get_env("PHX_HOST") || "example.com", port: 443, scheme: "https"],
    max_request_body_bytes: max_request_body_bytes,
    http: false,
    https: [
      ip: {0, 0, 0, 0},
      port: port,
      cipher_suite: :strong,
      keyfile: ssl_keyfile,
      certfile: ssl_certfile
    ],
    secret_key_base: secret_key_base

  # Database configuration with IAM authentication
  # When DB_IAM_AUTH=true, we use AWS RDS IAM auth tokens instead of passwords
  # The token is generated dynamically via the configure callback in repo.ex
  config :backend, Backend.Repo,
    hostname: db_host,
    database: db_name,
    username: db_user,
    port: 5432,
    pool_size: String.to_integer(System.get_env("DB_POOL_SIZE") || "10"),
    ssl: true,
    ssl_opts: [verify: :verify_none],
    # Connection settings for IAM auth
    queue_target: 5000,
    queue_interval: 1000

  # Store authentication configuration for the Repo to use
  config :backend, :db_iam_auth, db_iam_auth
  config :backend, :db_password, db_password
  config :backend, :require_iam_auth, require_iam_auth
  config :backend, :aws_region, aws_region

  # Google OAuth configuration (optional - only configure if credentials are provided)
  google_client_id = System.get_env("GOOGLE_CLIENT_ID")
  google_client_secret = System.get_env("GOOGLE_CLIENT_SECRET")

  if google_client_id && google_client_secret do
    config :ueberauth, Ueberauth.Strategy.Google.OAuth,
      client_id: google_client_id,
      client_secret: google_client_secret
  end

  # Apple OAuth configuration (optional - only configure if credentials are provided)
  apple_client_id = System.get_env("APPLE_CLIENT_ID")
  apple_client_secret = System.get_env("APPLE_CLIENT_SECRET")
  apple_team_id = System.get_env("APPLE_TEAM_ID")
  apple_key_id = System.get_env("APPLE_KEY_ID")
  apple_private_key = System.get_env("APPLE_PRIVATE_KEY")

  if apple_client_id && apple_client_secret && apple_team_id && apple_key_id && apple_private_key do
    config :ueberauth, Ueberauth.Strategy.Apple,
      client_id: apple_client_id,
      client_secret: apple_client_secret,
      team_id: apple_team_id,
      key_id: apple_key_id,
      private_key: apple_private_key
  end

  # Stripe API configuration (optional)
  stripe_api_key = System.get_env("STRIPE_API_KEY")

  if stripe_api_key do
    config :backend, :stripe, api_key: stripe_api_key
  end

  # Checkr API configuration (optional)
  checkr_api_key = System.get_env("CHECKR_API_KEY")
  checkr_environment = System.get_env("CHECKR_ENVIRONMENT") || "sandbox"

  if checkr_api_key do
    config :backend, :checkr,
      api_key: checkr_api_key,
      environment: checkr_environment
  end

  # Google Maps Platform configuration (optional)
  google_maps_api_key = System.get_env("GOOGLE_MAPS_API_KEY")

  if google_maps_api_key do
    config :backend, :google_maps, api_key: google_maps_api_key
  end

  # Valkey/Redis configuration with IAM authentication
  valkey_host = System.get_env("VALKEY_HOST")
  valkey_port = String.to_integer(System.get_env("VALKEY_PORT") || "6379")
  valkey_user = System.get_env("VALKEY_USER") || "app_user"
  valkey_password = System.get_env("VALKEY_PASSWORD")
  valkey_iam_auth = System.get_env("VALKEY_IAM_AUTH") == "true"
  valkey_cluster_id = System.get_env("VALKEY_CLUSTER_ID")
  # SSL is enabled by default in production, but can be disabled for local dev
  valkey_ssl = System.get_env("VALKEY_SSL") != "false"

  if valkey_host do
    config :backend, :valkey,
      host: valkey_host,
      port: valkey_port,
      username: valkey_user,
      password: valkey_password,
      ssl: valkey_ssl,
      iam_auth: valkey_iam_auth,
      cluster_id: valkey_cluster_id
  end

  # Production logging configuration
  config :logger, level: :info

  config :logger, :console,
    format: "$time $metadata[$level] $message\n",
    metadata: [:request_id]
end
