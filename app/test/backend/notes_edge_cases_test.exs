defmodule Backend.NotesEdgeCasesTest do
  @moduledoc """
  Edge case tests for Notes module to improve code coverage.
  """

  use Backend.DataCase, async: false

  alias Backend.Notes
  alias Backend.Notes.Note

  describe "list_notes edge cases" do
    setup do
      user_id = "edge_case_user_#{System.unique_integer()}"
      {:ok, user_id: user_id}
    end

    test "search with partial match in title", %{user_id: user_id} do
      {:ok, _note} = Notes.create_note(%{title: "Hello World Test"}, user_id)

      # Partial match should work
      notes = Notes.list_notes(user_id, search: "World")
      assert length(notes) == 1
    end

    test "search with partial match in content", %{user_id: user_id} do
      {:ok, _note} = Notes.create_note(%{title: "Title", content: "Secret content here"}, user_id)

      notes = Notes.list_notes(user_id, search: "Secret")
      assert length(notes) == 1
    end

    test "search is case insensitive", %{user_id: user_id} do
      {:ok, _note} = Notes.create_note(%{title: "UPPERCASE TITLE"}, user_id)

      notes = Notes.list_notes(user_id, search: "uppercase")
      assert length(notes) == 1
    end

    test "max limit caps at 100", %{user_id: user_id} do
      # Create some notes
      for i <- 1..5 do
        Notes.create_note(%{title: "Note #{i}"}, user_id)
      end

      # Request way more than max
      notes = Notes.list_notes(user_id, limit: 500)
      assert length(notes) <= 100
    end

    test "offset with large value returns empty", %{user_id: user_id} do
      {:ok, _note} = Notes.create_note(%{title: "Only note"}, user_id)

      notes = Notes.list_notes(user_id, offset: 1000)
      assert notes == []
    end

    test "combining multiple filters", %{user_id: user_id} do
      {:ok, _active} = Notes.create_note(%{title: "Active Note"}, user_id)
      {:ok, archived} = Notes.create_note(%{title: "Archived Note"}, user_id)
      Notes.archive_note(archived)

      # Search with archived filter
      notes = Notes.list_notes(user_id, archived: true, search: "Archived")
      assert length(notes) == 1
    end

    test "ordering is by inserted_at desc", %{user_id: user_id} do
      {:ok, first} = Notes.create_note(%{title: "First"}, user_id)
      Process.sleep(10)
      {:ok, second} = Notes.create_note(%{title: "Second"}, user_id)
      Process.sleep(10)
      {:ok, third} = Notes.create_note(%{title: "Third"}, user_id)

      notes = Notes.list_notes(user_id)

      # Most recent first
      assert Enum.at(notes, 0).id == third.id
      assert Enum.at(notes, 1).id == second.id
      assert Enum.at(notes, 2).id == first.id
    end
  end

  describe "count_notes edge cases" do
    setup do
      user_id = "count_edge_user_#{System.unique_integer()}"
      {:ok, user_id: user_id}
    end

    test "counts correctly with many notes", %{user_id: user_id} do
      for i <- 1..10 do
        Notes.create_note(%{title: "Note #{i}"}, user_id)
      end

      assert Notes.count_notes(user_id) == 10
    end

    test "archived and non-archived counts are separate", %{user_id: user_id} do
      # Create 5 active notes
      for i <- 1..5 do
        Notes.create_note(%{title: "Active #{i}"}, user_id)
      end

      # Create 3 archived notes
      for i <- 1..3 do
        {:ok, note} = Notes.create_note(%{title: "Archived #{i}"}, user_id)
        Notes.archive_note(note)
      end

      assert Notes.count_notes(user_id) == 5
      assert Notes.count_notes(user_id, archived: true) == 3
    end
  end

  describe "get_note! edge cases" do
    setup do
      user_id = "get_note_edge_user_#{System.unique_integer()}"
      {:ok, note} = Notes.create_note(%{title: "Test"}, user_id)
      {:ok, user_id: user_id, note: note}
    end

    test "raises for wrong user's note", %{note: note} do
      other_user = "other_#{System.unique_integer()}"

      assert_raise Ecto.NoResultsError, fn ->
        Notes.get_note!(note.id, other_user)
      end
    end

    test "raises for invalid UUID format", %{user_id: user_id} do
      # Invalid UUID should raise an error
      assert_raise Ecto.Query.CastError, fn ->
        Notes.get_note!("not-a-valid-uuid", user_id)
      end
    end
  end

  describe "update_note edge cases" do
    setup do
      user_id = "update_edge_user_#{System.unique_integer()}"
      {:ok, note} = Notes.create_note(%{title: "Original", content: "Original content"}, user_id)
      {:ok, note: note}
    end

    test "can clear content by setting to nil", %{note: note} do
      {:ok, updated} = Notes.update_note(note, %{content: nil})
      assert updated.content == nil
    end

    test "can update only title", %{note: note} do
      {:ok, updated} = Notes.update_note(note, %{title: "New Title"})
      assert updated.title == "New Title"
      assert updated.content == "Original content"
    end

    test "can update only content", %{note: note} do
      {:ok, updated} = Notes.update_note(note, %{content: "New Content"})
      assert updated.title == "Original"
      assert updated.content == "New Content"
    end

    test "empty update keeps values", %{note: note} do
      {:ok, updated} = Notes.update_note(note, %{})
      assert updated.title == "Original"
      assert updated.content == "Original content"
    end
  end

  describe "archive/unarchive round trip" do
    test "can archive and unarchive repeatedly" do
      user_id = "archive_round_trip_#{System.unique_integer()}"
      {:ok, note} = Notes.create_note(%{title: "Toggle Note"}, user_id)

      # Archive
      {:ok, archived} = Notes.archive_note(note)
      assert archived.archived == true

      # Unarchive
      {:ok, unarchived} = Notes.unarchive_note(archived)
      assert unarchived.archived == false

      # Archive again
      {:ok, re_archived} = Notes.archive_note(unarchived)
      assert re_archived.archived == true
    end
  end

  describe "delete_note edge cases" do
    test "deleted note doesn't appear in list" do
      user_id = "delete_list_#{System.unique_integer()}"
      {:ok, note1} = Notes.create_note(%{title: "Note 1"}, user_id)
      {:ok, note2} = Notes.create_note(%{title: "Note 2"}, user_id)

      Notes.delete_note(note1)

      notes = Notes.list_notes(user_id)
      assert length(notes) == 1
      assert hd(notes).id == note2.id
    end

    test "deleted note doesn't appear in count" do
      user_id = "delete_count_#{System.unique_integer()}"
      {:ok, note1} = Notes.create_note(%{title: "Note 1"}, user_id)
      {:ok, _note2} = Notes.create_note(%{title: "Note 2"}, user_id)

      assert Notes.count_notes(user_id) == 2

      Notes.delete_note(note1)

      assert Notes.count_notes(user_id) == 1
    end
  end

  describe "Note schema validations" do
    test "title at max length is valid" do
      title = String.duplicate("a", 255)
      changeset = Note.changeset(%Note{}, %{title: title})
      assert changeset.valid?
    end

    test "content at max length is valid" do
      content = String.duplicate("a", 10_000)
      changeset = Note.changeset(%Note{}, %{title: "Valid", content: content})
      assert changeset.valid?
    end

    test "archived defaults to false" do
      user_id = "default_archived_#{System.unique_integer()}"
      {:ok, note} = Notes.create_note(%{title: "Test"}, user_id)
      assert note.archived == false
    end
  end
end
