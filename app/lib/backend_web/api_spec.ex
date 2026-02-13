defmodule BackendWeb.ApiSpec do
  @moduledoc """
  OpenAPI specification for the Backend API.

  This module defines the OpenAPI 3.0 specification for the API,
  enabling automatic documentation generation and client SDK generation.

  ## Usage

  The spec is served at `/api/openapi` (JSON) and `/api/docs` (SwaggerUI).

  ## Generating Client SDKs

  Export the spec and use OpenAPI Generator:

      curl http://localhost:4000/api/openapi > openapi.json
      openapi-generator generate -i openapi.json -g typescript-fetch -o client/
  """

  alias OpenApiSpex.{Components, Contact, Info, License, OpenApi, Paths, SecurityScheme, Server}

  @behaviour OpenApi

  @impl OpenApi
  def spec do
    %OpenApi{
      info: %Info{
        title: "Backend API",
        version: Application.spec(:backend, :vsn) |> to_string(),
        description: """
        REST API for the Backend service.

        ## Authentication

        Most endpoints require authentication via session cookie.
        Use the OAuth endpoints (`/auth/:provider`) to authenticate.

        ## Rate Limiting

        API requests are rate-limited. If you exceed the limit,
        you'll receive a 429 Too Many Requests response.

        ## Errors

        Errors follow a consistent format:

        ```json
        {
          "error": "Error message",
          "details": { ... }
        }
        ```
        """,
        contact: %Contact{
          name: "API Support",
          email: "support@example.com"
        },
        license: %License{
          name: "MIT",
          url: "https://opensource.org/licenses/MIT"
        }
      },
      servers: [
        %Server{url: "/", description: "Current server"}
      ],
      paths: Paths.from_router(BackendWeb.Router),
      components: %Components{
        securitySchemes: %{
          "cookieAuth" => %SecurityScheme{
            type: "apiKey",
            in: "cookie",
            name: "_backend_session",
            description: "Session cookie set after OAuth authentication"
          }
        }
      }
    }
    |> OpenApiSpex.resolve_schema_modules()
  end
end
