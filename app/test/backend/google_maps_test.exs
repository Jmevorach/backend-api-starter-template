defmodule Backend.GoogleMapsTest do
  use ExUnit.Case, async: false

  alias Backend.GoogleMaps

  setup do
    original = Application.get_env(:backend, :google_maps)

    on_exit(fn ->
      if original,
        do: Application.put_env(:backend, :google_maps, original),
        else: Application.delete_env(:backend, :google_maps)
    end)

    :ok
  end

  test "returns api_key_not_configured when missing config" do
    Application.delete_env(:backend, :google_maps)
    assert {:error, :api_key_not_configured} = GoogleMaps.geocode("1600 Amphitheatre Parkway")
  end
end
