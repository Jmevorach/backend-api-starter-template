defmodule Backend.HTTPClient do
  @moduledoc """
  HTTP client behavior for external API requests.

  This module defines a behavior that can be mocked in tests using Mox,
  allowing us to test API client modules without making real HTTP requests.

  ## Usage in Production

  The default implementation uses `Req` to make HTTP requests:

      Backend.HTTPClient.Impl.get("https://api.example.com/resource", params: %{key: "value"})

  ## Usage in Tests

  In tests, configure the mock:

      Mox.expect(Backend.HTTPClientMock, :get, fn url, opts ->
        {:ok, %{status: 200, body: %{"data" => "mocked"}}}
      end)

  ## Configuration

  Set the HTTP client implementation via config:

      config :backend, :http_client, Backend.HTTPClient.Impl  # production
      config :backend, :http_client, Backend.HTTPClientMock   # test
  """

  @type url :: String.t()
  @type opts :: keyword()
  @type response :: {:ok, %{status: integer(), body: term()}} | {:error, term()}

  @doc """
  Makes an HTTP GET request.
  """
  @callback get(url(), opts()) :: response()

  @doc """
  Makes an HTTP POST request.
  """
  @callback post(url(), opts()) :: response()

  @doc """
  Makes an HTTP PUT request.
  """
  @callback put(url(), opts()) :: response()

  @doc """
  Makes an HTTP DELETE request.
  """
  @callback delete(url(), opts()) :: response()

  @doc """
  Makes an HTTP HEAD request.
  """
  @callback head(url(), opts()) :: response()

  @doc """
  Returns the configured HTTP client implementation.
  """
  def impl do
    Application.get_env(:backend, :http_client, Backend.HTTPClient.Impl)
  end

  @doc """
  Makes an HTTP GET request using the configured implementation.
  """
  def get(url, opts \\ []), do: impl().get(url, opts)

  @doc """
  Makes an HTTP POST request using the configured implementation.
  """
  def post(url, opts \\ []), do: impl().post(url, opts)

  @doc """
  Makes an HTTP PUT request using the configured implementation.
  """
  def put(url, opts \\ []), do: impl().put(url, opts)

  @doc """
  Makes an HTTP DELETE request using the configured implementation.
  """
  def delete(url, opts \\ []), do: impl().delete(url, opts)

  @doc """
  Makes an HTTP HEAD request using the configured implementation.
  """
  def head(url, opts \\ []), do: impl().head(url, opts)
end

defmodule Backend.HTTPClient.Impl do
  @moduledoc """
  Default HTTP client implementation using Req.

  This is the production implementation that makes real HTTP requests.
  In tests, this module is replaced by `Backend.HTTPClientMock` to avoid
  network calls and enable deterministic testing.

  ## Req Library

  This implementation uses the `Req` library which provides:
  - Automatic JSON encoding/decoding
  - Retry with backoff
  - Request/response logging
  - Connection pooling

  ## Example

      {:ok, response} = Backend.HTTPClient.Impl.get("https://api.example.com/data",
        params: %{page: 1},
        headers: [{"authorization", "Bearer token"}]
      )

      response.status  # => 200
      response.body    # => %{"data" => [...]}
  """

  @behaviour Backend.HTTPClient

  @impl true
  def get(url, opts) do
    Req.get(url, opts)
  end

  @impl true
  def post(url, opts) do
    Req.post(url, opts)
  end

  @impl true
  def put(url, opts) do
    Req.put(url, opts)
  end

  @impl true
  def delete(url, opts) do
    Req.delete(url, opts)
  end

  @impl true
  def head(url, opts) do
    Req.head(url, opts)
  end
end
