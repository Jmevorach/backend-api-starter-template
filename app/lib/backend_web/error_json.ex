defmodule BackendWeb.ErrorJSON do
  @moduledoc false

  # Fallback error rendering for JSON-only API responses.

  def render("404.json", _assigns),
    do: %{error: "Not Found", code: "not_found", message: "Not Found"}

  def render("500.json", _assigns),
    do: %{
      error: "Internal Server Error",
      code: "internal_server_error",
      message: "Internal Server Error"
    }

  def render(_template, assigns), do: Map.get(assigns, :error, %{error: "Unknown error"})
end
