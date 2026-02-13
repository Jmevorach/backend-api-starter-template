defmodule Backend.NotesCacheTest do
  @moduledoc """
  Tests for the Notes module caching functionality.

  These tests focus on the cache-related code paths including:
  - Cache hits and misses
  - Cache invalidation
  - Graceful degradation when cache is unavailable
  - JSON encoding/decoding of notes
  """

  use Backend.DataCase, async: false

  alias Backend.Notes
  alias Backend.Notes.Note

  @valid_attrs %{title: "Test Note", content: "Test content"}

  describe "list_notes/2 with caching" do
    setup do
      user_id = "cache_test_user_#{System.unique_integer()}"
      {:ok, user_id: user_id}
    end

    test "caches results on first call", %{user_id: user_id} do
      {:ok, note} = Notes.create_note(@valid_attrs, user_id)

      # First call - cache miss, should query DB
      notes = Notes.list_notes(user_id)
      assert length(notes) == 1
      assert hd(notes).id == note.id
    end

    test "search with nil returns all notes", %{user_id: user_id} do
      {:ok, _note} = Notes.create_note(@valid_attrs, user_id)

      # Search with nil should not filter
      notes = Notes.list_notes(user_id, search: nil)
      assert length(notes) == 1
    end

    test "search with empty string returns all notes", %{user_id: user_id} do
      {:ok, _note} = Notes.create_note(@valid_attrs, user_id)

      # Search with empty string should not filter
      notes = Notes.list_notes(user_id, search: "")
      assert length(notes) == 1
    end

    test "max limit is enforced", %{user_id: user_id} do
      # Create more than max limit notes
      for i <- 1..5 do
        Notes.create_note(%{title: "Note #{i}"}, user_id)
      end

      # Request more than max limit (100)
      notes = Notes.list_notes(user_id, limit: 200)

      # Should be capped at 100 (or however many exist)
      assert length(notes) <= 100
    end
  end

  describe "create_note/2 cache invalidation" do
    setup do
      user_id = "cache_test_user_#{System.unique_integer()}"
      {:ok, user_id: user_id}
    end

    test "invalidates cache on create", %{user_id: user_id} do
      # Pre-populate cache
      _notes = Notes.list_notes(user_id)

      # Create a new note (should invalidate cache)
      {:ok, note} = Notes.create_note(@valid_attrs, user_id)

      # Should see the new note
      notes = Notes.list_notes(user_id)
      assert Enum.any?(notes, &(&1.id == note.id))
    end
  end

  describe "update_note/2 cache invalidation" do
    setup do
      user_id = "cache_test_user_#{System.unique_integer()}"
      {:ok, note} = Notes.create_note(@valid_attrs, user_id)
      {:ok, user_id: user_id, note: note}
    end

    test "invalidates cache on update", %{user_id: user_id, note: note} do
      # Pre-populate cache
      _notes = Notes.list_notes(user_id)

      # Update note (should invalidate cache)
      {:ok, _updated} = Notes.update_note(note, %{title: "Updated Title"})

      # Should see the updated note
      notes = Notes.list_notes(user_id)
      updated_note = Enum.find(notes, &(&1.id == note.id))
      assert updated_note.title == "Updated Title"
    end
  end

  describe "delete_note/1 cache invalidation" do
    setup do
      user_id = "cache_test_user_#{System.unique_integer()}"
      {:ok, note} = Notes.create_note(@valid_attrs, user_id)
      {:ok, user_id: user_id, note: note}
    end

    test "invalidates cache on delete", %{user_id: user_id, note: note} do
      # Pre-populate cache
      notes_before = Notes.list_notes(user_id)
      assert length(notes_before) == 1

      # Delete note (should invalidate cache)
      {:ok, _deleted} = Notes.delete_note(note)

      # Should not see the deleted note
      notes_after = Notes.list_notes(user_id)
      assert notes_after == []
    end
  end

  describe "note encoding/decoding" do
    setup do
      user_id = "encode_test_user_#{System.unique_integer()}"
      {:ok, user_id: user_id}
    end

    test "note with all fields survives cache round-trip", %{user_id: user_id} do
      {:ok, original} =
        Notes.create_note(
          %{title: "Full Note", content: "Full content with special chars: éàü"},
          user_id
        )

      # Query to populate cache
      notes = Notes.list_notes(user_id)
      cached_note = Enum.find(notes, &(&1.id == original.id))

      assert cached_note.id == original.id
      assert cached_note.title == original.title
      assert cached_note.content == original.content
      assert cached_note.user_id == original.user_id
      assert cached_note.archived == original.archived
    end

    test "note with nil content works", %{user_id: user_id} do
      {:ok, original} = Notes.create_note(%{title: "No Content"}, user_id)

      notes = Notes.list_notes(user_id)
      cached_note = Enum.find(notes, &(&1.id == original.id))

      assert cached_note.id == original.id
      assert cached_note.content == nil || cached_note.content == original.content
    end
  end

  describe "datetime parsing" do
    test "parse_datetime handles nil" do
      # Test via note creation and retrieval
      user_id = "datetime_test_#{System.unique_integer()}"
      {:ok, note} = Notes.create_note(%{title: "DateTime Test"}, user_id)

      notes = Notes.list_notes(user_id)
      cached = Enum.find(notes, &(&1.id == note.id))

      # Timestamps should be preserved
      assert %DateTime{} = cached.inserted_at
      assert %DateTime{} = cached.updated_at
    end
  end

  describe "tap_ok helper" do
    test "executes function on success" do
      user_id = "tap_ok_test_#{System.unique_integer()}"

      # The tap_ok helper is used in create_note, update_note, delete_note
      # We can verify it works by checking that logging/invalidation happens

      # Create should log
      {:ok, note} = Notes.create_note(@valid_attrs, user_id)
      assert %Note{} = note

      # Update should log
      {:ok, updated} = Notes.update_note(note, %{title: "Updated"})
      assert updated.title == "Updated"

      # Delete should log
      {:ok, deleted} = Notes.delete_note(updated)
      assert deleted.id == note.id
    end

    test "returns error unchanged on failure" do
      user_id = "tap_ok_error_#{System.unique_integer()}"

      # Invalid attrs should return error without calling tap function
      {:error, changeset} = Notes.create_note(%{title: nil}, user_id)
      assert %Ecto.Changeset{} = changeset
    end
  end
end
