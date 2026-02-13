defmodule Backend.StripeMockedTest do
  @moduledoc """
  Mocked tests for the Stripe API client.

  These tests use Mox to mock HTTP responses with realistic Stripe API
  response formats, allowing us to test all code paths without making real
  API calls.

  API response formats are based on:
  https://stripe.com/docs/api
  """

  use ExUnit.Case, async: true

  import Mox

  alias Backend.Stripe

  # Make sure mocks are verified when the test exits
  setup :verify_on_exit!

  setup do
    # Configure API key for tests
    Application.put_env(:backend, :stripe, api_key: "sk_test_mock_key")

    on_exit(fn ->
      Application.delete_env(:backend, :stripe)
    end)

    :ok
  end

  # ===========================================================================
  # Realistic API Response Fixtures (based on Stripe API docs)
  # ===========================================================================

  defp customer_response(overrides \\ %{}) do
    Map.merge(
      %{
        "id" => "cus_NffrFeUfNV2Hib",
        "object" => "customer",
        "address" => nil,
        "balance" => 0,
        "created" => 1_680_893_993,
        "currency" => nil,
        "default_source" => nil,
        "delinquent" => false,
        "description" => nil,
        "discount" => nil,
        "email" => "jennyrosen@example.com",
        "invoice_prefix" => "0759376C",
        "invoice_settings" => %{
          "custom_fields" => nil,
          "default_payment_method" => nil,
          "footer" => nil
        },
        "livemode" => false,
        "metadata" => %{},
        "name" => "Jenny Rosen",
        "phone" => "+18008675309",
        "preferred_locales" => [],
        "shipping" => nil,
        "tax_exempt" => "none",
        "test_clock" => nil
      },
      overrides
    )
  end

  defp customers_list_response(customers \\ []) do
    %{
      "object" => "list",
      "url" => "/v1/customers",
      "has_more" => false,
      "data" => customers
    }
  end

  defp payment_intent_response(overrides \\ %{}) do
    Map.merge(
      %{
        "id" => "pi_3MtwBwLkdIwHu7ix28a3tqPa",
        "object" => "payment_intent",
        "amount" => 2000,
        "amount_capturable" => 0,
        "amount_details" => %{
          "tip" => %{}
        },
        "amount_received" => 0,
        "application" => nil,
        "application_fee_amount" => nil,
        "automatic_payment_methods" => %{
          "enabled" => true
        },
        "canceled_at" => nil,
        "cancellation_reason" => nil,
        "capture_method" => "automatic",
        "client_secret" => "pi_3MtwBwLkdIwHu7ix28a3tqPa_secret_YrKJUKribcBjcG8HVhfZluoGH",
        "confirmation_method" => "automatic",
        "created" => 1_680_800_504,
        "currency" => "usd",
        "customer" => nil,
        "description" => nil,
        "invoice" => nil,
        "last_payment_error" => nil,
        "latest_charge" => nil,
        "livemode" => false,
        "metadata" => %{},
        "next_action" => nil,
        "on_behalf_of" => nil,
        "payment_method" => nil,
        "payment_method_options" => %{
          "card" => %{
            "installments" => nil,
            "mandate_options" => nil,
            "network" => nil,
            "request_three_d_secure" => "automatic"
          },
          "link" => %{
            "persistent_token" => nil
          }
        },
        "payment_method_types" => ["card", "link"],
        "processing" => nil,
        "receipt_email" => nil,
        "review" => nil,
        "setup_future_usage" => nil,
        "shipping" => nil,
        "source" => nil,
        "statement_descriptor" => nil,
        "statement_descriptor_suffix" => nil,
        "status" => "requires_payment_method",
        "transfer_data" => nil,
        "transfer_group" => nil
      },
      overrides
    )
  end

  defp charge_response(overrides \\ %{}) do
    Map.merge(
      %{
        "id" => "ch_3MmlLrLkdIwHu7ix0snN0B15",
        "object" => "charge",
        "amount" => 1099,
        "amount_captured" => 1099,
        "amount_refunded" => 0,
        "application" => nil,
        "application_fee" => nil,
        "application_fee_amount" => nil,
        "balance_transaction" => "txn_3MmlLrLkdIwHu7ix0uke3Ezy",
        "billing_details" => %{
          "address" => %{
            "city" => nil,
            "country" => nil,
            "line1" => nil,
            "line2" => nil,
            "postal_code" => nil,
            "state" => nil
          },
          "email" => nil,
          "name" => nil,
          "phone" => nil
        },
        "calculated_statement_descriptor" => "STRIPE* EXAMPLE",
        "captured" => true,
        "created" => 1_679_090_539,
        "currency" => "usd",
        "customer" => nil,
        "description" => nil,
        "disputed" => false,
        "failure_balance_transaction" => nil,
        "failure_code" => nil,
        "failure_message" => nil,
        "fraud_details" => %{},
        "invoice" => nil,
        "livemode" => false,
        "metadata" => %{},
        "on_behalf_of" => nil,
        "outcome" => %{
          "network_status" => "approved_by_network",
          "reason" => nil,
          "risk_level" => "normal",
          "risk_score" => 32,
          "seller_message" => "Payment complete.",
          "type" => "authorized"
        },
        "paid" => true,
        "payment_intent" => nil,
        "payment_method" => "pm_1MmlLrLkdIwHu7ixIJwEWSNR",
        "payment_method_details" => %{
          "card" => %{
            "brand" => "visa",
            "checks" => %{
              "address_line1_check" => nil,
              "address_postal_code_check" => nil,
              "cvc_check" => "pass"
            },
            "country" => "US",
            "exp_month" => 3,
            "exp_year" => 2024,
            "fingerprint" => "mToisGZ01V71BCos",
            "funding" => "credit",
            "installments" => nil,
            "last4" => "4242",
            "mandate" => nil,
            "network" => "visa",
            "three_d_secure" => nil,
            "wallet" => nil
          },
          "type" => "card"
        },
        "receipt_email" => nil,
        "receipt_number" => nil,
        "receipt_url" =>
          "https://pay.stripe.com/receipts/payment/CAcaFwoVYWNjdF8xTTJKVGtMa2RJd0h1N2l4",
        "refunded" => false,
        "refunds" => %{
          "object" => "list",
          "data" => [],
          "has_more" => false,
          "total_count" => 0,
          "url" => "/v1/charges/ch_3MmlLrLkdIwHu7ix0snN0B15/refunds"
        },
        "review" => nil,
        "shipping" => nil,
        "source_transfer" => nil,
        "statement_descriptor" => nil,
        "statement_descriptor_suffix" => nil,
        "status" => "succeeded",
        "transfer_data" => nil,
        "transfer_group" => nil
      },
      overrides
    )
  end

  defp subscription_response(overrides \\ %{}) do
    Map.merge(
      %{
        "id" => "sub_1MowQVLkdIwHu7ixeRlqHVzs",
        "object" => "subscription",
        "application" => nil,
        "application_fee_percent" => nil,
        "automatic_tax" => %{
          "enabled" => false
        },
        "billing_cycle_anchor" => 1_679_609_767,
        "billing_thresholds" => nil,
        "cancel_at" => nil,
        "cancel_at_period_end" => false,
        "canceled_at" => nil,
        "collection_method" => "charge_automatically",
        "created" => 1_679_609_767,
        "currency" => "usd",
        "current_period_end" => 1_682_288_167,
        "current_period_start" => 1_679_609_767,
        "customer" => "cus_Na6dX7aXxi11N4",
        "days_until_due" => nil,
        "default_payment_method" => nil,
        "default_source" => nil,
        "default_tax_rates" => [],
        "description" => nil,
        "discount" => nil,
        "ended_at" => nil,
        "items" => %{
          "object" => "list",
          "data" => [
            %{
              "id" => "si_Na6dzxczY5fwHx",
              "object" => "subscription_item",
              "billing_thresholds" => nil,
              "created" => 1_679_609_768,
              "metadata" => %{},
              "plan" => %{
                "id" => "price_1MowQULkdIwHu7ixraBm864M",
                "object" => "plan",
                "active" => true,
                "aggregate_usage" => nil,
                "amount" => 1000,
                "amount_decimal" => "1000",
                "billing_scheme" => "per_unit",
                "created" => 1_679_609_766,
                "currency" => "usd",
                "interval" => "month",
                "interval_count" => 1,
                "livemode" => false,
                "metadata" => %{},
                "nickname" => nil,
                "product" => "prod_Na6dGcTsmU0I4R",
                "tiers_mode" => nil,
                "transform_usage" => nil,
                "trial_period_days" => nil,
                "usage_type" => "licensed"
              },
              "price" => %{
                "id" => "price_1MowQULkdIwHu7ixraBm864M",
                "object" => "price",
                "active" => true,
                "billing_scheme" => "per_unit",
                "created" => 1_679_609_766,
                "currency" => "usd",
                "custom_unit_amount" => nil,
                "livemode" => false,
                "lookup_key" => nil,
                "metadata" => %{},
                "nickname" => nil,
                "product" => "prod_Na6dGcTsmU0I4R",
                "recurring" => %{
                  "aggregate_usage" => nil,
                  "interval" => "month",
                  "interval_count" => 1,
                  "trial_period_days" => nil,
                  "usage_type" => "licensed"
                },
                "tax_behavior" => "unspecified",
                "tiers_mode" => nil,
                "transform_quantity" => nil,
                "type" => "recurring",
                "unit_amount" => 1000,
                "unit_amount_decimal" => "1000"
              },
              "quantity" => 1,
              "subscription" => "sub_1MowQVLkdIwHu7ixeRlqHVzs",
              "tax_rates" => []
            }
          ],
          "has_more" => false,
          "total_count" => 1,
          "url" => "/v1/subscription_items?subscription=sub_1MowQVLkdIwHu7ixeRlqHVzs"
        },
        "latest_invoice" => "in_1MowQWLkdIwHu7ixuzkSPfKd",
        "livemode" => false,
        "metadata" => %{},
        "next_pending_invoice_item_invoice" => nil,
        "on_behalf_of" => nil,
        "pause_collection" => nil,
        "payment_settings" => %{
          "payment_method_options" => nil,
          "payment_method_types" => nil,
          "save_default_payment_method" => "off"
        },
        "pending_invoice_item_interval" => nil,
        "pending_setup_intent" => nil,
        "pending_update" => nil,
        "plan" => %{
          "id" => "price_1MowQULkdIwHu7ixraBm864M",
          "object" => "plan",
          "active" => true,
          "amount" => 1000,
          "currency" => "usd",
          "interval" => "month",
          "interval_count" => 1,
          "livemode" => false,
          "product" => "prod_Na6dGcTsmU0I4R"
        },
        "quantity" => 1,
        "schedule" => nil,
        "start_date" => 1_679_609_767,
        "status" => "active",
        "test_clock" => nil,
        "transfer_data" => nil,
        "trial_end" => nil,
        "trial_start" => nil
      },
      overrides
    )
  end

  defp deleted_response(id) do
    %{
      "id" => id,
      "object" => "customer",
      "deleted" => true
    }
  end

  defp error_response(type, message, code \\ nil) do
    error = %{
      "type" => type,
      "message" => message
    }

    error = if code, do: Map.put(error, "code", code), else: error

    %{"error" => error}
  end

  # ===========================================================================
  # Customer Tests
  # ===========================================================================

  describe "create_customer/1 with mocked responses" do
    test "creates customer successfully" do
      Backend.HTTPClientMock
      |> expect(:post, fn url, opts ->
        assert url =~ "api.stripe.com/v1/customers"
        assert opts[:auth] == {:basic, "sk_test_mock_key:"}
        assert Keyword.has_key?(opts, :form)

        {:ok, %{status: 200, body: customer_response()}}
      end)

      result = Stripe.create_customer(%{email: "jennyrosen@example.com", name: "Jenny Rosen"})

      assert {:ok, customer} = result
      assert customer["id"] == "cus_NffrFeUfNV2Hib"
      assert customer["email"] == "jennyrosen@example.com"
      assert customer["name"] == "Jenny Rosen"
    end

    test "creates customer with metadata" do
      Backend.HTTPClientMock
      |> expect(:post, fn _url, opts ->
        form_data = opts[:form]
        # Verify metadata is flattened correctly
        assert Keyword.has_key?(form_data, :"metadata[order_id]")

        {:ok,
         %{
           status: 200,
           body: customer_response(%{"metadata" => %{"order_id" => "12345"}})
         }}
      end)

      result =
        Stripe.create_customer(%{
          email: "test@example.com",
          metadata: %{order_id: "12345"}
        })

      assert {:ok, customer} = result
      assert customer["metadata"]["order_id"] == "12345"
    end

    test "handles card_declined error" do
      Backend.HTTPClientMock
      |> expect(:post, fn _url, _opts ->
        {:ok,
         %{
           status: 402,
           body: error_response("card_error", "Your card was declined.", "card_declined")
         }}
      end)

      result = Stripe.create_customer(%{email: "test@example.com"})

      assert {:error, error} = result
      assert error["type"] == "card_error"
      assert error["code"] == "card_declined"
    end

    test "handles invalid_request_error" do
      Backend.HTTPClientMock
      |> expect(:post, fn _url, _opts ->
        {:ok,
         %{status: 400, body: error_response("invalid_request_error", "Invalid email address")}}
      end)

      result = Stripe.create_customer(%{email: "invalid"})

      assert {:error, error} = result
      assert error["type"] == "invalid_request_error"
    end
  end

  describe "get_customer/1 with mocked responses" do
    test "retrieves customer successfully" do
      Backend.HTTPClientMock
      |> expect(:get, fn url, _opts ->
        assert url =~ "api.stripe.com/v1/customers/cus_NffrFeUfNV2Hib"

        {:ok, %{status: 200, body: customer_response()}}
      end)

      result = Stripe.get_customer("cus_NffrFeUfNV2Hib")

      assert {:ok, customer} = result
      assert customer["id"] == "cus_NffrFeUfNV2Hib"
    end

    test "handles customer not found" do
      Backend.HTTPClientMock
      |> expect(:get, fn _url, _opts ->
        {:ok,
         %{
           status: 404,
           body:
             error_response(
               "invalid_request_error",
               "No such customer: 'cus_nonexistent'"
             )
         }}
      end)

      result = Stripe.get_customer("cus_nonexistent")

      assert {:error, error} = result
      assert error["message"] =~ "No such customer"
    end
  end

  describe "list_customers/1 with mocked responses" do
    test "lists customers successfully" do
      Backend.HTTPClientMock
      |> expect(:get, fn url, opts ->
        assert url =~ "api.stripe.com/v1/customers"
        assert opts[:params][:limit] == 10

        {:ok, %{status: 200, body: customers_list_response([customer_response()])}}
      end)

      result = Stripe.list_customers(%{limit: 10})

      assert {:ok, response} = result
      assert response["object"] == "list"
      assert length(response["data"]) == 1
    end

    test "lists customers with pagination" do
      Backend.HTTPClientMock
      |> expect(:get, fn _url, opts ->
        assert opts[:params][:starting_after] == "cus_previous"

        {:ok,
         %{
           status: 200,
           body:
             customers_list_response([customer_response()])
             |> Map.put("has_more", true)
         }}
      end)

      result = Stripe.list_customers(%{starting_after: "cus_previous"})

      assert {:ok, response} = result
      assert response["has_more"] == true
    end
  end

  describe "delete_customer/1 with mocked responses" do
    test "deletes customer successfully" do
      Backend.HTTPClientMock
      |> expect(:delete, fn url, _opts ->
        assert url =~ "api.stripe.com/v1/customers/cus_NffrFeUfNV2Hib"

        {:ok, %{status: 200, body: deleted_response("cus_NffrFeUfNV2Hib")}}
      end)

      result = Stripe.delete_customer("cus_NffrFeUfNV2Hib")

      assert {:ok, response} = result
      assert response["deleted"] == true
    end
  end

  # ===========================================================================
  # Payment Intent Tests
  # ===========================================================================

  describe "create_payment_intent/1 with mocked responses" do
    test "creates payment intent successfully" do
      Backend.HTTPClientMock
      |> expect(:post, fn url, opts ->
        assert url =~ "api.stripe.com/v1/payment_intents"
        form_data = opts[:form]
        assert Keyword.get(form_data, :amount) == 2000
        assert Keyword.get(form_data, :currency) == "usd"

        {:ok, %{status: 200, body: payment_intent_response()}}
      end)

      result = Stripe.create_payment_intent(%{amount: 2000, currency: "usd"})

      assert {:ok, pi} = result
      assert pi["id"] =~ "pi_"
      assert pi["amount"] == 2000
      assert pi["currency"] == "usd"
      assert pi["client_secret"]
    end

    test "creates payment intent with metadata" do
      Backend.HTTPClientMock
      |> expect(:post, fn _url, opts ->
        form_data = opts[:form]
        assert Keyword.has_key?(form_data, :"metadata[order_id]")

        {:ok,
         %{
           status: 200,
           body: payment_intent_response(%{"metadata" => %{"order_id" => "order_123"}})
         }}
      end)

      result =
        Stripe.create_payment_intent(%{
          amount: 2000,
          currency: "usd",
          metadata: %{order_id: "order_123"}
        })

      assert {:ok, pi} = result
      assert pi["metadata"]["order_id"] == "order_123"
    end
  end

  describe "confirm_payment_intent/2 with mocked responses" do
    test "confirms payment intent successfully" do
      Backend.HTTPClientMock
      |> expect(:post, fn url, _opts ->
        assert url =~ "api.stripe.com/v1/payment_intents/pi_123/confirm"

        {:ok, %{status: 200, body: payment_intent_response(%{"status" => "succeeded"})}}
      end)

      result = Stripe.confirm_payment_intent("pi_123", %{payment_method: "pm_card_visa"})

      assert {:ok, pi} = result
      assert pi["status"] == "succeeded"
    end
  end

  # ===========================================================================
  # Charge Tests
  # ===========================================================================

  describe "create_charge/1 with mocked responses" do
    test "creates charge successfully" do
      Backend.HTTPClientMock
      |> expect(:post, fn url, _opts ->
        assert url =~ "api.stripe.com/v1/charges"

        {:ok, %{status: 200, body: charge_response()}}
      end)

      result = Stripe.create_charge(%{amount: 1099, currency: "usd", source: "tok_visa"})

      assert {:ok, charge} = result
      assert charge["id"] =~ "ch_"
      assert charge["amount"] == 1099
      assert charge["paid"] == true
      assert charge["status"] == "succeeded"
    end
  end

  # ===========================================================================
  # Subscription Tests
  # ===========================================================================

  describe "create_subscription/1 with mocked responses" do
    test "creates subscription successfully" do
      Backend.HTTPClientMock
      |> expect(:post, fn url, opts ->
        assert url =~ "api.stripe.com/v1/subscriptions"
        form_data = opts[:form]
        assert Keyword.get(form_data, :customer) == "cus_Na6dX7aXxi11N4"
        # Items should be flattened
        assert Keyword.has_key?(form_data, :"items[0][price]")

        {:ok, %{status: 200, body: subscription_response()}}
      end)

      result =
        Stripe.create_subscription(%{
          customer: "cus_Na6dX7aXxi11N4",
          items: [%{price: "price_1MowQULkdIwHu7ixraBm864M"}]
        })

      assert {:ok, sub} = result
      assert sub["id"] =~ "sub_"
      assert sub["status"] == "active"
      assert sub["customer"] == "cus_Na6dX7aXxi11N4"
    end
  end

  describe "cancel_subscription/2 with mocked responses" do
    test "cancels subscription immediately" do
      Backend.HTTPClientMock
      |> expect(:delete, fn url, _opts ->
        assert url =~ "api.stripe.com/v1/subscriptions/sub_1MowQVLkdIwHu7ixeRlqHVzs"

        {:ok, %{status: 200, body: subscription_response(%{"status" => "canceled"})}}
      end)

      result = Stripe.cancel_subscription("sub_1MowQVLkdIwHu7ixeRlqHVzs")

      assert {:ok, sub} = result
      assert sub["status"] == "canceled"
    end

    test "cancels subscription at period end" do
      Backend.HTTPClientMock
      |> expect(:delete, fn _url, opts ->
        assert opts[:params][:cancel_at_period_end] == true

        {:ok, %{status: 200, body: subscription_response(%{"cancel_at_period_end" => true})}}
      end)

      result =
        Stripe.cancel_subscription("sub_1MowQVLkdIwHu7ixeRlqHVzs", %{
          cancel_at_period_end: true
        })

      assert {:ok, sub} = result
      assert sub["cancel_at_period_end"] == true
    end
  end

  # ===========================================================================
  # Error Handling Tests
  # ===========================================================================

  describe "error handling" do
    test "handles rate limiting (429)" do
      Backend.HTTPClientMock
      |> expect(:get, fn _url, _opts ->
        {:ok, %{status: 429, body: error_response("rate_limit_error", "Too many requests")}}
      end)

      result = Stripe.get_customer("cus_123")

      assert {:error, error} = result
      assert error["type"] == "rate_limit_error"
    end

    test "handles authentication error (401)" do
      Backend.HTTPClientMock
      |> expect(:get, fn _url, _opts ->
        {:ok,
         %{
           status: 401,
           body: error_response("authentication_error", "Invalid API Key provided")
         }}
      end)

      result = Stripe.get_customer("cus_123")

      assert {:error, error} = result
      assert error["type"] == "authentication_error"
    end

    test "handles network error" do
      Backend.HTTPClientMock
      |> expect(:get, fn _url, _opts ->
        {:error, %Req.TransportError{reason: :timeout}}
      end)

      result = Stripe.get_customer("cus_123")

      assert {:error, %Req.TransportError{reason: :timeout}} = result
    end

    test "handles unexpected status code" do
      Backend.HTTPClientMock
      |> expect(:get, fn _url, _opts ->
        {:ok, %{status: 503, body: "Service Unavailable"}}
      end)

      result = Stripe.get_customer("cus_123")

      assert {:error, {:unexpected_status, 503, _body}} = result
    end
  end
end
