defmodule Backend.CheckrTest do
  use ExUnit.Case, async: false

  alias Backend.Checkr

  setup do
    original = Application.get_env(:backend, :checkr)

    on_exit(fn ->
      if original,
        do: Application.put_env(:backend, :checkr, original),
        else: Application.delete_env(:backend, :checkr)
    end)

    :ok
  end

  test "returns api_key_not_configured when missing config" do
    Application.delete_env(:backend, :checkr)
    assert {:error, :api_key_not_configured} = Checkr.list_candidates()
  end

  test "verifies valid webhook signatures" do
    payload = ~s({"id":"evt_xxx","type":"report.completed"})

    signature =
      :crypto.mac(:hmac, :sha256, "checkr_secret", payload)
      |> Base.encode16(case: :lower)

    assert {:ok, %{"id" => "evt_xxx"}} =
             Checkr.verify_webhook_signature(payload, signature, "checkr_secret")
  end
end
