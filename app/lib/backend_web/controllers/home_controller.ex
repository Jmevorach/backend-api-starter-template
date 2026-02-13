defmodule BackendWeb.HomeController do
  @moduledoc """
  Root API endpoint.

  This keeps the project generic by returning a small JSON payload that
  describes the service and links to key endpoints.
  """

  use Phoenix.Controller, formats: [:json]

  @doc """
  GET / returns basic service metadata.
  """
  def index(conn, _params) do
    version = Application.spec(:backend, :vsn) |> to_string()

    json(conn, %{
      status: "ok",
      service: "mobile-backend",
      version: version,
      endpoints: %{
        health: "/healthz",
        me: "/api/v1/me",
        profile: "/api/v1/profile",
        dashboard: "/api/v1/dashboard",
        projects: "/api/v1/projects",
        tasks: "/api/v1/tasks",
        auth: "/auth/:provider"
      }
    })
  end
end
