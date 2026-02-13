defmodule BackendWeb.ErrorJSONTest do
  @moduledoc """
  Tests for the ErrorJSON module.

  These tests verify error response rendering.
  """

  use ExUnit.Case, async: true

  alias BackendWeb.ErrorJSON

  describe "render/2" do
    test "renders 404 error" do
      result = ErrorJSON.render("404.json", %{})

      assert result == %{error: "Not Found"}
    end

    test "renders 500 error" do
      result = ErrorJSON.render("500.json", %{})

      assert result == %{error: "Internal Server Error"}
    end

    test "renders custom error from assigns" do
      assigns = %{error: %{message: "Custom error", code: "CUSTOM"}}

      result = ErrorJSON.render("422.json", assigns)

      assert result == %{message: "Custom error", code: "CUSTOM"}
    end

    test "renders unknown error with default message" do
      result = ErrorJSON.render("unknown.json", %{})

      assert result == %{error: "Unknown error"}
    end

    test "handles nil assigns gracefully" do
      # When error is not in assigns, should return default
      result = ErrorJSON.render("400.json", %{other: "data"})

      assert result == %{error: "Unknown error"}
    end
  end
end
