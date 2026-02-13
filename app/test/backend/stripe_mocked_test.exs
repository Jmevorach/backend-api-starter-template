defmodule Backend.StripeMockedTest do
  use ExUnit.Case, async: false

  import Mox

  alias Backend.Stripe

  setup :verify_on_exit!

  setup do
    original = Application.get_env(:backend, :stripe)
    Application.put_env(:backend, :stripe, api_key: "sk_test_123")

    on_exit(fn ->
      if original,
        do: Application.put_env(:backend, :stripe, original),
        else: Application.delete_env(:backend, :stripe)
    end)

    :ok
  end

  test "covers customer, payment, subscription, product and price endpoints" do
    expect(Backend.HTTPClientMock, :post, fn url, _opts ->
      assert url =~ "/customers"
      {:ok, %{status: 200, body: %{"id" => "cus_123"}}}
    end)

    assert {:ok, _} = Stripe.create_customer(%{email: "a@example.com"})

    expect(Backend.HTTPClientMock, :get, fn url, _opts ->
      assert url =~ "/customers/cus_123"
      {:ok, %{status: 200, body: %{}}}
    end)

    assert {:ok, _} = Stripe.get_customer("cus_123")

    expect(Backend.HTTPClientMock, :post, fn url, _opts ->
      assert url =~ "/customers/cus_123"
      {:ok, %{status: 200, body: %{}}}
    end)

    assert {:ok, _} = Stripe.update_customer("cus_123", %{name: "New"})

    expect(Backend.HTTPClientMock, :get, fn url, _opts ->
      assert url =~ "/customers"
      {:ok, %{status: 200, body: %{}}}
    end)

    assert {:ok, _} = Stripe.list_customers()

    expect(Backend.HTTPClientMock, :delete, fn url, _opts ->
      assert url =~ "/customers/cus_123"
      {:ok, %{status: 200, body: %{}}}
    end)

    assert {:ok, _} = Stripe.delete_customer("cus_123")

    expect(Backend.HTTPClientMock, :post, fn url, _opts ->
      assert url =~ "/payment_intents"
      {:ok, %{status: 200, body: %{}}}
    end)

    assert {:ok, _} = Stripe.create_payment_intent(%{amount: 1000})

    expect(Backend.HTTPClientMock, :get, fn url, _opts ->
      assert url =~ "/payment_intents/pi_123"
      {:ok, %{status: 200, body: %{}}}
    end)

    assert {:ok, _} = Stripe.get_payment_intent("pi_123")

    expect(Backend.HTTPClientMock, :post, fn url, _opts ->
      assert url =~ "/payment_intents/pi_123/confirm"
      {:ok, %{status: 200, body: %{}}}
    end)

    assert {:ok, _} = Stripe.confirm_payment_intent("pi_123")

    expect(Backend.HTTPClientMock, :post, fn url, _opts ->
      assert url =~ "/charges"
      {:ok, %{status: 200, body: %{}}}
    end)

    assert {:ok, _} = Stripe.create_charge(%{amount: 500})

    expect(Backend.HTTPClientMock, :get, fn url, _opts ->
      assert url =~ "/charges/ch_123"
      {:ok, %{status: 200, body: %{}}}
    end)

    assert {:ok, _} = Stripe.get_charge("ch_123")

    expect(Backend.HTTPClientMock, :post, fn url, _opts ->
      assert url =~ "/subscriptions"
      {:ok, %{status: 200, body: %{}}}
    end)

    assert {:ok, _} = Stripe.create_subscription(%{customer: "cus_123"})

    expect(Backend.HTTPClientMock, :get, fn url, _opts ->
      assert url =~ "/subscriptions/sub_123"
      {:ok, %{status: 200, body: %{}}}
    end)

    assert {:ok, _} = Stripe.get_subscription("sub_123")

    expect(Backend.HTTPClientMock, :post, fn url, _opts ->
      assert url =~ "/subscriptions/sub_123"
      {:ok, %{status: 200, body: %{}}}
    end)

    assert {:ok, _} = Stripe.update_subscription("sub_123", %{metadata: %{x: "y"}})

    expect(Backend.HTTPClientMock, :delete, fn url, _opts ->
      assert url =~ "/subscriptions/sub_123"
      {:ok, %{status: 200, body: %{}}}
    end)

    assert {:ok, _} = Stripe.cancel_subscription("sub_123")

    expect(Backend.HTTPClientMock, :get, fn url, _opts ->
      assert url =~ "/subscriptions"
      {:ok, %{status: 200, body: %{}}}
    end)

    assert {:ok, _} = Stripe.list_subscriptions()

    expect(Backend.HTTPClientMock, :get, fn url, _opts ->
      assert url =~ "/products"
      {:ok, %{status: 200, body: %{}}}
    end)

    assert {:ok, _} = Stripe.list_products()

    expect(Backend.HTTPClientMock, :get, fn url, _opts ->
      assert url =~ "/prices"
      {:ok, %{status: 200, body: %{}}}
    end)

    assert {:ok, _} = Stripe.list_prices()
  end

  test "returns normalized API and transport errors" do
    expect(Backend.HTTPClientMock, :get, fn _url, _opts ->
      {:ok, %{status: 400, body: %{"error" => %{"message" => "bad"}}}}
    end)

    assert {:error, _} = Stripe.list_customers()

    expect(Backend.HTTPClientMock, :get, fn _url, _opts ->
      {:error, :timeout}
    end)

    assert {:error, :timeout} = Stripe.list_customers()
  end
end
