defmodule Backend.Stripe do
  @moduledoc """
  Stripe API client for payment processing.

  This module provides a simple interface to common Stripe operations including
  customers, charges, and subscriptions. It uses the Stripe REST API directly
  via the Req HTTP client.

  ## Configuration

  Set the `STRIPE_API_KEY` environment variable with your Stripe secret key.
  In production, this should be injected via AWS Secrets Manager.

  ## Usage

      # Create a customer
      {:ok, customer} = Backend.Stripe.create_customer(%{
        email: "user@example.com",
        name: "John Doe"
      })

      # Create a charge
      {:ok, charge} = Backend.Stripe.create_charge(%{
        amount: 2000,  # $20.00 in cents
        currency: "usd",
        customer: customer["id"]
      })

      # Create a subscription
      {:ok, subscription} = Backend.Stripe.create_subscription(%{
        customer: customer["id"],
        items: [%{price: "price_xxx"}]
      })

  ## Error Handling

  All functions return `{:ok, result}` on success or `{:error, reason}` on failure.
  Stripe API errors include the error type and message from Stripe.
  """

  require Logger

  @base_url "https://api.stripe.com/v1"

  # Customer Operations

  @doc """
  Creates a new Stripe customer.

  ## Parameters

    * `params` - Map containing customer details:
      * `:email` - Customer's email address (recommended)
      * `:name` - Customer's full name
      * `:description` - Optional description
      * `:metadata` - Optional metadata map
      * `:payment_method` - Optional payment method ID to attach

  ## Examples

      {:ok, customer} = Backend.Stripe.create_customer(%{
        email: "user@example.com",
        name: "John Doe"
      })
  """
  @spec create_customer(map()) :: {:ok, map()} | {:error, term()}
  def create_customer(params) do
    post("/customers", params)
  end

  @doc """
  Retrieves a Stripe customer by ID.

  ## Examples

      {:ok, customer} = Backend.Stripe.get_customer("cus_xxx")
  """
  @spec get_customer(String.t()) :: {:ok, map()} | {:error, term()}
  def get_customer(customer_id) do
    get("/customers/#{customer_id}")
  end

  @doc """
  Updates a Stripe customer.

  ## Parameters

    * `customer_id` - The Stripe customer ID
    * `params` - Map containing fields to update

  ## Examples

      {:ok, customer} = Backend.Stripe.update_customer("cus_xxx", %{
        email: "new@example.com"
      })
  """
  @spec update_customer(String.t(), map()) :: {:ok, map()} | {:error, term()}
  def update_customer(customer_id, params) do
    post("/customers/#{customer_id}", params)
  end

  @doc """
  Lists Stripe customers with optional filtering.

  ## Parameters

    * `params` - Optional map containing:
      * `:limit` - Number of customers to return (1-100, default 10)
      * `:starting_after` - Cursor for pagination
      * `:email` - Filter by email address

  ## Examples

      {:ok, %{"data" => customers}} = Backend.Stripe.list_customers(%{limit: 10})
  """
  @spec list_customers(map()) :: {:ok, map()} | {:error, term()}
  def list_customers(params \\ %{}) do
    get("/customers", params)
  end

  @doc """
  Deletes a Stripe customer.

  ## Examples

      {:ok, _} = Backend.Stripe.delete_customer("cus_xxx")
  """
  @spec delete_customer(String.t()) :: {:ok, map()} | {:error, term()}
  def delete_customer(customer_id) do
    delete("/customers/#{customer_id}")
  end

  # Payment Intent Operations (Modern approach for charges)

  @doc """
  Creates a PaymentIntent for collecting payment.

  This is the recommended way to collect payments in Stripe.

  ## Parameters

    * `params` - Map containing:
      * `:amount` - Amount in smallest currency unit (cents for USD)
      * `:currency` - Three-letter ISO currency code (e.g., "usd")
      * `:customer` - Optional customer ID
      * `:payment_method` - Optional payment method ID
      * `:confirm` - Whether to confirm immediately (default false)
      * `:metadata` - Optional metadata map

  ## Examples

      {:ok, intent} = Backend.Stripe.create_payment_intent(%{
        amount: 2000,
        currency: "usd",
        customer: "cus_xxx"
      })
  """
  @spec create_payment_intent(map()) :: {:ok, map()} | {:error, term()}
  def create_payment_intent(params) do
    post("/payment_intents", params)
  end

  @doc """
  Retrieves a PaymentIntent by ID.
  """
  @spec get_payment_intent(String.t()) :: {:ok, map()} | {:error, term()}
  def get_payment_intent(payment_intent_id) do
    get("/payment_intents/#{payment_intent_id}")
  end

  @doc """
  Confirms a PaymentIntent to complete the payment.
  """
  @spec confirm_payment_intent(String.t(), map()) :: {:ok, map()} | {:error, term()}
  def confirm_payment_intent(payment_intent_id, params \\ %{}) do
    post("/payment_intents/#{payment_intent_id}/confirm", params)
  end

  # Legacy Charge Operations (for simple charges)

  @doc """
  Creates a charge (legacy API - consider using PaymentIntents instead).

  ## Parameters

    * `params` - Map containing:
      * `:amount` - Amount in smallest currency unit (cents for USD)
      * `:currency` - Three-letter ISO currency code
      * `:customer` - Customer ID (if using saved payment method)
      * `:source` - Token or source ID (if not using customer)
      * `:description` - Optional description
      * `:metadata` - Optional metadata map

  ## Examples

      {:ok, charge} = Backend.Stripe.create_charge(%{
        amount: 2000,
        currency: "usd",
        customer: "cus_xxx"
      })
  """
  @spec create_charge(map()) :: {:ok, map()} | {:error, term()}
  def create_charge(params) do
    post("/charges", params)
  end

  @doc """
  Retrieves a charge by ID.
  """
  @spec get_charge(String.t()) :: {:ok, map()} | {:error, term()}
  def get_charge(charge_id) do
    get("/charges/#{charge_id}")
  end

  # Subscription Operations

  @doc """
  Creates a subscription for a customer.

  ## Parameters

    * `params` - Map containing:
      * `:customer` - Customer ID (required)
      * `:items` - List of subscription items, each with `:price` key
      * `:default_payment_method` - Optional payment method ID
      * `:trial_period_days` - Optional trial period
      * `:metadata` - Optional metadata map

  ## Examples

      {:ok, subscription} = Backend.Stripe.create_subscription(%{
        customer: "cus_xxx",
        items: [%{price: "price_xxx"}]
      })
  """
  @spec create_subscription(map()) :: {:ok, map()} | {:error, term()}
  def create_subscription(params) do
    post("/subscriptions", params)
  end

  @doc """
  Retrieves a subscription by ID.
  """
  @spec get_subscription(String.t()) :: {:ok, map()} | {:error, term()}
  def get_subscription(subscription_id) do
    get("/subscriptions/#{subscription_id}")
  end

  @doc """
  Updates a subscription.

  ## Examples

      {:ok, subscription} = Backend.Stripe.update_subscription("sub_xxx", %{
        items: [%{id: "si_xxx", price: "price_yyy"}]
      })
  """
  @spec update_subscription(String.t(), map()) :: {:ok, map()} | {:error, term()}
  def update_subscription(subscription_id, params) do
    post("/subscriptions/#{subscription_id}", params)
  end

  @doc """
  Cancels a subscription.

  ## Parameters

    * `subscription_id` - The subscription ID
    * `params` - Optional map containing:
      * `:cancel_at_period_end` - If true, cancel at end of period
      * `:prorate` - Whether to prorate (default true)

  ## Examples

      {:ok, subscription} = Backend.Stripe.cancel_subscription("sub_xxx")
  """
  @spec cancel_subscription(String.t(), map()) :: {:ok, map()} | {:error, term()}
  def cancel_subscription(subscription_id, params \\ %{}) do
    delete("/subscriptions/#{subscription_id}", params)
  end

  @doc """
  Lists subscriptions with optional filtering.

  ## Parameters

    * `params` - Optional map containing:
      * `:customer` - Filter by customer ID
      * `:status` - Filter by status (active, canceled, etc.)
      * `:limit` - Number to return (1-100)
  """
  @spec list_subscriptions(map()) :: {:ok, map()} | {:error, term()}
  def list_subscriptions(params \\ %{}) do
    get("/subscriptions", params)
  end

  # Product and Price Operations

  @doc """
  Lists available products.
  """
  @spec list_products(map()) :: {:ok, map()} | {:error, term()}
  def list_products(params \\ %{}) do
    get("/products", params)
  end

  @doc """
  Lists prices for products.
  """
  @spec list_prices(map()) :: {:ok, map()} | {:error, term()}
  def list_prices(params \\ %{}) do
    get("/prices", params)
  end

  # Webhook signature verification

  @doc """
  Verifies a Stripe webhook signature.

  ## Parameters

    * `payload` - Raw request body
    * `signature` - Value of `Stripe-Signature` header
    * `webhook_secret` - Your webhook endpoint's signing secret

  ## Examples

      case Backend.Stripe.verify_webhook_signature(body, sig_header, secret) do
        {:ok, event} -> handle_event(event)
        {:error, reason} -> {:error, :invalid_signature}
      end
  """
  @spec verify_webhook_signature(String.t(), String.t(), String.t()) ::
          {:ok, map()} | {:error, term()}
  def verify_webhook_signature(payload, signature, webhook_secret) do
    # Parse the signature header
    parts =
      signature
      |> String.split(",")
      |> Enum.map(fn part ->
        [key, value] = String.split(part, "=", parts: 2)
        {key, value}
      end)
      |> Map.new()

    timestamp = parts["t"]
    expected_sig = parts["v1"]

    # Compute the expected signature
    signed_payload = "#{timestamp}.#{payload}"

    computed_sig =
      :crypto.mac(:hmac, :sha256, webhook_secret, signed_payload)
      |> Base.encode16(case: :lower)

    # Verify signature using constant-time comparison
    if secure_compare(computed_sig, expected_sig) do
      # Parse and return the event
      case Jason.decode(payload) do
        {:ok, event} -> {:ok, event}
        {:error, _} -> {:error, :invalid_payload}
      end
    else
      {:error, :invalid_signature}
    end
  end

  # Private helper functions

  defp get(path, params \\ %{}) do
    request(:get, path, params)
  end

  defp post(path, params) do
    request(:post, path, params)
  end

  defp delete(path, params \\ %{}) do
    request(:delete, path, params)
  end

  defp request(method, path, params) do
    case get_api_key() do
      nil ->
        {:error, :api_key_not_configured}

      api_key ->
        url = @base_url <> path

        opts = [
          auth: {:basic, "#{api_key}:"},
          headers: [{"content-type", "application/x-www-form-urlencoded"}]
        ]

        opts =
          case method do
            :get -> Keyword.put(opts, :params, params)
            :delete -> Keyword.put(opts, :params, params)
            _ -> Keyword.put(opts, :form, flatten_params(params))
          end

        result = apply(http_client(), method, [url, opts])

        case result do
          {:ok, %{status: status, body: body}} when status in 200..299 ->
            {:ok, body}

          {:ok, %{status: _status, body: %{"error" => error}}} ->
            Logger.warning("Stripe API error: #{inspect(error)}")
            {:error, error}

          {:ok, %{status: status, body: body}} ->
            Logger.warning("Stripe API unexpected response: #{status} - #{inspect(body)}")
            {:error, {:unexpected_status, status, body}}

          {:error, reason} ->
            Logger.error("Stripe API request failed: #{inspect(reason)}")
            {:error, reason}
        end
    end
  end

  defp get_api_key do
    Application.get_env(:backend, :stripe)[:api_key]
  end

  defp http_client do
    Application.get_env(:backend, :http_client, Backend.HTTPClient.Impl)
  end

  # Flatten nested params for form encoding (Stripe expects param[key]=value format)
  defp flatten_params(params, prefix \\ nil) do
    Enum.flat_map(params, fn {key, value} ->
      full_key = if prefix, do: "#{prefix}[#{key}]", else: to_string(key)
      flatten_value(full_key, value)
    end)
  end

  defp flatten_value(key, value) when is_map(value) do
    flatten_params(value, key)
  end

  defp flatten_value(key, value) when is_list(value) do
    value
    |> Enum.with_index()
    |> Enum.flat_map(fn {item, index} -> flatten_list_item(key, index, item) end)
  end

  defp flatten_value(key, value) do
    [{String.to_atom(key), value}]
  end

  defp flatten_list_item(key, index, item) when is_map(item) do
    flatten_params(item, "#{key}[#{index}]")
  end

  defp flatten_list_item(key, index, item) do
    [{:"#{key}[#{index}]", item}]
  end

  # Constant-time string comparison to prevent timing attacks
  defp secure_compare(a, b) when byte_size(a) != byte_size(b), do: false

  defp secure_compare(a, b) do
    a_bytes = :binary.bin_to_list(a)
    b_bytes = :binary.bin_to_list(b)

    result =
      Enum.zip(a_bytes, b_bytes)
      |> Enum.reduce(0, fn {x, y}, acc -> Bitwise.bor(acc, Bitwise.bxor(x, y)) end)

    result == 0
  end
end
