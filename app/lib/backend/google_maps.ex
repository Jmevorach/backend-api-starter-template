defmodule Backend.GoogleMaps do
  @moduledoc """
  Google Maps Platform API client for geocoding and places.

  This module provides an interface to Google Maps APIs including geocoding
  (converting addresses to coordinates and vice versa) and Places API
  (search, autocomplete, details).

  ## Configuration

  Set the `GOOGLE_MAPS_API_KEY` environment variable with your Google Maps
  Platform API key. In production, this should be injected via AWS Secrets Manager.

  Make sure to enable the following APIs in Google Cloud Console:
  - Geocoding API
  - Places API

  ## Usage

      # Geocode an address to coordinates
      {:ok, result} = Backend.GoogleMaps.geocode("1600 Amphitheatre Parkway, Mountain View, CA")
      lat = result["geometry"]["location"]["lat"]
      lng = result["geometry"]["location"]["lng"]

      # Reverse geocode coordinates to address
      {:ok, result} = Backend.GoogleMaps.reverse_geocode(37.4224764, -122.0842499)
      address = result["formatted_address"]

      # Place autocomplete
      {:ok, predictions} = Backend.GoogleMaps.autocomplete("coffee shops near")

      # Get place details
      {:ok, place} = Backend.GoogleMaps.place_details("ChIJ2eUgeAK6j4ARbn5u_wAGqWA")

  ## Error Handling

  All functions return `{:ok, result}` on success or `{:error, reason}` on failure.
  Google Maps API errors include the status and error message from Google.
  """

  require Logger

  @geocoding_url "https://maps.googleapis.com/maps/api/geocode/json"
  @places_url "https://maps.googleapis.com/maps/api/place"

  # Geocoding Operations

  @doc """
  Converts an address to geographic coordinates (latitude/longitude).

  ## Parameters

    * `address` - The address to geocode (street address, city, etc.)
    * `opts` - Optional parameters:
      * `:components` - Component filters (country, postal_code, etc.)
      * `:bounds` - Preferred bounding box for results
      * `:region` - Region code (e.g., "us") for biasing
      * `:language` - Language for results

  ## Returns

  Returns the first geocoding result. The result contains:
    * `geometry.location.lat` - Latitude
    * `geometry.location.lng` - Longitude
    * `formatted_address` - Full formatted address
    * `address_components` - Structured address components
    * `place_id` - Google Place ID

  ## Examples

      {:ok, result} = Backend.GoogleMaps.geocode("1600 Amphitheatre Parkway, Mountain View, CA")
      # => %{"geometry" => %{"location" => %{"lat" => 37.4224764, "lng" => -122.0842499}}, ...}

      # With region biasing
      {:ok, result} = Backend.GoogleMaps.geocode("Sydney", region: "au")
  """
  @spec geocode(String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def geocode(address, opts \\ []) do
    params =
      %{address: address}
      |> maybe_add(:components, opts[:components])
      |> maybe_add(:bounds, opts[:bounds])
      |> maybe_add(:region, opts[:region])
      |> maybe_add(:language, opts[:language])

    case geocoding_request(params) do
      {:ok, [result | _]} -> {:ok, result}
      {:ok, []} -> {:error, :no_results}
      error -> error
    end
  end

  @doc """
  Returns all geocoding results for an address.

  Same as `geocode/2` but returns all matching results instead of just the first.
  """
  @spec geocode_all(String.t(), keyword()) :: {:ok, list(map())} | {:error, term()}
  def geocode_all(address, opts \\ []) do
    params =
      %{address: address}
      |> maybe_add(:components, opts[:components])
      |> maybe_add(:bounds, opts[:bounds])
      |> maybe_add(:region, opts[:region])
      |> maybe_add(:language, opts[:language])

    geocoding_request(params)
  end

  @doc """
  Converts geographic coordinates to a human-readable address.

  ## Parameters

    * `lat` - Latitude
    * `lng` - Longitude
    * `opts` - Optional parameters:
      * `:result_type` - Filter by address type (e.g., "street_address")
      * `:location_type` - Filter by location type
      * `:language` - Language for results

  ## Returns

  Returns the first reverse geocoding result with the formatted address.

  ## Examples

      {:ok, result} = Backend.GoogleMaps.reverse_geocode(37.4224764, -122.0842499)
      address = result["formatted_address"]
      # => "1600 Amphitheatre Pkwy, Mountain View, CA 94043, USA"
  """
  @spec reverse_geocode(float(), float(), keyword()) :: {:ok, map()} | {:error, term()}
  def reverse_geocode(lat, lng, opts \\ []) do
    params =
      %{latlng: "#{lat},#{lng}"}
      |> maybe_add(:result_type, opts[:result_type])
      |> maybe_add(:location_type, opts[:location_type])
      |> maybe_add(:language, opts[:language])

    case geocoding_request(params) do
      {:ok, [result | _]} -> {:ok, result}
      {:ok, []} -> {:error, :no_results}
      error -> error
    end
  end

  @doc """
  Returns all reverse geocoding results for coordinates.
  """
  @spec reverse_geocode_all(float(), float(), keyword()) :: {:ok, list(map())} | {:error, term()}
  def reverse_geocode_all(lat, lng, opts \\ []) do
    params =
      %{latlng: "#{lat},#{lng}"}
      |> maybe_add(:result_type, opts[:result_type])
      |> maybe_add(:location_type, opts[:location_type])
      |> maybe_add(:language, opts[:language])

    geocoding_request(params)
  end

  # Places API Operations

  @doc """
  Provides place predictions based on text input (autocomplete).

  Useful for building address/place autocomplete UI components.

  ## Parameters

    * `input` - The text input for predictions
    * `opts` - Optional parameters:
      * `:types` - Place types to filter (e.g., "geocode", "establishment")
      * `:location` - `{lat, lng}` tuple for biasing results
      * `:radius` - Radius in meters for location biasing
      * `:components` - Component restrictions (e.g., "country:us")
      * `:language` - Language for results
      * `:sessiontoken` - Session token for billing optimization

  ## Returns

  Returns a list of predictions, each containing:
    * `place_id` - Google Place ID (use with `place_details/2`)
    * `description` - Full place description
    * `structured_formatting` - Primary and secondary text
    * `matched_substrings` - Matched portions for highlighting

  ## Examples

      {:ok, predictions} = Backend.GoogleMaps.autocomplete("1600 Amphitheatre")
      # => [%{"place_id" => "...", "description" => "1600 Amphitheatre Parkway, ..."}, ...]

      # With location biasing
      {:ok, predictions} = Backend.GoogleMaps.autocomplete("coffee", location: {37.7749, -122.4194})
  """
  @spec autocomplete(String.t(), keyword()) :: {:ok, list(map())} | {:error, term()}
  def autocomplete(input, opts \\ []) do
    params =
      %{input: input}
      |> maybe_add(:types, opts[:types])
      |> maybe_add(:components, opts[:components])
      |> maybe_add(:language, opts[:language])
      |> maybe_add(:sessiontoken, opts[:sessiontoken])

    params =
      case opts[:location] do
        {lat, lng} ->
          params
          |> Map.put(:location, "#{lat},#{lng}")
          |> maybe_add(:radius, opts[:radius])

        _ ->
          params
      end

    places_request("/autocomplete/json", params, "predictions")
  end

  @doc """
  Gets detailed information about a place.

  ## Parameters

    * `place_id` - Google Place ID (from geocoding, autocomplete, or search)
    * `opts` - Optional parameters:
      * `:fields` - Comma-separated list of fields to return (reduces cost)
      * `:language` - Language for results
      * `:sessiontoken` - Session token (for autocomplete billing optimization)

  ## Common Fields

    * Basic: `name`, `formatted_address`, `geometry`, `place_id`, `types`
    * Contact: `formatted_phone_number`, `opening_hours`, `website`
    * Atmosphere: `rating`, `reviews`, `price_level`, `user_ratings_total`

  ## Examples

      {:ok, place} = Backend.GoogleMaps.place_details("ChIJ2eUgeAK6j4ARbn5u_wAGqWA")

      # Request specific fields only (recommended for cost)
      {:ok, place} = Backend.GoogleMaps.place_details(place_id,
        fields: "name,formatted_address,geometry,rating"
      )
  """
  @spec place_details(String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def place_details(place_id, opts \\ []) do
    params =
      %{place_id: place_id}
      |> maybe_add(:fields, opts[:fields])
      |> maybe_add(:language, opts[:language])
      |> maybe_add(:sessiontoken, opts[:sessiontoken])

    places_request("/details/json", params, "result")
  end

  @doc """
  Searches for nearby places.

  ## Parameters

    * `lat` - Latitude of the search center
    * `lng` - Longitude of the search center
    * `opts` - Search options:
      * `:radius` - Search radius in meters (required unless using `:rankby`)
      * `:type` - Place type (e.g., "restaurant", "cafe", "gas_station")
      * `:keyword` - Keyword to match in place names/descriptions
      * `:name` - Name to match
      * `:rankby` - "prominence" (default) or "distance"
      * `:language` - Language for results
      * `:pagetoken` - Token for next page of results

  ## Examples

      {:ok, places} = Backend.GoogleMaps.nearby_search(37.7749, -122.4194,
        radius: 1000,
        type: "restaurant"
      )

      # Search by keyword
      {:ok, places} = Backend.GoogleMaps.nearby_search(37.7749, -122.4194,
        radius: 500,
        keyword: "coffee"
      )
  """
  @spec nearby_search(float(), float(), keyword()) :: {:ok, list(map())} | {:error, term()}
  def nearby_search(lat, lng, opts \\ []) do
    params =
      %{location: "#{lat},#{lng}"}
      |> maybe_add(:radius, opts[:radius])
      |> maybe_add(:type, opts[:type])
      |> maybe_add(:keyword, opts[:keyword])
      |> maybe_add(:name, opts[:name])
      |> maybe_add(:rankby, opts[:rankby])
      |> maybe_add(:language, opts[:language])
      |> maybe_add(:pagetoken, opts[:pagetoken])

    places_request("/nearbysearch/json", params, "results")
  end

  @doc """
  Searches for places using a text query.

  ## Parameters

    * `query` - The text query (e.g., "restaurants in Sydney")
    * `opts` - Search options:
      * `:location` - `{lat, lng}` tuple for biasing results
      * `:radius` - Radius in meters for location biasing
      * `:type` - Place type filter
      * `:language` - Language for results
      * `:pagetoken` - Token for next page of results

  ## Examples

      {:ok, places} = Backend.GoogleMaps.text_search("pizza in New York")

      {:ok, places} = Backend.GoogleMaps.text_search("museum",
        location: {48.8566, 2.3522},
        radius: 5000
      )
  """
  @spec text_search(String.t(), keyword()) :: {:ok, list(map())} | {:error, term()}
  def text_search(query, opts \\ []) do
    params =
      %{query: query}
      |> maybe_add(:type, opts[:type])
      |> maybe_add(:language, opts[:language])
      |> maybe_add(:pagetoken, opts[:pagetoken])

    params =
      case opts[:location] do
        {lat, lng} ->
          params
          |> Map.put(:location, "#{lat},#{lng}")
          |> maybe_add(:radius, opts[:radius])

        _ ->
          params
      end

    places_request("/textsearch/json", params, "results")
  end

  # Distance Matrix

  @doc """
  Calculates travel distance and time between origins and destinations.

  ## Parameters

    * `origins` - List of origin addresses or `{lat, lng}` tuples
    * `destinations` - List of destination addresses or `{lat, lng}` tuples
    * `opts` - Options:
      * `:mode` - Travel mode: "driving" (default), "walking", "bicycling", "transit"
      * `:units` - "metric" or "imperial"
      * `:departure_time` - Unix timestamp or "now" for traffic
      * `:avoid` - Features to avoid: "tolls", "highways", "ferries"

  ## Examples

      {:ok, result} = Backend.GoogleMaps.distance_matrix(
        ["Seattle, WA"],
        ["San Francisco, CA", "Los Angeles, CA"]
      )
  """
  @spec distance_matrix(list(), list(), keyword()) :: {:ok, map()} | {:error, term()}
  def distance_matrix(origins, destinations, opts \\ []) do
    params =
      %{
        origins: format_locations(origins),
        destinations: format_locations(destinations)
      }
      |> maybe_add(:mode, opts[:mode])
      |> maybe_add(:units, opts[:units])
      |> maybe_add(:departure_time, opts[:departure_time])
      |> maybe_add(:avoid, opts[:avoid])

    case api_request("https://maps.googleapis.com/maps/api/distancematrix/json", params) do
      {:ok, %{"status" => "OK"} = result} -> {:ok, result}
      {:ok, %{"status" => status}} -> {:error, {:api_error, status}}
      error -> error
    end
  end

  # Private helper functions

  defp geocoding_request(params) do
    case api_request(@geocoding_url, params) do
      {:ok, %{"status" => "OK", "results" => results}} -> {:ok, results}
      {:ok, %{"status" => "ZERO_RESULTS"}} -> {:ok, []}
      {:ok, %{"status" => status, "error_message" => msg}} -> {:error, {status, msg}}
      {:ok, %{"status" => status}} -> {:error, {:api_error, status}}
      error -> error
    end
  end

  defp places_request(path, params, result_key) do
    url = @places_url <> path

    case api_request(url, params) do
      {:ok, %{"status" => "OK"} = body} -> {:ok, body[result_key]}
      {:ok, %{"status" => "ZERO_RESULTS"}} -> {:ok, []}
      {:ok, %{"status" => status, "error_message" => msg}} -> {:error, {status, msg}}
      {:ok, %{"status" => status}} -> {:error, {:api_error, status}}
      error -> error
    end
  end

  defp api_request(url, params) do
    case get_api_key() do
      nil ->
        {:error, :api_key_not_configured}

      api_key ->
        params = Map.put(params, :key, api_key)

        case http_client().get(url, params: params) do
          {:ok, %{status: 200, body: body}} ->
            {:ok, body}

          {:ok, %{status: status, body: body}} ->
            Logger.warning("Google Maps API error: #{status} - #{inspect(body)}")
            {:error, {:http_error, status, body}}

          {:error, reason} ->
            Logger.error("Google Maps API request failed: #{inspect(reason)}")
            {:error, reason}
        end
    end
  end

  defp http_client do
    Application.get_env(:backend, :http_client, Backend.HTTPClient.Impl)
  end

  defp get_api_key do
    Application.get_env(:backend, :google_maps)[:api_key]
  end

  defp maybe_add(map, _key, nil), do: map
  defp maybe_add(map, key, value), do: Map.put(map, key, value)

  defp format_locations(locations) do
    Enum.map_join(locations, "|", fn
      {lat, lng} -> "#{lat},#{lng}"
      address when is_binary(address) -> address
    end)
  end
end
