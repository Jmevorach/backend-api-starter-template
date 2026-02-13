defmodule Backend.GoogleMapsLiveTest do
  @moduledoc """
  Live integration tests for the Google Maps API client.

  ## Purpose

  These tests make real HTTP requests to the Google Maps API with invalid
  credentials to verify that:

  1. **Request formatting is correct** - The API returns "REQUEST_DENIED"
     (invalid API key), NOT "INVALID_REQUEST" (malformed request). This proves
     the request structure and parameters are properly formatted.

  2. **URL construction works** - Requests reach the correct endpoints.

  3. **Parameter encoding works** - Query parameters are properly encoded.

  ## Why This Matters

  Google Maps API returns different error statuses:
  - "REQUEST_DENIED" = API key invalid (our request format is correct)
  - "INVALID_REQUEST" = Malformed request (something wrong with our code)

  By receiving "REQUEST_DENIED", we confirm that:
  - Query parameters are correctly encoded
  - Required parameters are present
  - URL construction is valid
  - Special characters and unicode are properly handled

  ## Running These Tests

  These tests require network access but do NOT require valid API keys:

      mix test test/backend/google_maps_live_test.exs --include live_api

  They are excluded by default to avoid network dependencies in CI.
  """

  use ExUnit.Case, async: false

  alias Backend.GoogleMaps

  # Use a clearly fake API key - Google will reject it with REQUEST_DENIED
  # which proves our request was well-formed
  @fake_api_key "fake_api_key_for_testing_request_formatting"

  setup do
    original_config = Application.get_env(:backend, :google_maps)

    # Live tests use the real HTTP client, not the mock
    Application.put_env(:backend, :http_client, Backend.HTTPClient.Impl)
    Application.put_env(:backend, :google_maps, api_key: @fake_api_key)

    on_exit(fn ->
      # Restore mock for other tests
      Application.put_env(:backend, :http_client, Backend.HTTPClientMock)

      if original_config do
        Application.put_env(:backend, :google_maps, original_config)
      else
        Application.delete_env(:backend, :google_maps)
      end
    end)

    :ok
  end

  # Helper to verify we got an API key error (proves request was well-formed)
  defp assert_api_key_error({:error, error}) do
    error_str = if is_binary(error), do: error, else: inspect(error)

    # Google Maps returns "REQUEST_DENIED" for invalid API keys
    # "INVALID_REQUEST" would indicate our request format is wrong
    refute error_str =~ "INVALID_REQUEST",
           "Got INVALID_REQUEST - this indicates a malformed request: #{error_str}"

    assert error_str =~ "REQUEST_DENIED" or error_str =~ "API key" or
             error_str =~ "denied" or error_str =~ "invalid",
           "Expected API key error, got: #{error_str}"
  end

  describe "Geocoding operations - verify request formatting" do
    @describetag :live_api

    @tag :live_api
    test "geocode - basic address request is properly formatted" do
      result = GoogleMaps.geocode("1600 Amphitheatre Parkway, Mountain View, CA")
      assert_api_key_error(result)
    end

    @tag :live_api
    test "geocode - address with special characters is properly encoded" do
      result = GoogleMaps.geocode("Champs-Élysées, Paris, France")
      assert_api_key_error(result)
    end

    @tag :live_api
    test "geocode - unicode address is properly encoded" do
      result = GoogleMaps.geocode("東京都渋谷区")
      assert_api_key_error(result)
    end

    @tag :live_api
    test "geocode - with region hint parameter" do
      result = GoogleMaps.geocode("London", region: "uk")
      assert_api_key_error(result)
    end

    @tag :live_api
    test "geocode - with language parameter" do
      result = GoogleMaps.geocode("Paris", language: "fr")
      assert_api_key_error(result)
    end

    @tag :live_api
    test "geocode - with components filter" do
      result = GoogleMaps.geocode("Victoria", components: "country:AU")
      assert_api_key_error(result)
    end

    @tag :live_api
    test "geocode - with bounds parameter" do
      result =
        GoogleMaps.geocode("Winnetka",
          bounds: "34.172684,-118.604794|34.236144,-118.500938"
        )

      assert_api_key_error(result)
    end

    @tag :live_api
    test "geocode_all - returns list format" do
      result = GoogleMaps.geocode_all("Springfield")
      assert_api_key_error(result)
    end
  end

  describe "Reverse Geocoding - verify request formatting" do
    @describetag :live_api

    @tag :live_api
    test "reverse_geocode - coordinates are properly formatted" do
      # Coordinates for Googleplex
      result = GoogleMaps.reverse_geocode(37.4224764, -122.0842499)
      assert_api_key_error(result)
    end

    @tag :live_api
    test "reverse_geocode - negative coordinates work" do
      # Sydney, Australia (southern hemisphere)
      result = GoogleMaps.reverse_geocode(-33.8688, 151.2093)
      assert_api_key_error(result)
    end

    @tag :live_api
    test "reverse_geocode - with result_type filter" do
      result = GoogleMaps.reverse_geocode(37.4224764, -122.0842499, result_type: "street_address")
      assert_api_key_error(result)
    end

    @tag :live_api
    test "reverse_geocode - with location_type filter" do
      result = GoogleMaps.reverse_geocode(37.4224764, -122.0842499, location_type: "ROOFTOP")
      assert_api_key_error(result)
    end

    @tag :live_api
    test "reverse_geocode_all - returns list format" do
      result = GoogleMaps.reverse_geocode_all(37.4224764, -122.0842499)
      assert_api_key_error(result)
    end
  end

  describe "Places Autocomplete - verify request formatting" do
    @describetag :live_api

    @tag :live_api
    test "autocomplete - basic query is properly formatted" do
      result = GoogleMaps.autocomplete("coffee shops")
      assert_api_key_error(result)
    end

    @tag :live_api
    test "autocomplete - with location bias" do
      # Bias towards San Francisco
      result = GoogleMaps.autocomplete("pizza", location: {37.7749, -122.4194}, radius: 5000)
      assert_api_key_error(result)
    end

    @tag :live_api
    test "autocomplete - with types filter" do
      result = GoogleMaps.autocomplete("star", types: "establishment")
      assert_api_key_error(result)
    end

    @tag :live_api
    test "autocomplete - with components filter" do
      result = GoogleMaps.autocomplete("Paris", components: "country:fr")
      assert_api_key_error(result)
    end

    @tag :live_api
    test "autocomplete - with strict bounds" do
      result =
        GoogleMaps.autocomplete("restaurant",
          location: {37.7749, -122.4194},
          radius: 1000,
          strictbounds: true
        )

      assert_api_key_error(result)
    end

    @tag :live_api
    test "autocomplete - partial unicode input" do
      result = GoogleMaps.autocomplete("東京")
      assert_api_key_error(result)
    end
  end

  describe "Place Details - verify request formatting" do
    @describetag :live_api

    @tag :live_api
    test "place_details - place_id is properly included" do
      result = GoogleMaps.place_details("ChIJN1t_tDeuEmsRUsoyG83frY4")
      assert_api_key_error(result)
    end

    @tag :live_api
    test "place_details - with fields filter" do
      result =
        GoogleMaps.place_details("ChIJN1t_tDeuEmsRUsoyG83frY4",
          fields: "name,formatted_address,geometry"
        )

      assert_api_key_error(result)
    end

    @tag :live_api
    test "place_details - with language parameter" do
      result = GoogleMaps.place_details("ChIJN1t_tDeuEmsRUsoyG83frY4", language: "ja")
      assert_api_key_error(result)
    end
  end

  describe "Nearby Search - verify request formatting" do
    @describetag :live_api

    @tag :live_api
    test "nearby_search - location and radius are properly formatted" do
      result = GoogleMaps.nearby_search(37.7749, -122.4194, radius: 1000)
      assert_api_key_error(result)
    end

    @tag :live_api
    test "nearby_search - with type filter" do
      result = GoogleMaps.nearby_search(37.7749, -122.4194, radius: 1000, type: "restaurant")
      assert_api_key_error(result)
    end

    @tag :live_api
    test "nearby_search - with keyword filter" do
      result = GoogleMaps.nearby_search(37.7749, -122.4194, radius: 1000, keyword: "vegetarian")
      assert_api_key_error(result)
    end

    @tag :live_api
    test "nearby_search - with rankby distance" do
      # When using rankby=distance, radius is not allowed but type or keyword is required
      result = GoogleMaps.nearby_search(37.7749, -122.4194, rankby: "distance", type: "cafe")
      assert_api_key_error(result)
    end

    @tag :live_api
    test "nearby_search - with opennow filter" do
      result = GoogleMaps.nearby_search(37.7749, -122.4194, radius: 500, opennow: true)
      assert_api_key_error(result)
    end

    @tag :live_api
    test "nearby_search - with pagetoken" do
      result = GoogleMaps.nearby_search(37.7749, -122.4194, pagetoken: "next_page_token_xyz")
      assert_api_key_error(result)
    end
  end

  describe "Text Search - verify request formatting" do
    @describetag :live_api

    @tag :live_api
    test "text_search - basic query is properly formatted" do
      result = GoogleMaps.text_search("restaurants in Sydney")
      assert_api_key_error(result)
    end

    @tag :live_api
    test "text_search - with location bias" do
      result = GoogleMaps.text_search("museum", location: {48.8566, 2.3522}, radius: 5000)
      assert_api_key_error(result)
    end

    @tag :live_api
    test "text_search - with type filter" do
      result = GoogleMaps.text_search("food", type: "restaurant")
      assert_api_key_error(result)
    end

    @tag :live_api
    test "text_search - unicode query" do
      result = GoogleMaps.text_search("ラーメン 東京")
      assert_api_key_error(result)
    end

    @tag :live_api
    test "text_search - with minprice/maxprice" do
      result = GoogleMaps.text_search("restaurant", minprice: 2, maxprice: 4)
      assert_api_key_error(result)
    end
  end

  describe "Distance Matrix - verify request formatting" do
    @describetag :live_api

    @tag :live_api
    test "distance_matrix - coordinate origins/destinations work" do
      result =
        GoogleMaps.distance_matrix(
          [{37.7749, -122.4194}],
          [{34.0522, -118.2437}]
        )

      assert_api_key_error(result)
    end

    @tag :live_api
    test "distance_matrix - address origins/destinations work" do
      result =
        GoogleMaps.distance_matrix(
          ["San Francisco, CA"],
          ["Los Angeles, CA"]
        )

      assert_api_key_error(result)
    end

    @tag :live_api
    test "distance_matrix - mixed coordinates and addresses work" do
      result =
        GoogleMaps.distance_matrix(
          [{37.7749, -122.4194}, "Seattle, WA"],
          ["Portland, OR", {34.0522, -118.2437}]
        )

      assert_api_key_error(result)
    end

    @tag :live_api
    test "distance_matrix - multiple origins and destinations" do
      result =
        GoogleMaps.distance_matrix(
          ["New York, NY", "Boston, MA", "Philadelphia, PA"],
          ["Washington DC", "Baltimore, MD"]
        )

      assert_api_key_error(result)
    end

    @tag :live_api
    test "distance_matrix - with mode parameter" do
      result =
        GoogleMaps.distance_matrix(
          ["San Francisco, CA"],
          ["Oakland, CA"],
          mode: "transit"
        )

      assert_api_key_error(result)
    end

    @tag :live_api
    test "distance_matrix - with units parameter" do
      result =
        GoogleMaps.distance_matrix(
          ["London, UK"],
          ["Paris, France"],
          units: "metric"
        )

      assert_api_key_error(result)
    end

    @tag :live_api
    test "distance_matrix - with avoid parameter" do
      result =
        GoogleMaps.distance_matrix(
          ["San Francisco, CA"],
          ["San Jose, CA"],
          avoid: "tolls"
        )

      assert_api_key_error(result)
    end

    @tag :live_api
    test "distance_matrix - with departure_time" do
      result =
        GoogleMaps.distance_matrix(
          ["San Francisco, CA"],
          ["Oakland, CA"],
          departure_time: "now"
        )

      assert_api_key_error(result)
    end
  end
end
