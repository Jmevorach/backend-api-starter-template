## Local Development

This guide helps you run the Phoenix API locally with Postgres and Valkey.

### Table of Contents

- [Prerequisites](#prerequisites)
- [Start Dependencies](#start-dependencies)
- [Configure Environment](#configure-environment)
- [Run the App](#run-the-app)
- [Reset Local Data](#reset-local-data)
- [Troubleshooting](#troubleshooting)

### Prerequisites

- Docker (with Compose)
- Elixir + Erlang (for local app runs)

### Start Dependencies

The repo includes a `compose.yaml` for Postgres and Valkey.

```bash
bash scripts/dev-up.sh
```

### Configure Environment

The default `config/dev.exs` uses:

- DB user: `postgres`
- DB password: `postgres`
- DB name: `backend_dev`
- DB host: `localhost`

If you want Valkey-backed sessions locally, set:

```bash
export VALKEY_URL="redis://localhost:6379/0"
```

### Run the App

```bash
cd app
mix deps.get
mix ecto.create
mix ecto.migrate
mix phx.server
```

Verify:

```bash
curl http://localhost:4000/healthz
```

### Reset Local Data

To wipe the Postgres volume and start fresh:

```bash
bash scripts/dev-reset.sh
```

### Troubleshooting

- **DB connection errors**: make sure Postgres is running and port 5432 is free.
- **Valkey connection errors**: confirm `VALKEY_URL` is set and port 6379 is free.
