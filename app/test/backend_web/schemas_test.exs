defmodule BackendWeb.SchemasTest do
  @moduledoc """
  Tests for OpenAPI schemas.

  These tests verify that the schema definitions are valid and can be
  used for request/response validation.
  """

  use ExUnit.Case, async: true

  alias BackendWeb.Schemas.{
    Error,
    HealthResponse,
    MeResponse,
    Note,
    NoteRequest,
    NoteResponse,
    NotesResponse,
    Pagination,
    ServiceInfo,
    User
  }

  describe "Error schema" do
    test "has required schema fields" do
      schema = Error.schema()

      assert schema.title == "Error"
      assert schema.type == :object
      assert :error in schema.required
      assert Map.has_key?(schema.properties, :error)
      assert Map.has_key?(schema.properties, :details)
    end

    test "has valid example" do
      schema = Error.schema()

      assert schema.example["error"] == "Validation failed"
      assert is_map(schema.example["details"])
    end
  end

  describe "Pagination schema" do
    test "has required schema fields" do
      schema = Pagination.schema()

      assert schema.title == "Pagination"
      assert schema.type == :object
      assert Map.has_key?(schema.properties, :count)
      assert Map.has_key?(schema.properties, :total)
      assert Map.has_key?(schema.properties, :limit)
      assert Map.has_key?(schema.properties, :offset)
    end

    test "has valid example" do
      schema = Pagination.schema()

      assert is_integer(schema.example["count"])
      assert is_integer(schema.example["total"])
      assert is_integer(schema.example["limit"])
      assert is_integer(schema.example["offset"])
    end
  end

  describe "Note schema" do
    test "has required schema fields" do
      schema = Note.schema()

      assert schema.title == "Note"
      assert schema.type == :object
      assert :id in schema.required
      assert :title in schema.required
      assert :archived in schema.required
      assert Map.has_key?(schema.properties, :id)
      assert Map.has_key?(schema.properties, :title)
      assert Map.has_key?(schema.properties, :content)
      assert Map.has_key?(schema.properties, :archived)
      assert Map.has_key?(schema.properties, :inserted_at)
      assert Map.has_key?(schema.properties, :updated_at)
    end

    test "id field is uuid format" do
      schema = Note.schema()
      assert schema.properties.id.format == :uuid
    end

    test "has valid example" do
      schema = Note.schema()

      assert is_binary(schema.example["id"])
      assert is_binary(schema.example["title"])
      assert is_boolean(schema.example["archived"])
    end
  end

  describe "NoteRequest schema" do
    test "has required schema fields" do
      schema = NoteRequest.schema()

      assert schema.title == "NoteRequest"
      assert schema.type == :object
      assert :title in schema.required
      assert Map.has_key?(schema.properties, :title)
      assert Map.has_key?(schema.properties, :content)
    end

    test "title has length constraints" do
      schema = NoteRequest.schema()

      assert schema.properties.title.minLength == 1
      assert schema.properties.title.maxLength == 255
    end

    test "content has length constraints" do
      schema = NoteRequest.schema()

      assert schema.properties.content.maxLength == 10_000
      assert schema.properties.content.nullable == true
    end
  end

  describe "NoteResponse schema" do
    test "has required schema fields" do
      schema = NoteResponse.schema()

      assert schema.title == "NoteResponse"
      assert schema.type == :object
      assert :data in schema.required
      assert Map.has_key?(schema.properties, :data)
    end

    test "data field references Note schema" do
      schema = NoteResponse.schema()

      # The data property should reference the Note schema
      assert schema.properties.data == Note
    end
  end

  describe "NotesResponse schema" do
    test "has required schema fields" do
      schema = NotesResponse.schema()

      assert schema.title == "NotesResponse"
      assert schema.type == :object
      assert :data in schema.required
      assert :meta in schema.required
      assert Map.has_key?(schema.properties, :data)
      assert Map.has_key?(schema.properties, :meta)
    end

    test "data field is array of Notes" do
      schema = NotesResponse.schema()

      assert schema.properties.data.type == :array
      assert schema.properties.data.items == Note
    end

    test "meta field references Pagination schema" do
      schema = NotesResponse.schema()

      assert schema.properties.meta == Pagination
    end
  end

  describe "User schema" do
    test "has required schema fields" do
      schema = User.schema()

      assert schema.title == "User"
      assert schema.type == :object
      assert Map.has_key?(schema.properties, :email)
      assert Map.has_key?(schema.properties, :name)
      assert Map.has_key?(schema.properties, :first_name)
      assert Map.has_key?(schema.properties, :last_name)
      assert Map.has_key?(schema.properties, :image)
      assert Map.has_key?(schema.properties, :provider)
      assert Map.has_key?(schema.properties, :provider_uid)
    end

    test "email field has email format" do
      schema = User.schema()
      assert schema.properties.email.format == :email
    end

    test "image field has uri format" do
      schema = User.schema()
      assert schema.properties.image.format == :uri
    end

    test "has valid example" do
      schema = User.schema()

      assert schema.example["email"] =~ "@"
      assert is_binary(schema.example["provider"])
    end
  end

  describe "MeResponse schema" do
    test "has required schema fields" do
      schema = MeResponse.schema()

      assert schema.title == "MeResponse"
      assert schema.type == :object
      assert :authenticated in schema.required
      assert Map.has_key?(schema.properties, :user)
      assert Map.has_key?(schema.properties, :authenticated)
    end

    test "user field references User schema" do
      schema = MeResponse.schema()

      assert schema.properties.user == User
    end

    test "authenticated field is boolean" do
      schema = MeResponse.schema()

      assert schema.properties.authenticated.type == :boolean
    end
  end

  describe "HealthResponse schema" do
    test "has required schema fields" do
      schema = HealthResponse.schema()

      assert schema.title == "HealthResponse"
      assert schema.type == :object
      assert :status in schema.required
      assert Map.has_key?(schema.properties, :status)
      assert Map.has_key?(schema.properties, :version)
      assert Map.has_key?(schema.properties, :checks)
    end

    test "status field has valid enum values" do
      schema = HealthResponse.schema()

      assert "healthy" in schema.properties.status.enum
      assert "degraded" in schema.properties.status.enum
      assert "unhealthy" in schema.properties.status.enum
    end

    test "has valid example" do
      schema = HealthResponse.schema()

      assert schema.example["status"] in ["healthy", "degraded", "unhealthy"]
    end
  end

  describe "ServiceInfo schema" do
    test "has required schema fields" do
      schema = ServiceInfo.schema()

      assert schema.title == "ServiceInfo"
      assert schema.type == :object
      assert Map.has_key?(schema.properties, :status)
      assert Map.has_key?(schema.properties, :service)
      assert Map.has_key?(schema.properties, :version)
      assert Map.has_key?(schema.properties, :endpoints)
    end

    test "has valid example" do
      schema = ServiceInfo.schema()

      assert schema.example["status"] == "ok"
      assert schema.example["service"] == "mobile-backend"
      assert is_map(schema.example["endpoints"])
    end
  end

  describe "schema module functions" do
    test "all schemas define schema/0 function" do
      # All OpenApiSpex schemas should have a schema/0 function
      # Ensure modules are loaded before checking exports
      modules = [
        Error,
        Pagination,
        Note,
        NoteRequest,
        NoteResponse,
        NotesResponse,
        User,
        MeResponse,
        HealthResponse,
        ServiceInfo
      ]

      for module <- modules do
        Code.ensure_loaded!(module)

        assert function_exported?(module, :schema, 0),
               "Expected #{inspect(module)} to export schema/0"
      end
    end
  end
end
