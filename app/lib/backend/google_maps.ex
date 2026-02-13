defmodule Backend.GoogleMaps do
  @moduledoc """
  Google Maps Platform client (Geocoding, Places, Distance Matrix).
  """

  require Logger

  @geocoding_url "https://maps.googleapis.com/maps/api/geocode/json"
  @places_url "https://maps.googleapis.com/maps/api/place"

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

  @spec reverse_geocode_all(float(), float(), keyword()) :: {:ok, list(map())} | {:error, term()}
  def reverse_geocode_all(lat, lng, opts \\ []) do
    params =
      %{latlng: "#{lat},#{lng}"}
      |> maybe_add(:result_type, opts[:result_type])
      |> maybe_add(:location_type, opts[:location_type])
      |> maybe_add(:language, opts[:language])

    geocoding_request(params)
  end

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

  @spec place_details(String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def place_details(place_id, opts \\ []) do
    params =
      %{place_id: place_id}
      |> maybe_add(:fields, opts[:fields])
      |> maybe_add(:language, opts[:language])
      |> maybe_add(:sessiontoken, opts[:sessiontoken])

    places_request("/details/json", params, "result")
  end

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
    case api_request(@places_url <> path, params) do
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
            {:error, {:http_error, status, body}}

          {:error, reason} ->
            Logger.error("Google Maps request failed: #{inspect(reason)}")
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
