import Config

config :backend,
  ecto_repos: [Backend.Repo]

config :backend, BackendWeb.Endpoint,
  url: [host: "localhost"],
  max_request_body_bytes: 2_000_000,
  render_errors: [
    formats: [json: BackendWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Backend.PubSub

config :phoenix, :json_library, Jason

# Logger configuration
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id, :remote_ip, :trace_id, :method, :path, :user_id]

config :logger,
  level: :info

# Ueberauth configuration - providers are configured here,
# but credentials are set in runtime.exs for production
config :ueberauth, Ueberauth,
  providers: [
    google: {Ueberauth.Strategy.Google, [default_scope: "email profile"]},
    apple: {Ueberauth.Strategy.Apple, []}
  ]

import_config "#{config_env()}.exs"
