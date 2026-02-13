defmodule Backend.GoogleMapsMockedTest do
  @moduledoc """
  Mocked tests for the Google Maps API client.

  These tests use Mox to mock HTTP responses with realistic Google Maps API
  response formats, allowing us to test all code paths without making real
  API calls.

  API response formats are based on:
  https://developers.google.com/maps/documentation/geocoding/overview
  https://developers.google.com/maps/documentation/places/web-service/overview
  https://developers.google.com/maps/documentation/distance-matrix/overview
  """

  use ExUnit.Case, async: true

  import Mox

  alias Backend.GoogleMaps

  # Make sure mocks are verified when the test exits
  setup :verify_on_exit!

  setup do
    # Configure API key for tests
    Application.put_env(:backend, :google_maps, api_key: "test_api_key")

    on_exit(fn ->
      Application.delete_env(:backend, :google_maps)
    end)

    :ok
  end

  # ===========================================================================
  # Realistic API Response Fixtures
  # ===========================================================================

  defp geocode_success_response do
    %{
      "status" => "OK",
      "results" => [
        %{
          "address_components" => [
            %{
              "long_name" => "1600",
              "short_name" => "1600",
              "types" => ["street_number"]
            },
            %{
              "long_name" => "Amphitheatre Parkway",
              "short_name" => "Amphitheatre Pkwy",
              "types" => ["route"]
            },
            %{
              "long_name" => "Mountain View",
              "short_name" => "Mountain View",
              "types" => ["locality", "political"]
            },
            %{
              "long_name" => "Santa Clara County",
              "short_name" => "Santa Clara County",
              "types" => ["administrative_area_level_2", "political"]
            },
            %{
              "long_name" => "California",
              "short_name" => "CA",
              "types" => ["administrative_area_level_1", "political"]
            },
            %{
              "long_name" => "United States",
              "short_name" => "US",
              "types" => ["country", "political"]
            },
            %{
              "long_name" => "94043",
              "short_name" => "94043",
              "types" => ["postal_code"]
            }
          ],
          "formatted_address" => "1600 Amphitheatre Pkwy, Mountain View, CA 94043, USA",
          "geometry" => %{
            "location" => %{
              "lat" => 37.4224764,
              "lng" => -122.0842499
            },
            "location_type" => "ROOFTOP",
            "viewport" => %{
              "northeast" => %{"lat" => 37.4238253802915, "lng" => -122.0829009197085},
              "southwest" => %{"lat" => 37.4211274197085, "lng" => -122.0855988802915}
            }
          },
          "place_id" => "ChIJ2eUgeAK6j4ARbn5u_wAGqWA",
          "plus_code" => %{
            "compound_code" => "CWC8+W5 Mountain View, CA, USA",
            "global_code" => "849VCWC8+W5"
          },
          "types" => ["street_address"]
        }
      ]
    }
  end

  defp autocomplete_success_response do
    %{
      "status" => "OK",
      "predictions" => [
        %{
          "description" => "Starbucks, Market Street, San Francisco, CA, USA",
          "matched_substrings" => [%{"length" => 9, "offset" => 0}],
          "place_id" => "ChIJxZvD_neBhYARDBMvGvOV0rg",
          "reference" => "ChIJxZvD_neBhYARDBMvGvOV0rg",
          "structured_formatting" => %{
            "main_text" => "Starbucks",
            "main_text_matched_substrings" => [%{"length" => 9, "offset" => 0}],
            "secondary_text" => "Market Street, San Francisco, CA, USA"
          },
          "terms" => [
            %{"offset" => 0, "value" => "Starbucks"},
            %{"offset" => 11, "value" => "Market Street"},
            %{"offset" => 26, "value" => "San Francisco"},
            %{"offset" => 41, "value" => "CA"},
            %{"offset" => 45, "value" => "USA"}
          ],
          "types" => ["cafe", "food", "point_of_interest", "establishment"]
        },
        %{
          "description" => "Starbucks Reserve Roastery, 4th Street, San Francisco, CA, USA",
          "place_id" => "ChIJK5aJhYaBhYARjXqzjDQ6_Ug",
          "types" => ["cafe", "food", "point_of_interest", "establishment"]
        }
      ]
    }
  end

  defp place_details_success_response do
    %{
      "status" => "OK",
      "result" => %{
        "address_components" => [
          %{
            "long_name" => "48",
            "short_name" => "48",
            "types" => ["street_number"]
          },
          %{
            "long_name" => "Pirrama Road",
            "short_name" => "Pirrama Rd",
            "types" => ["route"]
          }
        ],
        "adr_address" =>
          "<span class=\"street-address\">48 Pirrama Rd</span>, <span class=\"locality\">Pyrmont</span> <span class=\"region\">NSW</span> <span class=\"postal-code\">2009</span>, <span class=\"country-name\">Australia</span>",
        "formatted_address" => "48 Pirrama Rd, Pyrmont NSW 2009, Australia",
        "formatted_phone_number" => "(02) 9374 4000",
        "geometry" => %{
          "location" => %{"lat" => -33.866489, "lng" => 151.1958561},
          "viewport" => %{
            "northeast" => %{"lat" => -33.8655112, "lng" => 151.1971156},
            "southwest" => %{"lat" => -33.86744589999999, "lng" => 151.1944158}
          }
        },
        "icon" => "https://maps.gstatic.com/mapfiles/place_api/icons/generic_business-71.png",
        "name" => "Google Workplace 6",
        "opening_hours" => %{
          "open_now" => false,
          "periods" => [
            %{
              "close" => %{"day" => 1, "time" => "1700"},
              "open" => %{"day" => 1, "time" => "0900"}
            }
          ],
          "weekday_text" => [
            "Monday: 9:00 AM – 5:00 PM",
            "Tuesday: 9:00 AM – 5:00 PM",
            "Wednesday: 9:00 AM – 5:00 PM",
            "Thursday: 9:00 AM – 5:00 PM",
            "Friday: 9:00 AM – 5:00 PM",
            "Saturday: Closed",
            "Sunday: Closed"
          ]
        },
        "place_id" => "ChIJN1t_tDeuEmsRUsoyG83frY4",
        "rating" => 4.5,
        "reviews" => [
          %{
            "author_name" => "Luke Archibald",
            "rating" => 5,
            "text" => "Great place to work"
          }
        ],
        "types" => ["point_of_interest", "establishment"],
        "url" => "https://maps.google.com/?cid=10281119596374313554",
        "user_ratings_total" => 939,
        "utc_offset" => 600,
        "website" => "https://www.google.com.au/about/careers/locations/sydney/"
      }
    }
  end

  defp nearby_search_success_response do
    %{
      "status" => "OK",
      "results" => [
        %{
          "geometry" => %{
            "location" => %{"lat" => 37.7749, "lng" => -122.4194}
          },
          "icon" => "https://maps.gstatic.com/mapfiles/place_api/icons/cafe-71.png",
          "name" => "Blue Bottle Coffee",
          "opening_hours" => %{"open_now" => true},
          "place_id" => "ChIJVTPokywQkFQRbhd98sLJE7Q",
          "price_level" => 2,
          "rating" => 4.4,
          "types" => ["cafe", "food", "point_of_interest", "establishment"],
          "vicinity" => "66 Mint St, San Francisco"
        },
        %{
          "geometry" => %{
            "location" => %{"lat" => 37.7751, "lng" => -122.4189}
          },
          "name" => "Sightglass Coffee",
          "place_id" => "ChIJE7ynY0uAhYAR8tP-_NG8HQQ",
          "rating" => 4.3,
          "types" => ["cafe", "food", "point_of_interest", "establishment"],
          "vicinity" => "270 7th St, San Francisco"
        }
      ],
      "next_page_token" => "AZose0kXcWkQc3dZ7A3xB5G3..."
    }
  end

  defp text_search_success_response do
    %{
      "status" => "OK",
      "results" => [
        %{
          "formatted_address" => "140 New Montgomery St, San Francisco, CA 94105, USA",
          "geometry" => %{
            "location" => %{"lat" => 37.7867, "lng" => -122.4000}
          },
          "name" => "Equator Coffees",
          "place_id" => "ChIJVVVVVYeAhYAR5a7A7UXmIjQ",
          "rating" => 4.6,
          "types" => ["cafe", "food", "point_of_interest", "establishment"]
        }
      ]
    }
  end

  defp distance_matrix_success_response do
    %{
      "status" => "OK",
      "destination_addresses" => ["Los Angeles, CA, USA"],
      "origin_addresses" => ["San Francisco, CA, USA"],
      "rows" => [
        %{
          "elements" => [
            %{
              "distance" => %{
                "text" => "617 km",
                "value" => 617_137
              },
              "duration" => %{
                "text" => "5 hours 45 mins",
                "value" => 20_700
              },
              "duration_in_traffic" => %{
                "text" => "6 hours 10 mins",
                "value" => 22_200
              },
              "status" => "OK"
            }
          ]
        }
      ]
    }
  end

  defp zero_results_response do
    %{
      "status" => "ZERO_RESULTS",
      "results" => []
    }
  end

  defp request_denied_response do
    %{
      "status" => "REQUEST_DENIED",
      "error_message" => "The provided API key is invalid."
    }
  end

  defp over_query_limit_response do
    %{
      "status" => "OVER_QUERY_LIMIT",
      "error_message" => "You have exceeded your daily request quota for this API."
    }
  end

  # ===========================================================================
  # Geocoding Tests
  # ===========================================================================

  describe "geocode/2 with mocked responses" do
    test "returns geocoded result for valid address" do
      Backend.HTTPClientMock
      |> expect(:get, fn url, opts ->
        assert url =~ "maps.googleapis.com/maps/api/geocode"
        assert opts[:params][:address] == "1600 Amphitheatre Parkway, Mountain View, CA"
        assert opts[:params][:key] == "test_api_key"

        {:ok, %{status: 200, body: geocode_success_response()}}
      end)

      result = GoogleMaps.geocode("1600 Amphitheatre Parkway, Mountain View, CA")

      assert {:ok, location} = result
      assert location["formatted_address"] =~ "1600 Amphitheatre"
      assert location["geometry"]["location"]["lat"] == 37.4224764
      assert location["geometry"]["location"]["lng"] == -122.0842499
      assert location["place_id"] == "ChIJ2eUgeAK6j4ARbn5u_wAGqWA"
    end

    test "returns all results with geocode_all/2" do
      Backend.HTTPClientMock
      |> expect(:get, fn _url, _opts ->
        {:ok, %{status: 200, body: geocode_success_response()}}
      end)

      result = GoogleMaps.geocode_all("1600 Amphitheatre Parkway")

      assert {:ok, results} = result
      assert is_list(results)
      assert length(results) == 1
    end

    test "handles ZERO_RESULTS status" do
      Backend.HTTPClientMock
      |> expect(:get, fn _url, _opts ->
        {:ok, %{status: 200, body: zero_results_response()}}
      end)

      result = GoogleMaps.geocode("nonexistent address xyz123")

      assert {:error, :no_results} = result
    end

    test "handles REQUEST_DENIED status" do
      Backend.HTTPClientMock
      |> expect(:get, fn _url, _opts ->
        {:ok, %{status: 200, body: request_denied_response()}}
      end)

      result = GoogleMaps.geocode("1600 Amphitheatre Parkway")

      assert {:error, {"REQUEST_DENIED", "The provided API key is invalid."}} = result
    end

    test "handles OVER_QUERY_LIMIT status" do
      Backend.HTTPClientMock
      |> expect(:get, fn _url, _opts ->
        {:ok, %{status: 200, body: over_query_limit_response()}}
      end)

      result = GoogleMaps.geocode("1600 Amphitheatre Parkway")

      assert {:error, {"OVER_QUERY_LIMIT", _message}} = result
    end

    test "handles HTTP error" do
      Backend.HTTPClientMock
      |> expect(:get, fn _url, _opts ->
        {:ok, %{status: 500, body: %{"error" => "Internal Server Error"}}}
      end)

      result = GoogleMaps.geocode("1600 Amphitheatre Parkway")

      assert {:error, {:http_error, 500, _body}} = result
    end

    test "handles connection error" do
      Backend.HTTPClientMock
      |> expect(:get, fn _url, _opts ->
        {:error, %Req.TransportError{reason: :timeout}}
      end)

      result = GoogleMaps.geocode("1600 Amphitheatre Parkway")

      assert {:error, %Req.TransportError{}} = result
    end

    test "passes optional parameters" do
      Backend.HTTPClientMock
      |> expect(:get, fn _url, opts ->
        assert opts[:params][:region] == "us"
        assert opts[:params][:language] == "en"
        assert opts[:params][:components] == "country:US"

        {:ok, %{status: 200, body: geocode_success_response()}}
      end)

      GoogleMaps.geocode("Mountain View", region: "us", language: "en", components: "country:US")
    end
  end

  describe "reverse_geocode/3 with mocked responses" do
    test "returns address for coordinates" do
      Backend.HTTPClientMock
      |> expect(:get, fn url, opts ->
        assert url =~ "maps.googleapis.com/maps/api/geocode"
        assert opts[:params][:latlng] == "37.4224764,-122.0842499"

        {:ok, %{status: 200, body: geocode_success_response()}}
      end)

      result = GoogleMaps.reverse_geocode(37.4224764, -122.0842499)

      assert {:ok, location} = result
      assert location["formatted_address"] =~ "Amphitheatre"
    end

    test "handles zero results" do
      Backend.HTTPClientMock
      |> expect(:get, fn _url, _opts ->
        {:ok, %{status: 200, body: zero_results_response()}}
      end)

      result = GoogleMaps.reverse_geocode(0.0, 0.0)

      assert {:error, :no_results} = result
    end
  end

  # ===========================================================================
  # Places Autocomplete Tests
  # ===========================================================================

  describe "autocomplete/2 with mocked responses" do
    test "returns predictions for search query" do
      Backend.HTTPClientMock
      |> expect(:get, fn url, opts ->
        assert url =~ "maps.googleapis.com/maps/api/place/autocomplete"
        assert opts[:params][:input] == "starbucks"

        {:ok, %{status: 200, body: autocomplete_success_response()}}
      end)

      result = GoogleMaps.autocomplete("starbucks")

      assert {:ok, predictions} = result
      assert is_list(predictions)
      assert length(predictions) == 2

      first = hd(predictions)
      assert first["description"] =~ "Starbucks"
      assert first["place_id"]
      assert first["types"]
    end

    test "passes location bias parameters" do
      Backend.HTTPClientMock
      |> expect(:get, fn _url, opts ->
        assert opts[:params][:location] == "37.7749,-122.4194"
        assert opts[:params][:radius] == 5000

        {:ok, %{status: 200, body: autocomplete_success_response()}}
      end)

      GoogleMaps.autocomplete("coffee", location: {37.7749, -122.4194}, radius: 5000)
    end

    test "handles empty predictions" do
      Backend.HTTPClientMock
      |> expect(:get, fn _url, _opts ->
        {:ok,
         %{
           status: 200,
           body: %{
             "status" => "OK",
             "predictions" => []
           }
         }}
      end)

      result = GoogleMaps.autocomplete("xyznonexistent123")

      assert {:ok, []} = result
    end
  end

  # ===========================================================================
  # Place Details Tests
  # ===========================================================================

  describe "place_details/2 with mocked responses" do
    test "returns place details for place_id" do
      Backend.HTTPClientMock
      |> expect(:get, fn url, opts ->
        assert url =~ "maps.googleapis.com/maps/api/place/details"
        assert opts[:params][:place_id] == "ChIJN1t_tDeuEmsRUsoyG83frY4"

        {:ok, %{status: 200, body: place_details_success_response()}}
      end)

      result = GoogleMaps.place_details("ChIJN1t_tDeuEmsRUsoyG83frY4")

      assert {:ok, place} = result
      assert place["name"] == "Google Workplace 6"
      assert place["formatted_address"] =~ "Pirrama"
      assert place["rating"] == 4.5
      assert place["geometry"]["location"]["lat"] == -33.866489
    end

    test "handles place not found" do
      Backend.HTTPClientMock
      |> expect(:get, fn _url, _opts ->
        {:ok,
         %{
           status: 200,
           body: %{
             "status" => "NOT_FOUND",
             "error_message" => "Place not found"
           }
         }}
      end)

      result = GoogleMaps.place_details("invalid_place_id")

      # When error_message is present, returns {status, message} tuple
      assert {:error, {"NOT_FOUND", "Place not found"}} = result
    end

    test "passes fields parameter" do
      Backend.HTTPClientMock
      |> expect(:get, fn _url, opts ->
        assert opts[:params][:fields] == "name,formatted_address,geometry"

        {:ok, %{status: 200, body: place_details_success_response()}}
      end)

      GoogleMaps.place_details("ChIJN1t_tDeuEmsRUsoyG83frY4",
        fields: "name,formatted_address,geometry"
      )
    end
  end

  # ===========================================================================
  # Nearby Search Tests
  # ===========================================================================

  describe "nearby_search/3 with mocked responses" do
    test "returns nearby places" do
      Backend.HTTPClientMock
      |> expect(:get, fn url, opts ->
        assert url =~ "maps.googleapis.com/maps/api/place/nearbysearch"
        assert opts[:params][:location] == "37.7749,-122.4194"
        assert opts[:params][:radius] == 1000

        {:ok, %{status: 200, body: nearby_search_success_response()}}
      end)

      result = GoogleMaps.nearby_search(37.7749, -122.4194, radius: 1000)

      assert {:ok, places} = result
      assert is_list(places)
      assert length(places) == 2

      first = hd(places)
      assert first["name"] == "Blue Bottle Coffee"
      assert first["rating"] == 4.4
    end

    test "passes type filter" do
      Backend.HTTPClientMock
      |> expect(:get, fn _url, opts ->
        assert opts[:params][:type] == "restaurant"

        {:ok, %{status: 200, body: nearby_search_success_response()}}
      end)

      GoogleMaps.nearby_search(37.7749, -122.4194, radius: 1000, type: "restaurant")
    end

    test "passes keyword filter" do
      Backend.HTTPClientMock
      |> expect(:get, fn _url, opts ->
        assert opts[:params][:keyword] == "vegetarian"

        {:ok, %{status: 200, body: nearby_search_success_response()}}
      end)

      GoogleMaps.nearby_search(37.7749, -122.4194, radius: 1000, keyword: "vegetarian")
    end
  end

  # ===========================================================================
  # Text Search Tests
  # ===========================================================================

  describe "text_search/2 with mocked responses" do
    test "returns places matching query" do
      Backend.HTTPClientMock
      |> expect(:get, fn url, opts ->
        assert url =~ "maps.googleapis.com/maps/api/place/textsearch"
        assert opts[:params][:query] == "coffee shops in San Francisco"

        {:ok, %{status: 200, body: text_search_success_response()}}
      end)

      result = GoogleMaps.text_search("coffee shops in San Francisco")

      assert {:ok, places} = result
      assert is_list(places)

      first = hd(places)
      assert first["name"]
      assert first["formatted_address"]
    end
  end

  # ===========================================================================
  # Distance Matrix Tests
  # ===========================================================================

  describe "distance_matrix/3 with mocked responses" do
    test "returns distance and duration between points" do
      Backend.HTTPClientMock
      |> expect(:get, fn url, opts ->
        assert url =~ "maps.googleapis.com/maps/api/distancematrix"
        assert opts[:params][:origins] == "San Francisco, CA"
        assert opts[:params][:destinations] == "Los Angeles, CA"

        {:ok, %{status: 200, body: distance_matrix_success_response()}}
      end)

      result = GoogleMaps.distance_matrix(["San Francisco, CA"], ["Los Angeles, CA"])

      assert {:ok, matrix} = result
      assert matrix["origin_addresses"] == ["San Francisco, CA, USA"]
      assert matrix["destination_addresses"] == ["Los Angeles, CA, USA"]

      element = hd(hd(matrix["rows"])["elements"])
      assert element["distance"]["text"] == "617 km"
      assert element["duration"]["text"] == "5 hours 45 mins"
    end

    test "handles coordinate origins and destinations" do
      Backend.HTTPClientMock
      |> expect(:get, fn _url, opts ->
        assert opts[:params][:origins] == "37.7749,-122.4194"
        assert opts[:params][:destinations] == "34.0522,-118.2437"

        {:ok, %{status: 200, body: distance_matrix_success_response()}}
      end)

      GoogleMaps.distance_matrix([{37.7749, -122.4194}], [{34.0522, -118.2437}])
    end

    test "handles multiple origins and destinations" do
      Backend.HTTPClientMock
      |> expect(:get, fn _url, opts ->
        assert opts[:params][:origins] == "New York, NY|Boston, MA"
        assert opts[:params][:destinations] == "Washington DC|Philadelphia, PA"

        {:ok, %{status: 200, body: distance_matrix_success_response()}}
      end)

      GoogleMaps.distance_matrix(
        ["New York, NY", "Boston, MA"],
        ["Washington DC", "Philadelphia, PA"]
      )
    end

    test "passes travel mode parameter" do
      Backend.HTTPClientMock
      |> expect(:get, fn _url, opts ->
        assert opts[:params][:mode] == "transit"

        {:ok, %{status: 200, body: distance_matrix_success_response()}}
      end)

      GoogleMaps.distance_matrix(["SF"], ["LA"], mode: "transit")
    end
  end
end
