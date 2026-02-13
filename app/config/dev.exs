import Config

config :backend, BackendWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4000],
  check_origin: false,
  server: true,
  secret_key_base: String.duplicate("a", 64),
  debug_errors: true,
  code_reloader: true

config :backend, Backend.Repo,
  username: "postgres",
  password: "postgres",
  database: "backend_dev",
  hostname: "localhost",
  port: 5432,
  pool_size: 10,
  ssl: false,
  stacktrace: true,
  show_sensitive_data_on_connection_error: true

# Valkey configuration for local development
config :backend, :valkey,
  host: "localhost",
  port: 6379,
  password: "devpassword",
  ssl: false,
  iam_auth: false

# Development OAuth configuration - use dummy values
# Real OAuth won't work in dev without proper credentials
config :ueberauth, Ueberauth.Strategy.Google.OAuth,
  client_id: "dev_google_client_id",
  client_secret: "dev_google_client_secret"

config :ueberauth, Ueberauth.Strategy.Apple,
  client_id: "dev_apple_client_id",
  client_secret: "dev_apple_client_secret",
  team_id: "dev_team_id",
  key_id: "dev_key_id",
  private_key: "dev_private_key"

# More verbose logging in development
config :logger, :console, format: "[$level] $message\n"
config :logger, level: :debug

# Do not include metadata in dev logs
config :phoenix, :stacktrace_depth, 20

# Initialize plugs at runtime for faster development compilation
config :phoenix, :plug_init_mode, :runtime
