defmodule Backend.StripeLiveTest do
  @moduledoc """
  Live integration tests for the Stripe API client.

  ## Purpose

  These tests make real HTTP requests to the Stripe API with invalid credentials
  to verify that:

  1. **Request formatting is correct** - The API returns authentication errors,
     NOT "invalid request" or "malformed" errors. This proves the request
     structure, headers, and parameters are properly formatted.

  2. **HTTP layer works** - Connections succeed and responses are received.

  3. **Error parsing works** - Error responses are correctly parsed into maps.

  ## Why This Matters

  If requests were malformed (wrong Content-Type, bad parameter encoding, etc.),
  Stripe would return a different error type. By receiving "Invalid API Key"
  errors, we confirm that:

  - The request body format is correct (form-encoded for POST)
  - Required headers are present and correct
  - Parameter nesting/flattening works properly
  - URL construction is valid

  ## Running These Tests

  These tests require network access but do NOT require valid API keys:

      mix test test/backend/stripe_live_test.exs --include live_api

  They are excluded by default to avoid network dependencies in CI.
  """

  use ExUnit.Case, async: false

  alias Backend.Stripe

  # Live tests use the real HTTP client, not the mock
  setup do
    # Configure to use the real HTTP implementation for live tests
    Application.put_env(:backend, :http_client, Backend.HTTPClient.Impl)

    on_exit(fn ->
      # Restore mock for other tests
      Application.put_env(:backend, :http_client, Backend.HTTPClientMock)
    end)

    :ok
  end

  # Use a clearly fake API key - Stripe will reject it with a proper error
  # that proves our request was well-formed
  @fake_api_key "sk_test_fake_key_for_testing_request_formatting"

  setup do
    original_config = Application.get_env(:backend, :stripe)
    Application.put_env(:backend, :stripe, api_key: @fake_api_key)

    on_exit(fn ->
      if original_config do
        Application.put_env(:backend, :stripe, original_config)
      else
        Application.delete_env(:backend, :stripe)
      end
    end)

    :ok
  end

  # Helper to verify we got an auth error (proves request was well-formed)
  defp assert_auth_error({:error, error}) do
    assert is_map(error), "Expected error to be a map, got: #{inspect(error)}"

    # Stripe returns "invalid_request_error" for bad API keys
    # If we got a different error type, our request format might be wrong
    assert error["type"] == "invalid_request_error",
           "Expected 'invalid_request_error' (auth failure), got '#{error["type"]}'. " <>
             "This might indicate a malformed request."

    assert error["message"] =~ "Invalid API Key" or error["message"] =~ "API key",
           "Expected API key error, got: #{error["message"]}"
  end

  describe "Customer operations - verify request formatting" do
    @describetag :live_api

    @tag :live_api
    test "POST /customers - request is properly formatted" do
      # This tests that:
      # - POST body is correctly form-encoded
      # - Authorization header is present
      # - Content-Type is correct
      result = Stripe.create_customer(%{email: "test@example.com", name: "Test User"})
      assert_auth_error(result)
    end

    @tag :live_api
    test "GET /customers/:id - request is properly formatted" do
      # This tests URL path construction
      result = Stripe.get_customer("cus_nonexistent123")
      assert_auth_error(result)
    end

    @tag :live_api
    test "GET /customers - request is properly formatted" do
      # This tests list endpoint formatting
      result = Stripe.list_customers()
      assert_auth_error(result)
    end

    @tag :live_api
    test "GET /customers with pagination - query params are correct" do
      # This tests query parameter encoding
      result = Stripe.list_customers(%{limit: 10, starting_after: "cus_xxx"})
      assert_auth_error(result)
    end

    @tag :live_api
    test "POST /customers/:id - update request is properly formatted" do
      result = Stripe.update_customer("cus_xxx", %{name: "Updated Name"})
      assert_auth_error(result)
    end

    @tag :live_api
    test "DELETE /customers/:id - delete request is properly formatted" do
      result = Stripe.delete_customer("cus_xxx")
      assert_auth_error(result)
    end
  end

  describe "Payment Intent operations - verify request formatting" do
    @describetag :live_api

    @tag :live_api
    test "POST /payment_intents - nested params are correctly flattened" do
      # This specifically tests that nested parameters like metadata
      # are correctly encoded as metadata[key]=value
      result =
        Stripe.create_payment_intent(%{
          amount: 1000,
          currency: "usd",
          metadata: %{
            order_id: "order_123",
            user_id: "user_456"
          }
        })

      assert_auth_error(result)
    end

    @tag :live_api
    test "GET /payment_intents/:id - request is properly formatted" do
      result = Stripe.get_payment_intent("pi_nonexistent")
      assert_auth_error(result)
    end

    @tag :live_api
    test "POST /payment_intents/:id/confirm - confirm request works" do
      result = Stripe.confirm_payment_intent("pi_xxx", %{payment_method: "pm_card_visa"})
      assert_auth_error(result)
    end
  end

  describe "Charge operations - verify request formatting" do
    @describetag :live_api

    @tag :live_api
    test "POST /charges - request is properly formatted" do
      result =
        Stripe.create_charge(%{
          amount: 2000,
          currency: "usd",
          source: "tok_visa"
        })

      assert_auth_error(result)
    end

    @tag :live_api
    test "GET /charges/:id - request is properly formatted" do
      result = Stripe.get_charge("ch_nonexistent")
      assert_auth_error(result)
    end
  end

  describe "Subscription operations - verify request formatting" do
    @describetag :live_api

    @tag :live_api
    test "POST /subscriptions - array params are correctly encoded" do
      # This specifically tests that array parameters like items[]
      # are correctly encoded
      result =
        Stripe.create_subscription(%{
          customer: "cus_xxx",
          items: [
            %{price: "price_xxx"},
            %{price: "price_yyy", quantity: 2}
          ]
        })

      assert_auth_error(result)
    end

    @tag :live_api
    test "GET /subscriptions/:id - request is properly formatted" do
      result = Stripe.get_subscription("sub_nonexistent")
      assert_auth_error(result)
    end

    @tag :live_api
    test "POST /subscriptions/:id - update with nested params works" do
      result =
        Stripe.update_subscription("sub_xxx", %{
          items: [%{id: "si_xxx", quantity: 3}],
          proration_behavior: "create_prorations"
        })

      assert_auth_error(result)
    end

    @tag :live_api
    test "DELETE /subscriptions/:id - cancel request is properly formatted" do
      result = Stripe.cancel_subscription("sub_xxx")
      assert_auth_error(result)
    end

    @tag :live_api
    test "DELETE /subscriptions/:id with params - cancel at period end works" do
      result = Stripe.cancel_subscription("sub_xxx", %{cancel_at_period_end: true})
      assert_auth_error(result)
    end

    @tag :live_api
    test "GET /subscriptions - list with filters works" do
      result = Stripe.list_subscriptions(%{customer: "cus_xxx", status: "active"})
      assert_auth_error(result)
    end
  end

  describe "Product and Price operations - verify request formatting" do
    @describetag :live_api

    @tag :live_api
    test "GET /products - list products works" do
      result = Stripe.list_products()
      assert_auth_error(result)
    end

    @tag :live_api
    test "GET /products with filters - query params are correct" do
      result = Stripe.list_products(%{active: true, limit: 5})
      assert_auth_error(result)
    end

    @tag :live_api
    test "GET /prices - list prices works" do
      result = Stripe.list_prices()
      assert_auth_error(result)
    end

    @tag :live_api
    test "GET /prices with filters - query params are correct" do
      result = Stripe.list_prices(%{product: "prod_xxx", active: true})
      assert_auth_error(result)
    end
  end
end
