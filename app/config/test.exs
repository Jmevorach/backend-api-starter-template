import Config

config :backend, BackendWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  server: false,
  secret_key_base: String.duplicate("b", 64),
  session_opts: [
    store: :cookie,
    key: "_backend_session",
    signing_salt: "test_signing_salt"
  ]

test_db_username = System.get_env("TEST_DB_USERNAME") || "postgres"
test_db_password = System.get_env("TEST_DB_PASSWORD") || "postgres"
test_db_name = System.get_env("TEST_DB_NAME") || "backend_test"
test_db_host = System.get_env("TEST_DB_HOST") || "localhost"

config :backend, Backend.Repo,
  username: test_db_username,
  password: test_db_password,
  database: test_db_name,
  hostname: test_db_host,
  pool: Ecto.Adapters.SQL.Sandbox
