defmodule BackendWeb.API.NotesController do
  @moduledoc """
  Notes API controller for CRUD operations.

  This controller demonstrates:
  - RESTful API design
  - Request parameter validation
  - Proper error handling
  - Pagination with metadata
  - JSON response formatting

  ## Endpoints

  - `GET /api/notes` - List notes with optional filters
  - `GET /api/notes/:id` - Get a single note
  - `POST /api/notes` - Create a new note
  - `PUT /api/notes/:id` - Update a note
  - `DELETE /api/notes/:id` - Delete a note
  - `POST /api/notes/:id/archive` - Archive a note
  - `POST /api/notes/:id/unarchive` - Unarchive a note

  ## Authentication

  All endpoints require authentication via the `:protected_api` pipeline.
  The user is identified by their OAuth provider UID stored in the session.

  ## Response Format

  Success responses follow the format:

      {
        "data": {...},
        "meta": {...}
      }

  Error responses follow the format:

      {
        "error": "Error message",
        "details": {...}
      }
  """

  use BackendWeb, :controller

  alias Backend.Notes
  alias Backend.Notes.Note
  alias BackendWeb.ErrorResponse

  action_fallback(BackendWeb.FallbackController)

  @doc """
  Lists notes for the authenticated user.

  ## Query Parameters

  - `archived` - Filter by archived status ("true" or "false", default: "false")
  - `limit` - Maximum results (1-100, default: 50)
  - `offset` - Skip N results (default: 0)
  - `search` - Search in title and content

  ## Response

      {
        "data": [
          {
            "id": "uuid",
            "title": "My Note",
            "content": "Note content",
            "archived": false,
            "inserted_at": "2024-01-01T00:00:00Z",
            "updated_at": "2024-01-01T00:00:00Z"
          }
        ],
        "meta": {
          "count": 1,
          "total": 42,
          "limit": 50,
          "offset": 0
        }
      }
  """
  def index(conn, params) do
    user_id = get_user_id(conn)

    opts = [
      archived: params["archived"] == "true",
      limit: parse_int(params["limit"], 50),
      offset: parse_int(params["offset"], 0),
      search: params["search"]
    ]

    notes = Notes.list_notes(user_id, opts)
    total = Notes.count_notes(user_id, archived: opts[:archived])

    json(conn, %{
      data: Enum.map(notes, &note_json/1),
      meta: %{
        count: length(notes),
        total: total,
        limit: opts[:limit],
        offset: opts[:offset]
      }
    })
  end

  @doc """
  Gets a single note by ID.

  ## Response

      {
        "data": {
          "id": "uuid",
          "title": "My Note",
          "content": "Note content",
          "archived": false,
          "inserted_at": "2024-01-01T00:00:00Z",
          "updated_at": "2024-01-01T00:00:00Z"
        }
      }

  ## Errors

  - `404 Not Found` - Note doesn't exist or belongs to another user
  """
  def show(conn, %{"id" => id}) do
    user_id = get_user_id(conn)

    case Notes.get_note(id, user_id) do
      nil ->
        conn
        |> ErrorResponse.send(:not_found, "note_not_found", "Note not found")

      note ->
        json(conn, %{data: note_json(note)})
    end
  end

  @doc """
  Creates a new note.

  ## Request Body

      {
        "title": "My Note",
        "content": "Optional content"
      }

  ## Response

      {
        "data": {
          "id": "uuid",
          "title": "My Note",
          ...
        }
      }

  ## Errors

  - `422 Unprocessable Entity` - Validation failed
  """
  def create(conn, params) do
    user_id = get_user_id(conn)

    case Notes.create_note(params, user_id) do
      {:ok, note} ->
        conn
        |> put_status(:created)
        |> json(%{data: note_json(note)})

      {:error, changeset} ->
        conn
        |> ErrorResponse.send(
          :unprocessable_entity,
          "validation_failed",
          "Validation failed",
          translate_errors(changeset)
        )
    end
  end

  @doc """
  Updates an existing note.

  ## Request Body

      {
        "title": "Updated Title",
        "content": "Updated content"
      }

  ## Response

      {
        "data": {
          "id": "uuid",
          "title": "Updated Title",
          ...
        }
      }

  ## Errors

  - `404 Not Found` - Note doesn't exist
  - `422 Unprocessable Entity` - Validation failed
  """
  def update(conn, %{"id" => id} = params) do
    user_id = get_user_id(conn)

    case Notes.get_note(id, user_id) do
      nil ->
        conn
        |> ErrorResponse.send(:not_found, "note_not_found", "Note not found")

      note ->
        case Notes.update_note(note, params) do
          {:ok, updated_note} ->
            json(conn, %{data: note_json(updated_note)})

          {:error, changeset} ->
            conn
            |> ErrorResponse.send(
              :unprocessable_entity,
              "validation_failed",
              "Validation failed",
              translate_errors(changeset)
            )
        end
    end
  end

  @doc """
  Deletes a note permanently.

  ## Response

  - `204 No Content` on success

  ## Errors

  - `404 Not Found` - Note doesn't exist
  """
  def delete(conn, %{"id" => id}) do
    user_id = get_user_id(conn)

    case Notes.get_note(id, user_id) do
      nil ->
        conn
        |> ErrorResponse.send(:not_found, "note_not_found", "Note not found")

      note ->
        {:ok, _deleted} = Notes.delete_note(note)
        send_resp(conn, :no_content, "")
    end
  end

  @doc """
  Archives a note (soft delete).

  ## Response

      {
        "data": {
          "id": "uuid",
          "archived": true,
          ...
        }
      }
  """
  def archive(conn, %{"id" => id}) do
    user_id = get_user_id(conn)

    case Notes.get_note(id, user_id) do
      nil ->
        conn
        |> ErrorResponse.send(:not_found, "note_not_found", "Note not found")

      note ->
        {:ok, archived_note} = Notes.archive_note(note)
        json(conn, %{data: note_json(archived_note)})
    end
  end

  @doc """
  Unarchives a note.

  ## Response

      {
        "data": {
          "id": "uuid",
          "archived": false,
          ...
        }
      }
  """
  def unarchive(conn, %{"id" => id}) do
    user_id = get_user_id(conn)

    case Notes.get_note(id, user_id) do
      nil ->
        conn
        |> ErrorResponse.send(:not_found, "note_not_found", "Note not found")

      note ->
        {:ok, unarchived_note} = Notes.unarchive_note(note)
        json(conn, %{data: note_json(unarchived_note)})
    end
  end

  # ---------------------------------------------------------------------------
  # Private Functions
  # ---------------------------------------------------------------------------

  defp get_user_id(conn) do
    case get_session(conn, :current_user) do
      %{"provider_uid" => uid} -> uid
      %{provider_uid: uid} -> uid
      _ -> raise "User not authenticated"
    end
  end

  defp parse_int(nil, default), do: default

  defp parse_int(str, default) when is_binary(str) do
    case Integer.parse(str) do
      {int, _} when int > 0 -> int
      _ -> default
    end
  end

  defp parse_int(_, default), do: default

  defp note_json(%Note{} = note) do
    %{
      id: note.id,
      title: note.title,
      content: note.content,
      archived: note.archived,
      inserted_at: note.inserted_at,
      updated_at: note.updated_at
    }
  end

  defp translate_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
  end
end
