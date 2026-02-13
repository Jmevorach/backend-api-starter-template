defmodule Backend.NotesTest do
  @moduledoc """
  Tests for the Notes context.

  These tests demonstrate:
  - Unit testing Ecto schemas and changesets
  - Testing context functions
  - Database isolation with Ecto.Adapters.SQL.Sandbox
  """

  use Backend.DataCase, async: true

  alias Backend.Notes
  alias Backend.Notes.Note

  @valid_attrs %{title: "Test Note", content: "Test content"}
  @update_attrs %{title: "Updated Note", content: "Updated content"}
  @invalid_attrs %{title: nil}

  describe "Note schema" do
    test "changeset with valid data" do
      changeset = Note.changeset(%Note{}, @valid_attrs)
      assert changeset.valid?
    end

    test "changeset with invalid data" do
      changeset = Note.changeset(%Note{}, @invalid_attrs)
      refute changeset.valid?
      assert %{title: ["can't be blank"]} = errors_on(changeset)
    end

    test "changeset validates title length" do
      # Too short
      changeset = Note.changeset(%Note{}, %{title: ""})
      refute changeset.valid?
      assert %{title: [_]} = errors_on(changeset)

      # Too long
      long_title = String.duplicate("a", 256)
      changeset = Note.changeset(%Note{}, %{title: long_title})
      refute changeset.valid?
      assert %{title: ["should be at most 255 character(s)"]} = errors_on(changeset)
    end

    test "changeset validates content length" do
      long_content = String.duplicate("a", 10_001)
      changeset = Note.changeset(%Note{}, %{title: "Valid", content: long_content})
      refute changeset.valid?
      assert %{content: ["should be at most 10000 character(s)"]} = errors_on(changeset)
    end

    test "create_changeset sets user_id" do
      changeset = Note.create_changeset(%Note{}, @valid_attrs, "user123")
      assert changeset.valid?
      assert Ecto.Changeset.get_change(changeset, :user_id) == "user123"
    end
  end

  describe "list_notes/2" do
    setup do
      user_id = "test_user_#{System.unique_integer()}"
      {:ok, user_id: user_id}
    end

    test "returns empty list when no notes exist", %{user_id: user_id} do
      assert Notes.list_notes(user_id) == []
    end

    test "returns notes for the user", %{user_id: user_id} do
      {:ok, note} = Notes.create_note(@valid_attrs, user_id)

      notes = Notes.list_notes(user_id)
      assert length(notes) == 1
      assert hd(notes).id == note.id
    end

    test "does not return notes from other users", %{user_id: user_id} do
      other_user_id = "other_user_#{System.unique_integer()}"

      {:ok, _note} = Notes.create_note(@valid_attrs, other_user_id)

      assert Notes.list_notes(user_id) == []
    end

    test "filters by archived status", %{user_id: user_id} do
      {:ok, active_note} = Notes.create_note(@valid_attrs, user_id)
      {:ok, archived_note} = Notes.create_note(%{title: "Archived"}, user_id)
      {:ok, _} = Notes.archive_note(archived_note)

      # Default: only non-archived
      notes = Notes.list_notes(user_id)
      assert length(notes) == 1
      assert hd(notes).id == active_note.id

      # Archived only
      archived_notes = Notes.list_notes(user_id, archived: true)
      assert length(archived_notes) == 1
      assert hd(archived_notes).id == archived_note.id
    end

    test "respects limit option", %{user_id: user_id} do
      for i <- 1..5 do
        Notes.create_note(%{title: "Note #{i}"}, user_id)
      end

      notes = Notes.list_notes(user_id, limit: 3)
      assert length(notes) == 3
    end

    test "respects offset option", %{user_id: user_id} do
      for i <- 1..5 do
        Notes.create_note(%{title: "Note #{i}"}, user_id)
        # Small delay to ensure ordering
        Process.sleep(1)
      end

      all_notes = Notes.list_notes(user_id)
      offset_notes = Notes.list_notes(user_id, offset: 2)

      assert length(offset_notes) == 3
      assert hd(offset_notes).id == Enum.at(all_notes, 2).id
    end

    test "searches by title", %{user_id: user_id} do
      {:ok, _note1} = Notes.create_note(%{title: "Hello World"}, user_id)
      {:ok, _note2} = Notes.create_note(%{title: "Goodbye"}, user_id)

      notes = Notes.list_notes(user_id, search: "Hello")
      assert length(notes) == 1
      assert hd(notes).title == "Hello World"
    end

    test "searches by content", %{user_id: user_id} do
      {:ok, _note1} = Notes.create_note(%{title: "Note 1", content: "Important stuff"}, user_id)
      {:ok, _note2} = Notes.create_note(%{title: "Note 2", content: "Other stuff"}, user_id)

      notes = Notes.list_notes(user_id, search: "Important")
      assert length(notes) == 1
      assert hd(notes).title == "Note 1"
    end
  end

  describe "count_notes/2" do
    setup do
      user_id = "test_user_#{System.unique_integer()}"
      {:ok, user_id: user_id}
    end

    test "returns 0 when no notes exist", %{user_id: user_id} do
      assert Notes.count_notes(user_id) == 0
    end

    test "counts notes for the user", %{user_id: user_id} do
      Notes.create_note(@valid_attrs, user_id)
      Notes.create_note(%{title: "Note 2"}, user_id)

      assert Notes.count_notes(user_id) == 2
    end

    test "counts archived notes separately", %{user_id: user_id} do
      {:ok, _note1} = Notes.create_note(@valid_attrs, user_id)
      {:ok, note2} = Notes.create_note(%{title: "Note 2"}, user_id)
      Notes.archive_note(note2)

      assert Notes.count_notes(user_id) == 1
      assert Notes.count_notes(user_id, archived: true) == 1
    end
  end

  describe "get_note/2" do
    setup do
      user_id = "test_user_#{System.unique_integer()}"
      {:ok, note} = Notes.create_note(@valid_attrs, user_id)
      {:ok, user_id: user_id, note: note}
    end

    test "returns note when it exists", %{user_id: user_id, note: note} do
      fetched = Notes.get_note(note.id, user_id)
      assert fetched.id == note.id
      assert fetched.title == note.title
    end

    test "returns nil for non-existent note", %{user_id: user_id} do
      assert Notes.get_note(Ecto.UUID.generate(), user_id) == nil
    end

    test "returns nil for another user's note", %{note: note} do
      other_user_id = "other_user_#{System.unique_integer()}"
      assert Notes.get_note(note.id, other_user_id) == nil
    end
  end

  describe "get_note!/2" do
    setup do
      user_id = "test_user_#{System.unique_integer()}"
      {:ok, note} = Notes.create_note(@valid_attrs, user_id)
      {:ok, user_id: user_id, note: note}
    end

    test "returns note when it exists", %{user_id: user_id, note: note} do
      assert Notes.get_note!(note.id, user_id).id == note.id
    end

    test "raises for non-existent note", %{user_id: user_id} do
      assert_raise Ecto.NoResultsError, fn ->
        Notes.get_note!(Ecto.UUID.generate(), user_id)
      end
    end
  end

  describe "create_note/2" do
    setup do
      user_id = "test_user_#{System.unique_integer()}"
      {:ok, user_id: user_id}
    end

    test "creates note with valid data", %{user_id: user_id} do
      assert {:ok, %Note{} = note} = Notes.create_note(@valid_attrs, user_id)
      assert note.title == "Test Note"
      assert note.content == "Test content"
      assert note.user_id == user_id
      assert note.archived == false
    end

    test "returns error with invalid data", %{user_id: user_id} do
      assert {:error, changeset} = Notes.create_note(@invalid_attrs, user_id)
      assert %{title: ["can't be blank"]} = errors_on(changeset)
    end

    test "generates UUID for id", %{user_id: user_id} do
      {:ok, note} = Notes.create_note(@valid_attrs, user_id)
      assert note.id =~ ~r/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/
    end

    test "sets timestamps", %{user_id: user_id} do
      {:ok, note} = Notes.create_note(@valid_attrs, user_id)
      assert note.inserted_at != nil
      assert note.updated_at != nil
    end
  end

  describe "update_note/2" do
    setup do
      user_id = "test_user_#{System.unique_integer()}"
      {:ok, note} = Notes.create_note(@valid_attrs, user_id)
      {:ok, note: note}
    end

    test "updates note with valid data", %{note: note} do
      assert {:ok, updated} = Notes.update_note(note, @update_attrs)
      assert updated.title == "Updated Note"
      assert updated.content == "Updated content"
    end

    test "returns error with invalid data", %{note: note} do
      assert {:error, changeset} = Notes.update_note(note, @invalid_attrs)
      assert %{title: ["can't be blank"]} = errors_on(changeset)
    end

    test "updates updated_at timestamp", %{note: note} do
      # Small delay to ensure timestamp difference
      Process.sleep(10)
      {:ok, updated} = Notes.update_note(note, @update_attrs)
      assert DateTime.compare(updated.updated_at, note.updated_at) == :gt
    end
  end

  describe "archive_note/1" do
    setup do
      user_id = "test_user_#{System.unique_integer()}"
      {:ok, note} = Notes.create_note(@valid_attrs, user_id)
      {:ok, note: note}
    end

    test "archives the note", %{note: note} do
      assert {:ok, archived} = Notes.archive_note(note)
      assert archived.archived == true
    end
  end

  describe "unarchive_note/1" do
    setup do
      user_id = "test_user_#{System.unique_integer()}"
      {:ok, note} = Notes.create_note(@valid_attrs, user_id)
      {:ok, archived} = Notes.archive_note(note)
      {:ok, note: archived}
    end

    test "unarchives the note", %{note: note} do
      assert {:ok, unarchived} = Notes.unarchive_note(note)
      assert unarchived.archived == false
    end
  end

  describe "delete_note/1" do
    setup do
      user_id = "test_user_#{System.unique_integer()}"
      {:ok, note} = Notes.create_note(@valid_attrs, user_id)
      {:ok, user_id: user_id, note: note}
    end

    test "deletes the note", %{user_id: user_id, note: note} do
      assert {:ok, _deleted} = Notes.delete_note(note)
      assert Notes.get_note(note.id, user_id) == nil
    end
  end
end
