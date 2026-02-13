defmodule BackendWeb.ErrorJSON do
  @moduledoc false

  # Fallback error rendering for JSON-only API responses.

  def render("404.json", _assigns), do: %{error: "Not Found"}
  def render("500.json", _assigns), do: %{error: "Internal Server Error"}
  def render(_template, assigns), do: Map.get(assigns, :error, %{error: "Unknown error"})
end
