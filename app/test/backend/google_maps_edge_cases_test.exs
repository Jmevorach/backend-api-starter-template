defmodule Backend.GoogleMapsEdgeCasesTest do
  @moduledoc """
  Edge case tests for Google Maps module to improve code coverage.
  """

  use ExUnit.Case, async: true

  import Mox

  alias Backend.GoogleMaps

  setup :verify_on_exit!

  setup do
    Application.put_env(:backend, :google_maps, api_key: "test_key")

    stub(Backend.HTTPClientMock, :get, fn _url, _opts ->
      {:ok,
       %{
         status: 200,
         body: %{
           "status" => "OK",
           "results" => [%{"formatted_address" => "Test Address"}]
         }
       }}
    end)

    on_exit(fn ->
      Application.delete_env(:backend, :google_maps)
    end)

    :ok
  end

  describe "maybe_add helper coverage" do
    test "geocode with all optional params" do
      expect(Backend.HTTPClientMock, :get, fn _url, opts ->
        params = opts[:params]
        assert params[:region] == "us"
        assert params[:language] == "en"
        assert params[:bounds] == "34.0,-118.5|34.1,-118.4"
        assert params[:components] == "country:US"

        {:ok,
         %{
           status: 200,
           body: %{
             "status" => "OK",
             "results" => [%{"formatted_address" => "Test"}]
           }
         }}
      end)

      GoogleMaps.geocode("Test Address",
        region: "us",
        language: "en",
        bounds: "34.0,-118.5|34.1,-118.4",
        components: "country:US"
      )
    end

    test "autocomplete with all optional params" do
      expect(Backend.HTTPClientMock, :get, fn _url, opts ->
        params = opts[:params]
        assert params[:types] == "geocode"
        assert is_binary(params[:location])
        assert params[:radius] == 5000
        assert params[:components] == "country:us"
        assert params[:language] == "en"
        assert params[:sessiontoken] == "test_token"

        {:ok,
         %{
           status: 200,
           body: %{
             "status" => "OK",
             "predictions" => []
           }
         }}
      end)

      GoogleMaps.autocomplete("test",
        types: "geocode",
        location: {37.7749, -122.4194},
        radius: 5000,
        components: "country:us",
        language: "en",
        sessiontoken: "test_token"
      )
    end

    test "place_details with all optional params" do
      expect(Backend.HTTPClientMock, :get, fn _url, opts ->
        params = opts[:params]
        assert params[:fields] == "name,geometry"
        assert params[:language] == "es"
        assert params[:sessiontoken] == "session123"

        {:ok,
         %{
           status: 200,
           body: %{
             "status" => "OK",
             "result" => %{"name" => "Test Place"}
           }
         }}
      end)

      GoogleMaps.place_details("ChIJ123",
        fields: "name,geometry",
        language: "es",
        sessiontoken: "session123"
      )
    end

    test "nearby_search with all optional params" do
      expect(Backend.HTTPClientMock, :get, fn _url, opts ->
        params = opts[:params]
        assert params[:type] == "restaurant"
        assert params[:keyword] == "pizza"
        assert params[:rankby] == "distance"
        assert params[:language] == "it"
        assert params[:name] == "Test"
        assert params[:pagetoken] == "next_page"

        {:ok,
         %{
           status: 200,
           body: %{
             "status" => "OK",
             "results" => []
           }
         }}
      end)

      GoogleMaps.nearby_search(37.7749, -122.4194,
        radius: 1000,
        type: "restaurant",
        keyword: "pizza",
        rankby: "distance",
        language: "it",
        name: "Test",
        pagetoken: "next_page"
      )
    end

    test "text_search with all optional params" do
      expect(Backend.HTTPClientMock, :get, fn _url, opts ->
        params = opts[:params]
        # Check location is a string (float formatting may vary)
        assert is_binary(params[:location])
        assert params[:radius] == 10_000
        assert params[:type] == "cafe"
        assert params[:language] == "fr"
        assert params[:pagetoken] == "next_page_token"

        {:ok,
         %{
           status: 200,
           body: %{
             "status" => "OK",
             "results" => []
           }
         }}
      end)

      GoogleMaps.text_search("coffee shops",
        location: {40.7128, -74.006},
        radius: 10_000,
        type: "cafe",
        language: "fr",
        pagetoken: "next_page_token"
      )
    end

    test "distance_matrix with all optional params" do
      expect(Backend.HTTPClientMock, :get, fn _url, opts ->
        params = opts[:params]
        assert params[:mode] == "driving"
        assert params[:units] == "metric"
        assert params[:avoid] == "tolls"
        assert params[:departure_time] == "now"

        {:ok,
         %{
           status: 200,
           body: %{
             "status" => "OK",
             "rows" => [%{"elements" => []}]
           }
         }}
      end)

      GoogleMaps.distance_matrix(["NYC"], ["LA"],
        mode: "driving",
        units: "metric",
        avoid: "tolls",
        departure_time: "now"
      )
    end
  end

  describe "format_locations coverage" do
    test "distance_matrix with mixed origins" do
      expect(Backend.HTTPClientMock, :get, fn _url, opts ->
        params = opts[:params]
        # Coordinate tuple and address string mixed
        assert params[:origins] == "37.7749,-122.4194|San Francisco, CA"

        {:ok, %{status: 200, body: %{"status" => "OK", "rows" => []}}}
      end)

      GoogleMaps.distance_matrix(
        [{37.7749, -122.4194}, "San Francisco, CA"],
        ["Los Angeles, CA"]
      )
    end
  end

  describe "reverse_geocode_all/3" do
    test "returns all results" do
      expect(Backend.HTTPClientMock, :get, fn _url, _opts ->
        {:ok,
         %{
           status: 200,
           body: %{
             "status" => "OK",
             "results" => [
               %{"formatted_address" => "Address 1"},
               %{"formatted_address" => "Address 2"}
             ]
           }
         }}
      end)

      {:ok, results} = GoogleMaps.reverse_geocode_all(37.7749, -122.4194)
      assert length(results) == 2
    end

    test "handles zero results" do
      expect(Backend.HTTPClientMock, :get, fn _url, _opts ->
        {:ok, %{status: 200, body: %{"status" => "ZERO_RESULTS", "results" => []}}}
      end)

      {:ok, results} = GoogleMaps.reverse_geocode_all(0.0, 0.0)
      assert results == []
    end
  end

  describe "distance_matrix error handling" do
    test "handles api error status" do
      expect(Backend.HTTPClientMock, :get, fn _url, _opts ->
        {:ok, %{status: 200, body: %{"status" => "INVALID_REQUEST"}}}
      end)

      result = GoogleMaps.distance_matrix(["NYC"], ["LA"])
      assert {:error, {:api_error, "INVALID_REQUEST"}} = result
    end
  end
end
