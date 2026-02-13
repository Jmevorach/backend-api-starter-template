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
      service: "patient-backend",
      version: version,
      endpoints: %{
        health: "/healthz",
        me: "/api/me",
        patient_profile: "/api/patient/profile",
        patient_dashboard: "/api/patient/dashboard",
        auth: "/auth/:provider"
      }
    })
  end
end
