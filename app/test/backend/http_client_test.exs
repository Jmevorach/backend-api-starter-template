defmodule Backend.HTTPClientTest do
  @moduledoc """
  Tests for the HTTPClient module and its wrapper functions.
  """

  use ExUnit.Case, async: true

  import Mox

  alias Backend.HTTPClient

  setup :verify_on_exit!

  describe "impl/0" do
    test "returns configured HTTP client" do
      # The test environment configures HTTPClientMock
      assert HTTPClient.impl() == Backend.HTTPClientMock
    end

    test "returns Impl by default when not configured" do
      original = Application.get_env(:backend, :http_client)
      Application.delete_env(:backend, :http_client)

      assert HTTPClient.impl() == Backend.HTTPClient.Impl

      # Restore
      if original, do: Application.put_env(:backend, :http_client, original)
    end
  end

  describe "get/2" do
    test "delegates to configured implementation" do
      expect(Backend.HTTPClientMock, :get, fn url, opts ->
        assert url == "https://example.com"
        assert opts == [params: %{key: "value"}]
        {:ok, %{status: 200, body: %{"data" => "test"}}}
      end)

      assert {:ok, %{status: 200, body: %{"data" => "test"}}} =
               HTTPClient.get("https://example.com", params: %{key: "value"})
    end

    test "works with default empty opts" do
      expect(Backend.HTTPClientMock, :get, fn url, opts ->
        assert url == "https://example.com"
        assert opts == []
        {:ok, %{status: 200, body: %{}}}
      end)

      assert {:ok, _} = HTTPClient.get("https://example.com")
    end
  end

  describe "post/2" do
    test "delegates to configured implementation" do
      expect(Backend.HTTPClientMock, :post, fn url, opts ->
        assert url == "https://example.com/create"
        assert opts == [json: %{name: "test"}]
        {:ok, %{status: 201, body: %{"id" => "123"}}}
      end)

      assert {:ok, %{status: 201, body: %{"id" => "123"}}} =
               HTTPClient.post("https://example.com/create", json: %{name: "test"})
    end

    test "works with default empty opts" do
      expect(Backend.HTTPClientMock, :post, fn _url, opts ->
        assert opts == []
        {:ok, %{status: 201, body: %{}}}
      end)

      assert {:ok, _} = HTTPClient.post("https://example.com")
    end
  end

  describe "put/2" do
    test "delegates to configured implementation" do
      expect(Backend.HTTPClientMock, :put, fn url, opts ->
        assert url == "https://example.com/update/123"
        assert opts == [json: %{name: "updated"}]
        {:ok, %{status: 200, body: %{"updated" => true}}}
      end)

      assert {:ok, %{status: 200}} =
               HTTPClient.put("https://example.com/update/123", json: %{name: "updated"})
    end

    test "works with default empty opts" do
      expect(Backend.HTTPClientMock, :put, fn _url, opts ->
        assert opts == []
        {:ok, %{status: 200, body: %{}}}
      end)

      assert {:ok, _} = HTTPClient.put("https://example.com")
    end
  end

  describe "delete/2" do
    test "delegates to configured implementation" do
      expect(Backend.HTTPClientMock, :delete, fn url, opts ->
        assert url == "https://example.com/delete/123"
        assert opts == []
        {:ok, %{status: 204, body: nil}}
      end)

      assert {:ok, %{status: 204}} = HTTPClient.delete("https://example.com/delete/123")
    end

    test "passes options to implementation" do
      expect(Backend.HTTPClientMock, :delete, fn _url, opts ->
        assert opts == [headers: [{"x-api-key", "secret"}]]
        {:ok, %{status: 204, body: nil}}
      end)

      assert {:ok, _} =
               HTTPClient.delete("https://example.com", headers: [{"x-api-key", "secret"}])
    end
  end
end
