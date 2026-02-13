defmodule Backend.CheckrMockedTest do
  use ExUnit.Case, async: false

  import Mox

  alias Backend.Checkr

  setup :verify_on_exit!

  setup do
    original = Application.get_env(:backend, :checkr)
    Application.put_env(:backend, :checkr, api_key: "ck_test_123", environment: "sandbox")

    on_exit(fn ->
      if original,
        do: Application.put_env(:backend, :checkr, original),
        else: Application.delete_env(:backend, :checkr)
    end)

    :ok
  end

  test "covers candidate, invitation, report, package and screening endpoints" do
    expect(Backend.HTTPClientMock, :post, fn url, _opts ->
      assert url =~ "/candidates"
      assert url =~ "checkr-staging"
      {:ok, %{status: 200, body: %{}}}
    end)

    assert {:ok, _} = Checkr.create_candidate(%{email: "a@example.com"})

    expect(Backend.HTTPClientMock, :get, fn url, _opts ->
      assert url =~ "/candidates/cand_123"
      {:ok, %{status: 200, body: %{}}}
    end)

    assert {:ok, _} = Checkr.get_candidate("cand_123")

    expect(Backend.HTTPClientMock, :get, fn url, _opts ->
      assert url =~ "/candidates"
      {:ok, %{status: 200, body: %{}}}
    end)

    assert {:ok, _} = Checkr.list_candidates()

    expect(Backend.HTTPClientMock, :post, fn url, _opts ->
      assert url =~ "/invitations"
      {:ok, %{status: 200, body: %{}}}
    end)

    assert {:ok, _} = Checkr.create_invitation(%{candidate_id: "cand_123"})

    expect(Backend.HTTPClientMock, :get, fn url, _opts ->
      assert url =~ "/invitations/inv_123"
      {:ok, %{status: 200, body: %{}}}
    end)

    assert {:ok, _} = Checkr.get_invitation("inv_123")

    expect(Backend.HTTPClientMock, :get, fn url, _opts ->
      assert url =~ "/invitations"
      {:ok, %{status: 200, body: %{}}}
    end)

    assert {:ok, _} = Checkr.list_invitations()

    expect(Backend.HTTPClientMock, :delete, fn url, _opts ->
      assert url =~ "/invitations/inv_123"
      {:ok, %{status: 200, body: %{}}}
    end)

    assert {:ok, _} = Checkr.cancel_invitation("inv_123")

    expect(Backend.HTTPClientMock, :post, fn url, _opts ->
      assert url =~ "/reports"
      {:ok, %{status: 200, body: %{}}}
    end)

    assert {:ok, _} = Checkr.create_report(%{package: "basic"})

    expect(Backend.HTTPClientMock, :get, fn url, _opts ->
      assert url =~ "/reports/rep_123"
      {:ok, %{status: 200, body: %{}}}
    end)

    assert {:ok, _} = Checkr.get_report("rep_123")

    expect(Backend.HTTPClientMock, :get, fn url, _opts ->
      assert url =~ "/reports"
      {:ok, %{status: 200, body: %{}}}
    end)

    assert {:ok, _} = Checkr.list_reports()

    expect(Backend.HTTPClientMock, :get, fn url, _opts ->
      assert url =~ "/packages"
      {:ok, %{status: 200, body: %{}}}
    end)

    assert {:ok, _} = Checkr.list_packages()

    expect(Backend.HTTPClientMock, :get, fn url, _opts ->
      assert url =~ "/packages/pkg_basic"
      {:ok, %{status: 200, body: %{}}}
    end)

    assert {:ok, _} = Checkr.get_package("pkg_basic")

    expect(Backend.HTTPClientMock, :get, fn url, _opts ->
      assert url =~ "/screenings/scr_123"
      {:ok, %{status: 200, body: %{}}}
    end)

    assert {:ok, _} = Checkr.get_screening("scr_123")
  end

  test "supports production URL and handles API/transport errors" do
    Application.put_env(:backend, :checkr, api_key: "ck_live_123", environment: "production")

    expect(Backend.HTTPClientMock, :get, fn url, _opts ->
      assert url =~ "api.checkr.com"
      {:ok, %{status: 400, body: %{"error" => %{"message" => "bad"}}}}
    end)

    assert {:error, _} = Checkr.list_candidates()

    expect(Backend.HTTPClientMock, :get, fn _url, _opts ->
      {:error, :timeout}
    end)

    assert {:error, :timeout} = Checkr.list_candidates()
  end
end
