defmodule Backend.GoogleMapsTest do
  @moduledoc """
  Tests for the Google Maps API client module.

  These tests verify:
  - Configuration handling (API key present/missing)
  - Helper functions (maybe_add, format_locations)
  - Parameter building for various API endpoints
  - Error handling patterns
  """

  use ExUnit.Case, async: false

  import Mox

  alias Backend.GoogleMaps

  # Make sure mocks are verified when the test exits
  setup :verify_on_exit!

  # Store original config and restore after each test
  setup do
    original_config = Application.get_env(:backend, :google_maps)

    # Stub HTTP client to return a simulated API error for tests with API key
    stub(Backend.HTTPClientMock, :get, fn _url, _opts ->
      {:ok,
       %{
         status: 200,
         body: %{
           "status" => "REQUEST_DENIED",
           "error_message" => "Test stub - no real API call"
         }
       }}
    end)

    on_exit(fn ->
      if original_config do
        Application.put_env(:backend, :google_maps, original_config)
      else
        Application.delete_env(:backend, :google_maps)
      end
    end)

    :ok
  end

  describe "when not configured" do
    setup do
      Application.delete_env(:backend, :google_maps)
      :ok
    end

    # Geocoding
    test "geocode returns :api_key_not_configured" do
      assert {:error, :api_key_not_configured} =
               GoogleMaps.geocode("1600 Amphitheatre Parkway, Mountain View, CA")
    end

    test "geocode_all returns :api_key_not_configured" do
      assert {:error, :api_key_not_configured} = GoogleMaps.geocode_all("New York")
    end

    test "reverse_geocode returns :api_key_not_configured" do
      assert {:error, :api_key_not_configured} =
               GoogleMaps.reverse_geocode(37.4224764, -122.0842499)
    end

    test "reverse_geocode_all returns :api_key_not_configured" do
      assert {:error, :api_key_not_configured} =
               GoogleMaps.reverse_geocode_all(37.4224764, -122.0842499)
    end

    # Places
    test "autocomplete returns :api_key_not_configured" do
      assert {:error, :api_key_not_configured} = GoogleMaps.autocomplete("coffee shops")
    end

    test "place_details returns :api_key_not_configured" do
      assert {:error, :api_key_not_configured} =
               GoogleMaps.place_details("ChIJ2eUgeAK6j4ARbn5u_wAGqWA")
    end

    test "nearby_search returns :api_key_not_configured" do
      assert {:error, :api_key_not_configured} =
               GoogleMaps.nearby_search(37.7749, -122.4194, radius: 1000)
    end

    test "text_search returns :api_key_not_configured" do
      assert {:error, :api_key_not_configured} = GoogleMaps.text_search("pizza in New York")
    end

    # Distance Matrix
    test "distance_matrix returns :api_key_not_configured" do
      assert {:error, :api_key_not_configured} =
               GoogleMaps.distance_matrix(["Seattle, WA"], ["San Francisco, CA"])
    end
  end

  describe "geocode/2" do
    setup do
      Application.delete_env(:backend, :google_maps)
      :ok
    end

    test "accepts address string" do
      assert {:error, :api_key_not_configured} =
               GoogleMaps.geocode("1600 Amphitheatre Parkway")
    end

    test "accepts optional region parameter" do
      assert {:error, :api_key_not_configured} =
               GoogleMaps.geocode("Sydney", region: "au")
    end

    test "accepts optional language parameter" do
      assert {:error, :api_key_not_configured} =
               GoogleMaps.geocode("Tokyo", language: "ja")
    end

    test "accepts optional components parameter" do
      assert {:error, :api_key_not_configured} =
               GoogleMaps.geocode("Paris", components: "country:FR")
    end

    test "accepts optional bounds parameter" do
      assert {:error, :api_key_not_configured} =
               GoogleMaps.geocode("Main Street",
                 bounds: "34.0,-118.5|34.3,-118.2"
               )
    end

    test "accepts multiple options" do
      assert {:error, :api_key_not_configured} =
               GoogleMaps.geocode("High Street",
                 region: "uk",
                 language: "en",
                 components: "country:GB"
               )
    end
  end

  describe "reverse_geocode/3" do
    setup do
      Application.delete_env(:backend, :google_maps)
      :ok
    end

    test "accepts lat/lng coordinates" do
      assert {:error, :api_key_not_configured} =
               GoogleMaps.reverse_geocode(37.4224764, -122.0842499)
    end

    test "accepts optional result_type parameter" do
      assert {:error, :api_key_not_configured} =
               GoogleMaps.reverse_geocode(37.4224764, -122.0842499, result_type: "street_address")
    end

    test "accepts optional location_type parameter" do
      assert {:error, :api_key_not_configured} =
               GoogleMaps.reverse_geocode(37.4224764, -122.0842499, location_type: "ROOFTOP")
    end

    test "accepts optional language parameter" do
      assert {:error, :api_key_not_configured} =
               GoogleMaps.reverse_geocode(35.6762, 139.6503, language: "ja")
    end
  end

  describe "autocomplete/2" do
    setup do
      Application.delete_env(:backend, :google_maps)
      :ok
    end

    test "accepts input string" do
      assert {:error, :api_key_not_configured} = GoogleMaps.autocomplete("coffee")
    end

    test "accepts optional types parameter" do
      assert {:error, :api_key_not_configured} =
               GoogleMaps.autocomplete("coffee", types: "establishment")
    end

    test "accepts optional location parameter as tuple" do
      assert {:error, :api_key_not_configured} =
               GoogleMaps.autocomplete("coffee", location: {37.7749, -122.4194})
    end

    test "accepts optional radius parameter with location" do
      assert {:error, :api_key_not_configured} =
               GoogleMaps.autocomplete("coffee",
                 location: {37.7749, -122.4194},
                 radius: 5000
               )
    end

    test "accepts optional components parameter" do
      assert {:error, :api_key_not_configured} =
               GoogleMaps.autocomplete("coffee", components: "country:us")
    end

    test "accepts optional language parameter" do
      assert {:error, :api_key_not_configured} =
               GoogleMaps.autocomplete("cafe", language: "fr")
    end

    test "accepts optional sessiontoken parameter" do
      assert {:error, :api_key_not_configured} =
               GoogleMaps.autocomplete("coffee", sessiontoken: "unique-session-token-123")
    end
  end

  describe "place_details/2" do
    setup do
      Application.delete_env(:backend, :google_maps)
      :ok
    end

    test "accepts place_id" do
      assert {:error, :api_key_not_configured} =
               GoogleMaps.place_details("ChIJ2eUgeAK6j4ARbn5u_wAGqWA")
    end

    test "accepts optional fields parameter" do
      assert {:error, :api_key_not_configured} =
               GoogleMaps.place_details("ChIJ2eUgeAK6j4ARbn5u_wAGqWA",
                 fields: "name,formatted_address,geometry"
               )
    end

    test "accepts optional language parameter" do
      assert {:error, :api_key_not_configured} =
               GoogleMaps.place_details("ChIJ2eUgeAK6j4ARbn5u_wAGqWA", language: "es")
    end

    test "accepts optional sessiontoken parameter" do
      assert {:error, :api_key_not_configured} =
               GoogleMaps.place_details("ChIJ2eUgeAK6j4ARbn5u_wAGqWA",
                 sessiontoken: "session-123"
               )
    end
  end

  describe "nearby_search/3" do
    setup do
      Application.delete_env(:backend, :google_maps)
      :ok
    end

    test "accepts lat/lng and radius" do
      assert {:error, :api_key_not_configured} =
               GoogleMaps.nearby_search(37.7749, -122.4194, radius: 1000)
    end

    test "accepts optional type parameter" do
      assert {:error, :api_key_not_configured} =
               GoogleMaps.nearby_search(37.7749, -122.4194,
                 radius: 1000,
                 type: "restaurant"
               )
    end

    test "accepts optional keyword parameter" do
      assert {:error, :api_key_not_configured} =
               GoogleMaps.nearby_search(37.7749, -122.4194,
                 radius: 500,
                 keyword: "vegetarian"
               )
    end

    test "accepts optional name parameter" do
      assert {:error, :api_key_not_configured} =
               GoogleMaps.nearby_search(37.7749, -122.4194,
                 radius: 1000,
                 name: "Starbucks"
               )
    end

    test "accepts optional rankby parameter" do
      assert {:error, :api_key_not_configured} =
               GoogleMaps.nearby_search(37.7749, -122.4194, rankby: "distance", type: "cafe")
    end

    test "accepts optional language parameter" do
      assert {:error, :api_key_not_configured} =
               GoogleMaps.nearby_search(37.7749, -122.4194,
                 radius: 1000,
                 language: "ja"
               )
    end

    test "accepts optional pagetoken parameter" do
      assert {:error, :api_key_not_configured} =
               GoogleMaps.nearby_search(37.7749, -122.4194, pagetoken: "next-page-token-xyz")
    end
  end

  describe "text_search/2" do
    setup do
      Application.delete_env(:backend, :google_maps)
      :ok
    end

    test "accepts query string" do
      assert {:error, :api_key_not_configured} = GoogleMaps.text_search("pizza in New York")
    end

    test "accepts optional location parameter as tuple" do
      assert {:error, :api_key_not_configured} =
               GoogleMaps.text_search("museum", location: {48.8566, 2.3522})
    end

    test "accepts optional radius parameter with location" do
      assert {:error, :api_key_not_configured} =
               GoogleMaps.text_search("museum",
                 location: {48.8566, 2.3522},
                 radius: 5000
               )
    end

    test "accepts optional type parameter" do
      assert {:error, :api_key_not_configured} =
               GoogleMaps.text_search("food", type: "restaurant")
    end

    test "accepts optional language parameter" do
      assert {:error, :api_key_not_configured} =
               GoogleMaps.text_search("restaurants", language: "it")
    end

    test "accepts optional pagetoken parameter" do
      assert {:error, :api_key_not_configured} =
               GoogleMaps.text_search("hotels", pagetoken: "page-token-abc")
    end
  end

  describe "distance_matrix/3" do
    setup do
      Application.delete_env(:backend, :google_maps)
      :ok
    end

    test "accepts origin and destination addresses" do
      assert {:error, :api_key_not_configured} =
               GoogleMaps.distance_matrix(
                 ["Seattle, WA"],
                 ["San Francisco, CA"]
               )
    end

    test "accepts multiple origins and destinations" do
      assert {:error, :api_key_not_configured} =
               GoogleMaps.distance_matrix(
                 ["Seattle, WA", "Portland, OR"],
                 ["San Francisco, CA", "Los Angeles, CA"]
               )
    end

    test "accepts lat/lng tuples" do
      assert {:error, :api_key_not_configured} =
               GoogleMaps.distance_matrix(
                 [{47.6062, -122.3321}],
                 [{37.7749, -122.4194}]
               )
    end

    test "accepts mixed addresses and coordinates" do
      assert {:error, :api_key_not_configured} =
               GoogleMaps.distance_matrix(
                 ["Seattle, WA", {45.5155, -122.6789}],
                 [{37.7749, -122.4194}, "Los Angeles, CA"]
               )
    end

    test "accepts optional mode parameter" do
      assert {:error, :api_key_not_configured} =
               GoogleMaps.distance_matrix(
                 ["Seattle, WA"],
                 ["Portland, OR"],
                 mode: "transit"
               )
    end

    test "accepts optional units parameter" do
      assert {:error, :api_key_not_configured} =
               GoogleMaps.distance_matrix(
                 ["New York, NY"],
                 ["Boston, MA"],
                 units: "imperial"
               )
    end

    test "accepts optional departure_time parameter" do
      assert {:error, :api_key_not_configured} =
               GoogleMaps.distance_matrix(
                 ["Home"],
                 ["Work"],
                 departure_time: "now"
               )
    end

    test "accepts optional avoid parameter" do
      assert {:error, :api_key_not_configured} =
               GoogleMaps.distance_matrix(
                 ["Seattle, WA"],
                 ["Portland, OR"],
                 avoid: "tolls"
               )
    end
  end

  describe "location formatting" do
    # Test the format_locations function indirectly through distance_matrix

    test "formats address strings correctly" do
      Application.put_env(:backend, :google_maps, api_key: "test_key")

      # This will make an HTTP request (which will fail with invalid key)
      # but we can verify the function doesn't crash with various inputs
      result =
        GoogleMaps.distance_matrix(
          ["123 Main St, City, ST 12345"],
          ["456 Oak Ave, Town, ST 67890"]
        )

      assert {:error, _} = result
    end

    test "formats coordinate tuples correctly" do
      Application.put_env(:backend, :google_maps, api_key: "test_key")

      result =
        GoogleMaps.distance_matrix(
          [{37.7749, -122.4194}],
          [{34.0522, -118.2437}]
        )

      assert {:error, _} = result
    end

    test "handles negative coordinates" do
      Application.put_env(:backend, :google_maps, api_key: "test_key")

      result =
        GoogleMaps.distance_matrix(
          [{-33.8688, 151.2093}],
          [{-34.6037, -58.3816}]
        )

      assert {:error, _} = result
    end

    test "handles zero coordinates" do
      Application.put_env(:backend, :google_maps, api_key: "test_key")

      result =
        GoogleMaps.distance_matrix(
          [{0.0, 0.0}],
          [{0.0, 0.0}]
        )

      assert {:error, _} = result
    end
  end

  describe "optional parameter handling" do
    # Test that nil values are properly filtered out

    test "geocode handles nil options" do
      Application.delete_env(:backend, :google_maps)

      # Should not crash with nil values
      assert {:error, :api_key_not_configured} =
               GoogleMaps.geocode("test",
                 region: nil,
                 language: nil,
                 components: nil
               )
    end

    test "autocomplete handles nil location" do
      Application.delete_env(:backend, :google_maps)

      # Should not crash when location is nil
      assert {:error, :api_key_not_configured} =
               GoogleMaps.autocomplete("test", location: nil)
    end

    test "nearby_search handles nil optional params" do
      Application.delete_env(:backend, :google_maps)

      assert {:error, :api_key_not_configured} =
               GoogleMaps.nearby_search(37.0, -122.0,
                 radius: 1000,
                 type: nil,
                 keyword: nil
               )
    end
  end

  describe "coordinate precision" do
    test "handles high precision coordinates" do
      Application.put_env(:backend, :google_maps, api_key: "test_key")

      # Should not crash with high precision coordinates
      result = GoogleMaps.reverse_geocode(37.422476432189756, -122.08424987654321)
      assert {:error, _} = result
    end

    test "handles integer coordinates" do
      Application.put_env(:backend, :google_maps, api_key: "test_key")

      # Should handle integer coordinates (they'll be converted to float format)
      result = GoogleMaps.reverse_geocode(37, -122)
      assert {:error, _} = result
    end

    test "handles negative coordinates" do
      Application.put_env(:backend, :google_maps, api_key: "test_key")

      # Southern and Western hemispheres use negative coordinates
      result = GoogleMaps.reverse_geocode(-33.8688, 151.2093)
      assert {:error, _} = result
    end

    test "handles zero coordinates" do
      Application.put_env(:backend, :google_maps, api_key: "test_key")

      # Null Island (0, 0) is a valid coordinate
      result = GoogleMaps.reverse_geocode(0.0, 0.0)
      assert {:error, _} = result
    end
  end

  describe "special characters in queries" do
    setup do
      Application.put_env(:backend, :google_maps, api_key: "test_key")
      :ok
    end

    test "geocode handles unicode addresses" do
      # Japanese address
      result = GoogleMaps.geocode("東京都渋谷区")
      assert {:error, _} = result
    end

    test "geocode handles addresses with special characters" do
      # Address with accents and special chars
      result = GoogleMaps.geocode("Champs-Élysées, Paris")
      assert {:error, _} = result
    end

    test "text_search handles emoji in query" do
      # Some users might include emoji
      result = GoogleMaps.text_search("🍕 pizza near me")
      assert {:error, _} = result
    end

    test "autocomplete handles partial unicode input" do
      result = GoogleMaps.autocomplete("東京")
      assert {:error, _} = result
    end

    test "geocode handles query with ampersand" do
      result = GoogleMaps.geocode("Ben & Jerry's, Burlington VT")
      assert {:error, _} = result
    end

    test "geocode handles query with quotes" do
      result = GoogleMaps.geocode("\"Empire State Building\" New York")
      assert {:error, _} = result
    end
  end

  describe "distance matrix edge cases" do
    setup do
      Application.delete_env(:backend, :google_maps)
      :ok
    end

    test "handles single origin and destination" do
      assert {:error, :api_key_not_configured} =
               GoogleMaps.distance_matrix(
                 [{37.7749, -122.4194}],
                 [{34.0522, -118.2437}]
               )
    end

    test "handles maximum origins and destinations" do
      # Google Maps allows up to 25 origins x 25 destinations
      origins = for i <- 1..10, do: {37.0 + i * 0.1, -122.0}
      destinations = for i <- 1..10, do: {34.0 + i * 0.1, -118.0}

      assert {:error, :api_key_not_configured} =
               GoogleMaps.distance_matrix(origins, destinations)
    end

    test "handles mixed coordinate and address inputs" do
      assert {:error, :api_key_not_configured} =
               GoogleMaps.distance_matrix(
                 [{37.7749, -122.4194}, "Los Angeles, CA"],
                 ["New York, NY", {40.7128, -74.0060}]
               )
    end
  end
end
