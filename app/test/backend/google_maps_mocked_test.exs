defmodule Backend.GoogleMapsMockedTest do
  use ExUnit.Case, async: false

  import Mox

  alias Backend.GoogleMaps

  setup :verify_on_exit!

  setup do
    original = Application.get_env(:backend, :google_maps)
    Application.put_env(:backend, :google_maps, api_key: "gmaps_test_123")

    on_exit(fn ->
      if original,
        do: Application.put_env(:backend, :google_maps, original),
        else: Application.delete_env(:backend, :google_maps)
    end)

    :ok
  end

  test "covers geocoding and reverse geocoding variants" do
    expect(Backend.HTTPClientMock, :get, 4, fn url, opts ->
      assert url =~ "geocode"
      assert Keyword.has_key?(opts, :params)

      {:ok,
       %{status: 200, body: %{"status" => "OK", "results" => [%{"formatted_address" => "X"}]}}}
    end)

    assert {:ok, _} = GoogleMaps.geocode("1600 Amphitheatre Pkwy")
    assert {:ok, [_]} = GoogleMaps.geocode_all("1600 Amphitheatre Pkwy")
    assert {:ok, _} = GoogleMaps.reverse_geocode(37.42, -122.08)
    assert {:ok, [_]} = GoogleMaps.reverse_geocode_all(37.42, -122.08)
  end

  test "covers places and distance matrix endpoints" do
    expect(Backend.HTTPClientMock, :get, fn url, _opts ->
      assert url =~ "autocomplete"
      {:ok, %{status: 200, body: %{"status" => "OK", "predictions" => [%{"description" => "A"}]}}}
    end)

    assert {:ok, [_]} =
             GoogleMaps.autocomplete("coffee", location: {37.42, -122.08}, radius: 500)

    expect(Backend.HTTPClientMock, :get, fn url, _opts ->
      assert url =~ "details"
      {:ok, %{status: 200, body: %{"status" => "OK", "result" => %{"name" => "Cafe"}}}}
    end)

    assert {:ok, %{"name" => "Cafe"}} = GoogleMaps.place_details("place_123")

    expect(Backend.HTTPClientMock, :get, fn url, _opts ->
      assert url =~ "nearbysearch"
      {:ok, %{status: 200, body: %{"status" => "OK", "results" => [%{"name" => "Cafe"}]}}}
    end)

    assert {:ok, [_]} = GoogleMaps.nearby_search(37.42, -122.08, radius: 1000)

    expect(Backend.HTTPClientMock, :get, fn url, _opts ->
      assert url =~ "textsearch"
      {:ok, %{status: 200, body: %{"status" => "OK", "results" => [%{"name" => "Bakery"}]}}}
    end)

    assert {:ok, [_]} = GoogleMaps.text_search("bakery", location: {37.42, -122.08}, radius: 500)

    expect(Backend.HTTPClientMock, :get, fn url, opts ->
      assert url =~ "distancematrix"
      assert "A|37.42,-122.08" == opts[:params][:origins]
      assert "B" == opts[:params][:destinations]
      {:ok, %{status: 200, body: %{"status" => "OK", "rows" => []}}}
    end)

    assert {:ok, _} = GoogleMaps.distance_matrix(["A", {37.42, -122.08}], ["B"])
  end

  test "handles zero results and API/transport errors" do
    expect(Backend.HTTPClientMock, :get, fn _url, _opts ->
      {:ok, %{status: 200, body: %{"status" => "ZERO_RESULTS"}}}
    end)

    assert {:error, :no_results} = GoogleMaps.geocode("unknown")

    expect(Backend.HTTPClientMock, :get, fn _url, _opts ->
      {:ok, %{status: 200, body: %{"status" => "REQUEST_DENIED", "error_message" => "denied"}}}
    end)

    assert {:error, {"REQUEST_DENIED", "denied"}} = GoogleMaps.geocode_all("x")

    expect(Backend.HTTPClientMock, :get, fn _url, _opts ->
      {:ok, %{status: 500, body: %{"error" => "oops"}}}
    end)

    assert {:error, {:http_error, 500, _}} = GoogleMaps.text_search("x")

    expect(Backend.HTTPClientMock, :get, fn _url, _opts ->
      {:error, :timeout}
    end)

    assert {:error, :timeout} = GoogleMaps.distance_matrix(["A"], ["B"])
  end
end
