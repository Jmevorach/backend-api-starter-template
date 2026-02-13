defmodule BackendWeb.Router do
  @moduledoc """
  Phoenix Router for the Backend application.

  This module defines all HTTP routes and their pipelines. Routes are organized
  into scopes based on their purpose and authentication requirements:

  ## Pipelines

  - `:browser` - Accepts HTML requests (for OAuth redirects/callbacks)
  - `:api` - Accepts JSON requests (public API endpoints)
  - `:protected_api` - JSON requests requiring authentication

  ## Route Groups

  ### Authentication (`/auth/*`)
  OAuth login flows for Google and Apple Sign-In. These routes handle the
  OAuth redirect dance and session establishment.

  ### API (`/api/*`)
  JSON API endpoints for client applications. Currently includes user info.

  ### Root (`/`)
  JSON metadata for the service (useful for quick sanity checks).

  ## Adding New Routes

  1. Choose the appropriate scope based on authentication needs
  2. Use `pipe_through` to apply the correct pipeline
  3. Follow REST conventions for API routes

  ## Example

      scope "/api/v2", BackendWeb.API.V2 do
        pipe_through :protected_api

        resources "/posts", PostController, only: [:index, :show, :create]
      end
  """

  use Phoenix.Router

  import Phoenix.Controller

  # ---------------------------------------------------------------------------
  # Pipelines
  # ---------------------------------------------------------------------------
  # Pipelines are sets of plugs that transform the connection.
  # Each request passes through the plugs in its assigned pipeline.

  @doc """
  Browser pipeline for OAuth redirects/callbacks.
  """
  pipeline :browser do
    plug(:accepts, ["html"])
  end

  @doc """
  API pipeline for JSON responses.
  Used for public API endpoints that don't require authentication.
  """
  pipeline :api do
    plug(:accepts, ["json"])
  end

  @doc """
  Protected API pipeline for authenticated JSON endpoints.
  Applies authentication check before reaching the controller.
  """
  pipeline :protected_api do
    plug(:accepts, ["json"])
    plug(BackendWeb.Plugs.EnsureAuthenticated)
  end

  # ---------------------------------------------------------------------------
  # Authentication Routes
  # ---------------------------------------------------------------------------
  # OAuth login flow routes. Ueberauth handles the actual OAuth logic.
  #
  # Flow:
  # 1. GET /auth/:provider - Redirects to OAuth provider
  # 2. GET /auth/:provider/callback - Provider redirects back here
  # 3. Session is established, user redirected to home

  scope "/auth", BackendWeb do
    pipe_through(:browser)

    # Initiate OAuth flow (redirects to provider)
    get("/:provider", AuthController, :request)

    # OAuth callback (provider redirects here after auth)
    get("/:provider/callback", AuthController, :callback)
    post("/:provider/callback", AuthController, :callback)

    # Logout (destroys session)
    get("/logout", AuthController, :logout)
    delete("/logout", AuthController, :logout)
  end

  # ---------------------------------------------------------------------------
  # API Routes
  # ---------------------------------------------------------------------------
  # JSON API endpoints for client applications.
  # Use protected_api for routes that require auth.

  scope "/api", BackendWeb.API, as: :api do
    pipe_through(:protected_api)

    # Get current user info (returns 401 if not authenticated)
    get("/me", UserController, :me)

    # Notes CRUD API - demonstrates database operations and caching
    resources("/notes", NotesController, except: [:new, :edit])
    post("/notes/:id/archive", NotesController, :archive)
    post("/notes/:id/unarchive", NotesController, :unarchive)

    # File uploads API - S3 presigned URL management
    # GET  /api/uploads              - List user's files
    # POST /api/uploads/presign      - Get presigned upload URL
    # GET  /api/uploads/types        - Get allowed content types
    # GET  /api/uploads/:key         - Get file metadata
    # GET  /api/uploads/:key/download - Get presigned download URL
    # DELETE /api/uploads/:key       - Delete a file
    get("/uploads", UploadsController, :index)
    post("/uploads/presign", UploadsController, :presign)
    get("/uploads/types", UploadsController, :allowed_types)
    get("/uploads/:key", UploadsController, :show)
    get("/uploads/:key/download", UploadsController, :download)
    delete("/uploads/:key", UploadsController, :delete)
  end

  # ---------------------------------------------------------------------------
  # Root Route
  # ---------------------------------------------------------------------------
  # JSON metadata for the service.

  scope "/", BackendWeb do
    pipe_through(:api)

    # Root endpoint with service metadata
    get("/", HomeController, :index)
  end

  # ---------------------------------------------------------------------------
  # Health Check
  # ---------------------------------------------------------------------------
  # Infrastructure health check endpoint.
  # Used by ALB, ECS, and Global Accelerator for health monitoring.

  scope "/", BackendWeb do
    pipe_through(:api)

    # Health check - returns 200 if healthy, 503 if degraded
    # Add ?detailed=true for component-level status
    get("/healthz", HealthController, :index)
  end

  # ---------------------------------------------------------------------------
  # API Documentation
  # ---------------------------------------------------------------------------
  # OpenAPI specification and SwaggerUI documentation.

  scope "/api", BackendWeb.API, as: :api do
    pipe_through(:api)

    # OpenAPI spec as JSON
    get("/openapi", OpenApiController, :spec)

    # SwaggerUI documentation
    get("/docs", OpenApiController, :docs)
  end
end
