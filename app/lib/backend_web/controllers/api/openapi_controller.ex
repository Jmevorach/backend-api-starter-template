defmodule BackendWeb.API.OpenApiController do
  @moduledoc """
  Controller for serving OpenAPI specification and documentation.

  ## Endpoints

  - `GET /api/openapi` - OpenAPI spec as JSON
  - `GET /api/docs` - SwaggerUI documentation
  - `GET /api/v1/openapi` - OpenAPI spec as JSON (versioned docs route)
  - `GET /api/v1/docs` - SwaggerUI documentation (versioned docs route)
  """

  use BackendWeb, :controller

  @doc """
  Serves the OpenAPI specification as JSON.

  This can be used by:
  - API documentation tools
  - Client SDK generators
  - API testing tools
  """
  def spec(conn, _params) do
    spec = BackendWeb.ApiSpec.spec()

    conn
    |> put_resp_content_type("application/json")
    |> json(spec)
  end

  @doc """
  Serves SwaggerUI for interactive API documentation.
  """
  def docs(conn, _params) do
    html = """
    <!DOCTYPE html>
    <html lang="en">
    <head>
      <meta charset="UTF-8">
      <meta name="viewport" content="width=device-width, initial-scale=1.0">
      <title>Backend API Documentation</title>
      <link rel="stylesheet" type="text/css" href="https://unpkg.com/swagger-ui-dist@5/swagger-ui.css">
      <style>
        body { margin: 0; padding: 0; }
        .swagger-ui .topbar { display: none; }
      </style>
    </head>
    <body>
      <div id="swagger-ui"></div>
      <script src="https://unpkg.com/swagger-ui-dist@5/swagger-ui-bundle.js"></script>
      <script>
        window.onload = function() {
          SwaggerUIBundle({
            url: "/api/openapi",
            dom_id: '#swagger-ui',
            deepLinking: true,
            presets: [
              SwaggerUIBundle.presets.apis,
              SwaggerUIBundle.SwaggerUIStandalonePreset
            ],
            layout: "BaseLayout",
            persistAuthorization: true,
            tryItOutEnabled: true
          });
        };
      </script>
    </body>
    </html>
    """

    conn
    |> put_resp_content_type("text/html")
    |> send_resp(200, html)
  end
end
