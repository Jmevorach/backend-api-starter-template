defmodule Backend.StripeTest do
  use ExUnit.Case, async: false

  alias Backend.Stripe

  setup do
    original = Application.get_env(:backend, :stripe)

    on_exit(fn ->
      if original,
        do: Application.put_env(:backend, :stripe, original),
        else: Application.delete_env(:backend, :stripe)
    end)

    :ok
  end

  test "returns api_key_not_configured when missing config" do
    Application.delete_env(:backend, :stripe)
    assert {:error, :api_key_not_configured} = Stripe.list_customers()
  end

  test "verifies valid webhook signatures" do
    payload = ~s({"id":"evt_test","type":"customer.created"})
    timestamp = "1234567890"
    signed_payload = "#{timestamp}.#{payload}"

    signature =
      :crypto.mac(:hmac, :sha256, "whsec_test", signed_payload)
      |> Base.encode16(case: :lower)

    sig_header = "t=#{timestamp},v1=#{signature}"

    assert {:ok, %{"id" => "evt_test"}} =
             Stripe.verify_webhook_signature(payload, sig_header, "whsec_test")
  end
end
