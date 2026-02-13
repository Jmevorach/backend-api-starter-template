defmodule BackendWeb.Schemas do
  @moduledoc """
  OpenAPI schemas for request/response validation and documentation.

  These schemas are used by OpenApiSpex to:
  - Validate incoming requests
  - Generate API documentation
  - Generate client SDKs

  ## Usage

  In controllers, use the schemas for request/response documentation:

      use OpenApiSpex.ControllerSpecs

      operation :index,
        summary: "List notes",
        responses: [
          ok: {"Notes list", "application/json", NotesResponse}
        ]
  """

  alias OpenApiSpex.Schema

  require OpenApiSpex

  # ---------------------------------------------------------------------------
  # Common Schemas
  # ---------------------------------------------------------------------------

  defmodule Error do
    @moduledoc "Error response schema"
    OpenApiSpex.schema(%{
      title: "Error",
      type: :object,
      properties: %{
        error: %Schema{type: :string, description: "Error message"},
        details: %Schema{type: :object, description: "Additional error details"}
      },
      required: [:error],
      example: %{
        "error" => "Validation failed",
        "details" => %{"title" => ["can't be blank"]}
      }
    })
  end

  defmodule Pagination do
    @moduledoc "Pagination metadata schema"
    OpenApiSpex.schema(%{
      title: "Pagination",
      type: :object,
      properties: %{
        count: %Schema{type: :integer, description: "Number of items in current response"},
        total: %Schema{type: :integer, description: "Total number of items"},
        limit: %Schema{type: :integer, description: "Maximum items per page"},
        offset: %Schema{type: :integer, description: "Number of items skipped"}
      },
      example: %{
        "count" => 10,
        "total" => 42,
        "limit" => 50,
        "offset" => 0
      }
    })
  end

  # ---------------------------------------------------------------------------
  # Note Schemas
  # ---------------------------------------------------------------------------

  defmodule Note do
    @moduledoc "Note schema"
    OpenApiSpex.schema(%{
      title: "Note",
      type: :object,
      properties: %{
        id: %Schema{type: :string, format: :uuid, description: "Unique identifier"},
        title: %Schema{type: :string, description: "Note title"},
        content: %Schema{type: :string, nullable: true, description: "Note content"},
        archived: %Schema{type: :boolean, description: "Whether the note is archived"},
        inserted_at: %Schema{
          type: :string,
          format: :"date-time",
          description: "Creation timestamp"
        },
        updated_at: %Schema{
          type: :string,
          format: :"date-time",
          description: "Last update timestamp"
        }
      },
      required: [:id, :title, :archived],
      example: %{
        "id" => "550e8400-e29b-41d4-a716-446655440000",
        "title" => "My Note",
        "content" => "This is the note content",
        "archived" => false,
        "inserted_at" => "2024-01-01T00:00:00Z",
        "updated_at" => "2024-01-01T00:00:00Z"
      }
    })
  end

  defmodule NoteRequest do
    @moduledoc "Note create/update request schema"
    OpenApiSpex.schema(%{
      title: "NoteRequest",
      type: :object,
      properties: %{
        title: %Schema{type: :string, minLength: 1, maxLength: 255, description: "Note title"},
        content: %Schema{
          type: :string,
          maxLength: 10_000,
          nullable: true,
          description: "Note content"
        }
      },
      required: [:title],
      example: %{
        "title" => "My New Note",
        "content" => "This is the note content"
      }
    })
  end

  defmodule NoteResponse do
    @moduledoc "Single note response schema"
    OpenApiSpex.schema(%{
      title: "NoteResponse",
      type: :object,
      properties: %{
        data: Note
      },
      required: [:data]
    })
  end

  defmodule NotesResponse do
    @moduledoc "Notes list response schema"
    OpenApiSpex.schema(%{
      title: "NotesResponse",
      type: :object,
      properties: %{
        data: %Schema{type: :array, items: Note},
        meta: Pagination
      },
      required: [:data, :meta]
    })
  end

  # ---------------------------------------------------------------------------
  # User Schemas
  # ---------------------------------------------------------------------------

  defmodule User do
    @moduledoc "User schema"
    OpenApiSpex.schema(%{
      title: "User",
      type: :object,
      properties: %{
        email: %Schema{type: :string, format: :email, description: "User email"},
        name: %Schema{type: :string, description: "User display name"},
        first_name: %Schema{type: :string, nullable: true, description: "First name"},
        last_name: %Schema{type: :string, nullable: true, description: "Last name"},
        image: %Schema{
          type: :string,
          format: :uri,
          nullable: true,
          description: "Profile image URL"
        },
        provider: %Schema{type: :string, description: "OAuth provider (google, apple)"},
        provider_uid: %Schema{type: :string, description: "User ID from OAuth provider"}
      },
      example: %{
        "email" => "user@example.com",
        "name" => "John Doe",
        "first_name" => "John",
        "last_name" => "Doe",
        "image" => "https://example.com/avatar.jpg",
        "provider" => "google",
        "provider_uid" => "123456789"
      }
    })
  end

  defmodule MeResponse do
    @moduledoc "Current user response schema"
    OpenApiSpex.schema(%{
      title: "MeResponse",
      type: :object,
      properties: %{
        user: User,
        authenticated: %Schema{type: :boolean}
      },
      required: [:authenticated]
    })
  end

  # ---------------------------------------------------------------------------
  # Health Schemas
  # ---------------------------------------------------------------------------

  defmodule HealthResponse do
    @moduledoc "Health check response schema"
    OpenApiSpex.schema(%{
      title: "HealthResponse",
      type: :object,
      properties: %{
        status: %Schema{type: :string, enum: ["healthy", "degraded", "unhealthy"]},
        version: %Schema{type: :string},
        checks: %Schema{
          type: :object,
          additionalProperties: %Schema{
            type: :object,
            properties: %{
              status: %Schema{type: :string},
              latency_ms: %Schema{type: :number}
            }
          }
        }
      },
      required: [:status],
      example: %{
        "status" => "healthy",
        "version" => "0.1.0",
        "checks" => %{
          "database" => %{"status" => "ok", "latency_ms" => 5.2},
          "cache" => %{"status" => "ok", "latency_ms" => 1.1}
        }
      }
    })
  end

  # ---------------------------------------------------------------------------
  # Service Info Schemas
  # ---------------------------------------------------------------------------

  defmodule ServiceInfo do
    @moduledoc "Service info response schema"
    OpenApiSpex.schema(%{
      title: "ServiceInfo",
      type: :object,
      properties: %{
        status: %Schema{type: :string},
        service: %Schema{type: :string},
        version: %Schema{type: :string},
        endpoints: %Schema{type: :object}
      },
      example: %{
        "status" => "ok",
        "service" => "mobile-backend",
        "version" => "0.1.0",
        "endpoints" => %{
          "health" => "/healthz",
          "me" => "/api/me",
          "profile" => "/api/profile",
          "dashboard" => "/api/dashboard",
          "auth" => "/auth/:provider"
        }
      }
    })
  end
end
