defmodule Backend.Stripe do
  @moduledoc """
  Stripe API client for mobile app payment workflows.
  """

  require Logger

  @base_url "https://api.stripe.com/v1"

  @spec create_customer(map()) :: {:ok, map()} | {:error, term()}
  def create_customer(params), do: post("/customers", params)

  @spec get_customer(String.t()) :: {:ok, map()} | {:error, term()}
  def get_customer(customer_id), do: get("/customers/#{customer_id}")

  @spec update_customer(String.t(), map()) :: {:ok, map()} | {:error, term()}
  def update_customer(customer_id, params), do: post("/customers/#{customer_id}", params)

  @spec list_customers(map()) :: {:ok, map()} | {:error, term()}
  def list_customers(params \\ %{}), do: get("/customers", params)

  @spec delete_customer(String.t()) :: {:ok, map()} | {:error, term()}
  def delete_customer(customer_id), do: delete("/customers/#{customer_id}")

  @spec create_payment_intent(map()) :: {:ok, map()} | {:error, term()}
  def create_payment_intent(params), do: post("/payment_intents", params)

  @spec get_payment_intent(String.t()) :: {:ok, map()} | {:error, term()}
  def get_payment_intent(payment_intent_id), do: get("/payment_intents/#{payment_intent_id}")

  @spec confirm_payment_intent(String.t(), map()) :: {:ok, map()} | {:error, term()}
  def confirm_payment_intent(payment_intent_id, params \\ %{}) do
    post("/payment_intents/#{payment_intent_id}/confirm", params)
  end

  @spec create_charge(map()) :: {:ok, map()} | {:error, term()}
  def create_charge(params), do: post("/charges", params)

  @spec get_charge(String.t()) :: {:ok, map()} | {:error, term()}
  def get_charge(charge_id), do: get("/charges/#{charge_id}")

  @spec create_subscription(map()) :: {:ok, map()} | {:error, term()}
  def create_subscription(params), do: post("/subscriptions", params)

  @spec get_subscription(String.t()) :: {:ok, map()} | {:error, term()}
  def get_subscription(subscription_id), do: get("/subscriptions/#{subscription_id}")

  @spec update_subscription(String.t(), map()) :: {:ok, map()} | {:error, term()}
  def update_subscription(subscription_id, params),
    do: post("/subscriptions/#{subscription_id}", params)

  @spec cancel_subscription(String.t(), map()) :: {:ok, map()} | {:error, term()}
  def cancel_subscription(subscription_id, params \\ %{}),
    do: delete("/subscriptions/#{subscription_id}", params)

  @spec list_subscriptions(map()) :: {:ok, map()} | {:error, term()}
  def list_subscriptions(params \\ %{}), do: get("/subscriptions", params)

  @spec list_products(map()) :: {:ok, map()} | {:error, term()}
  def list_products(params \\ %{}), do: get("/products", params)

  @spec list_prices(map()) :: {:ok, map()} | {:error, term()}
  def list_prices(params \\ %{}), do: get("/prices", params)

  @spec verify_webhook_signature(String.t(), String.t(), String.t()) ::
          {:ok, map()} | {:error, term()}
  def verify_webhook_signature(payload, signature, webhook_secret) do
    with {:ok, timestamp, expected_sig} <- parse_signature(signature),
         true <- secure_compare(sign("#{timestamp}.#{payload}", webhook_secret), expected_sig),
         {:ok, decoded} <- Jason.decode(payload) do
      {:ok, decoded}
    else
      false -> {:error, :invalid_signature}
      :error -> {:error, :invalid_signature}
      {:error, _} -> {:error, :invalid_payload}
    end
  end

  defp parse_signature(signature) do
    parsed =
      signature
      |> String.split(",", trim: true)
      |> Enum.map(&String.split(&1, "=", parts: 2))
      |> Enum.filter(&(length(&1) == 2))
      |> Map.new(fn [k, v] -> {k, v} end)

    case {parsed["t"], parsed["v1"]} do
      {t, v1} when is_binary(t) and is_binary(v1) -> {:ok, t, v1}
      _ -> :error
    end
  end

  defp get(path, params \\ %{}), do: request(:get, path, params)
  defp post(path, params), do: request(:post, path, params)
  defp delete(path, params \\ %{}), do: request(:delete, path, params)

  defp request(method, path, params) do
    case get_api_key() do
      nil ->
        {:error, :api_key_not_configured}

      api_key ->
        opts = [
          auth: {:basic, "#{api_key}:"},
          headers: [{"content-type", "application/x-www-form-urlencoded"}]
        ]

        opts =
          case method do
            :get -> Keyword.put(opts, :params, params)
            :delete -> Keyword.put(opts, :params, params)
            _ -> Keyword.put(opts, :form, params)
          end

        case apply(http_client(), method, [@base_url <> path, opts]) do
          {:ok, %{status: status, body: body}} when status in 200..299 ->
            {:ok, body}

          {:ok, %{status: _status, body: %{"error" => error}}} ->
            {:error, error}

          {:ok, %{status: status, body: body}} ->
            {:error, {:unexpected_status, status, body}}

          {:error, reason} ->
            Logger.error("Stripe request failed: #{inspect(reason)}")
            {:error, reason}
        end
    end
  end

  defp sign(payload, webhook_secret) do
    :crypto.mac(:hmac, :sha256, webhook_secret, payload)
    |> Base.encode16(case: :lower)
  end

  defp get_api_key do
    Application.get_env(:backend, :stripe)[:api_key]
  end

  defp http_client do
    Application.get_env(:backend, :http_client, Backend.HTTPClient.Impl)
  end

  defp secure_compare(a, b) when byte_size(a) != byte_size(b), do: false

  defp secure_compare(a, b) do
    a
    |> :binary.bin_to_list()
    |> Enum.zip(:binary.bin_to_list(b))
    |> Enum.reduce(0, fn {x, y}, acc -> Bitwise.bor(acc, Bitwise.bxor(x, y)) end)
    |> Kernel.==(0)
  end
end
