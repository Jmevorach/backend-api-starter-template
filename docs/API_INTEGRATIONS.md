# API Integrations Guide

This backend intentionally ships with minimal optional vendor integrations
(payments, background checks, maps, etc.). The goal is to keep the open-source
mobile backend clean and domain-focused while making integrations easy to add.

## Table of Contents

- [Integration Pattern](#integration-pattern)
- [Runtime Configuration](#runtime-configuration)
- [Testing Integrations](#testing-integrations)
- [Security Checklist](#security-checklist)

## Integration Pattern

Create a dedicated module under `app/lib/backend/`:

```elixir
defmodule Backend.YourService do
  @base_url "https://api.example.com/v1"

  def request(payload) do
    case api_key() do
      nil -> {:error, :api_key_not_configured}
      key -> http_client().post(@base_url <> "/endpoint", headers: auth_headers(key), json: payload)
    end
  end

  defp api_key, do: Application.get_env(:backend, :your_service)[:api_key]
  defp http_client, do: Application.get_env(:backend, :http_client, Backend.HTTPClient.Impl)
  defp auth_headers(key), do: [{"authorization", "Bearer #{key}"}]
end
```

## Runtime Configuration

Use environment variables in `config/runtime.exs`, for example:

```elixir
your_service_key = System.get_env("YOUR_SERVICE_API_KEY")

if your_service_key do
  config :backend, :your_service, api_key: your_service_key
end
```

For production, inject secrets from AWS Secrets Manager using `infra/variables.tf`
and `infra/ecs.tf`.

## Testing Integrations

- Use `Mox` and `Backend.HTTPClientMock` for deterministic tests.
- Assert both success and failure paths.
- Avoid live API tests in default CI pipelines.

## Security Checklist

- Store keys in Secrets Manager, never in source code.
- Validate webhook signatures with constant-time comparison.
- Avoid logging raw payloads that may contain sensitive user data.
- Apply least-privilege IAM when granting secret access.
