defmodule BackendWeb.API.NotesControllerTest do
  @moduledoc """
  Tests for the Notes API controller.

  These tests demonstrate:
  - Controller testing with Phoenix.ConnTest
  - Authentication setup for protected routes
  - JSON response assertions
  - HTTP status code verification
  """

  use BackendWeb.ConnCase, async: true

  alias Backend.Notes

  @valid_attrs %{"title" => "Test Note", "content" => "Test content"}
  @update_attrs %{"title" => "Updated Note", "content" => "Updated content"}
  @invalid_attrs %{"title" => ""}

  setup %{conn: conn} do
    # Set up authenticated user
    user_id = "test_user_#{System.unique_integer()}"

    conn =
      conn
      |> init_test_session(%{
        current_user: %{
          "provider_uid" => user_id,
          "email" => "test@example.com",
          "name" => "Test User"
        }
      })

    {:ok, conn: conn, user_id: user_id}
  end

  describe "GET /api/notes" do
    test "returns empty list when no notes exist", %{conn: conn} do
      conn = get(conn, ~p"/api/notes")

      assert %{
               "data" => [],
               "meta" => %{"count" => 0, "total" => 0}
             } = json_response(conn, 200)
    end

    test "returns notes for authenticated user", %{conn: conn, user_id: user_id} do
      {:ok, note} = Notes.create_note(@valid_attrs, user_id)

      conn = get(conn, ~p"/api/notes")

      assert %{
               "data" => [%{"id" => id, "title" => "Test Note"}],
               "meta" => %{"count" => 1, "total" => 1}
             } = json_response(conn, 200)

      assert id == note.id
    end

    test "filters by archived status", %{conn: conn, user_id: user_id} do
      {:ok, _active} = Notes.create_note(%{"title" => "Active"}, user_id)
      {:ok, archived} = Notes.create_note(%{"title" => "Archived"}, user_id)
      Notes.archive_note(archived)

      # Default: non-archived only
      conn1 = get(conn, ~p"/api/notes")
      assert %{"data" => [%{"title" => "Active"}]} = json_response(conn1, 200)

      # Archived only
      conn2 = get(conn, ~p"/api/notes?archived=true")
      assert %{"data" => [%{"title" => "Archived"}]} = json_response(conn2, 200)
    end

    test "supports pagination", %{conn: conn, user_id: user_id} do
      for i <- 1..5 do
        Notes.create_note(%{"title" => "Note #{i}"}, user_id)
      end

      conn = get(conn, ~p"/api/notes?limit=2&offset=2")

      assert %{
               "data" => data,
               "meta" => %{"limit" => 2, "offset" => 2}
             } = json_response(conn, 200)

      assert length(data) == 2
    end

    test "supports search", %{conn: conn, user_id: user_id} do
      {:ok, _note1} = Notes.create_note(%{"title" => "Hello World"}, user_id)
      {:ok, _note2} = Notes.create_note(%{"title" => "Goodbye"}, user_id)

      conn = get(conn, ~p"/api/notes?search=Hello")

      assert %{"data" => [%{"title" => "Hello World"}]} = json_response(conn, 200)
    end
  end

  describe "GET /api/notes/:id" do
    test "returns note when it exists", %{conn: conn, user_id: user_id} do
      {:ok, note} = Notes.create_note(@valid_attrs, user_id)
      note_id = note.id

      conn = get(conn, ~p"/api/notes/#{note.id}")

      assert %{
               "data" => %{
                 "id" => ^note_id,
                 "title" => "Test Note",
                 "content" => "Test content"
               }
             } = json_response(conn, 200)
    end

    test "returns 404 for non-existent note", %{conn: conn} do
      conn = get(conn, ~p"/api/notes/#{Ecto.UUID.generate()}")
      assert %{"error" => "Note not found"} = json_response(conn, 404)
    end

    test "returns 404 for another user's note", %{conn: conn} do
      other_user_id = "other_user_#{System.unique_integer()}"
      {:ok, note} = Notes.create_note(@valid_attrs, other_user_id)

      conn = get(conn, ~p"/api/notes/#{note.id}")
      assert %{"error" => "Note not found"} = json_response(conn, 404)
    end
  end

  describe "POST /api/notes" do
    test "creates note with valid data", %{conn: conn} do
      conn = post(conn, ~p"/api/notes", @valid_attrs)

      assert %{
               "data" => %{
                 "id" => id,
                 "title" => "Test Note",
                 "content" => "Test content",
                 "archived" => false
               }
             } = json_response(conn, 201)

      assert id =~ ~r/^[0-9a-f-]{36}$/
    end

    test "returns error with invalid data", %{conn: conn} do
      conn = post(conn, ~p"/api/notes", @invalid_attrs)

      assert %{
               "error" => "Validation failed",
               "details" => %{"title" => _}
             } = json_response(conn, 422)
    end
  end

  describe "PUT /api/notes/:id" do
    test "updates note with valid data", %{conn: conn, user_id: user_id} do
      {:ok, note} = Notes.create_note(@valid_attrs, user_id)
      note_id = note.id

      conn = put(conn, ~p"/api/notes/#{note.id}", @update_attrs)

      assert %{
               "data" => %{
                 "id" => ^note_id,
                 "title" => "Updated Note",
                 "content" => "Updated content"
               }
             } = json_response(conn, 200)
    end

    test "returns 404 for non-existent note", %{conn: conn} do
      conn = put(conn, ~p"/api/notes/#{Ecto.UUID.generate()}", @update_attrs)
      assert %{"error" => "Note not found"} = json_response(conn, 404)
    end

    test "returns error with invalid data", %{conn: conn, user_id: user_id} do
      {:ok, note} = Notes.create_note(@valid_attrs, user_id)

      conn = put(conn, ~p"/api/notes/#{note.id}", @invalid_attrs)
      assert %{"error" => "Validation failed"} = json_response(conn, 422)
    end
  end

  describe "DELETE /api/notes/:id" do
    test "deletes note", %{conn: conn, user_id: user_id} do
      {:ok, note} = Notes.create_note(@valid_attrs, user_id)

      conn = delete(conn, ~p"/api/notes/#{note.id}")
      assert response(conn, 204)

      # Verify deletion
      assert Notes.get_note(note.id, user_id) == nil
    end

    test "returns 404 for non-existent note", %{conn: conn} do
      conn = delete(conn, ~p"/api/notes/#{Ecto.UUID.generate()}")
      assert %{"error" => "Note not found"} = json_response(conn, 404)
    end
  end

  describe "POST /api/notes/:id/archive" do
    test "archives note", %{conn: conn, user_id: user_id} do
      {:ok, note} = Notes.create_note(@valid_attrs, user_id)

      conn = post(conn, ~p"/api/notes/#{note.id}/archive")

      assert %{"data" => %{"archived" => true}} = json_response(conn, 200)
    end

    test "returns 404 for non-existent note", %{conn: conn} do
      conn = post(conn, ~p"/api/notes/#{Ecto.UUID.generate()}/archive")
      assert %{"error" => "Note not found"} = json_response(conn, 404)
    end
  end

  describe "POST /api/notes/:id/unarchive" do
    test "unarchives note", %{conn: conn, user_id: user_id} do
      {:ok, note} = Notes.create_note(@valid_attrs, user_id)
      Notes.archive_note(note)

      conn = post(conn, ~p"/api/notes/#{note.id}/unarchive")

      assert %{"data" => %{"archived" => false}} = json_response(conn, 200)
    end
  end
end
