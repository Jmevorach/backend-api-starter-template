defmodule BackendWeb.API.ProfileControllerTest do
  use BackendWeb.ConnCase, async: true

  alias Backend.Notes

  setup %{conn: conn} do
    user_id = "user_#{System.unique_integer([:positive])}"

    conn =
      conn
      |> init_test_session(%{
        current_user: %{
          "provider_uid" => user_id,
          "email" => "user@example.com",
          "name" => "User Test",
          "first_name" => "User",
          "last_name" => "Test",
          "image" => "https://example.com/avatar.png",
          "provider" => "google"
        }
      })

    {:ok, conn: conn, user_id: user_id}
  end

  describe "GET /api/profile" do
    test "returns normalized profile", %{conn: conn, user_id: user_id} do
      conn = get(conn, ~p"/api/profile")

      assert %{
               "data" => %{
                 "id" => ^user_id,
                 "email" => "user@example.com",
                 "name" => "User Test",
                 "auth_provider" => "google"
               }
             } = json_response(conn, 200)
    end
  end

  describe "GET /api/dashboard" do
    test "returns dashboard with note summary and recent notes", %{conn: conn, user_id: user_id} do
      {:ok, _note1} =
        Notes.create_note(
          %{"title" => "Sprint follow-up", "content" => "Schedule planning"},
          user_id
        )

      {:ok, _note2} =
        Notes.create_note(%{"title" => "Blood pressure", "content" => "Daily logs"}, user_id)

      {:ok, archived_note} = Notes.create_note(%{"title" => "Archived note"}, user_id)
      Notes.archive_note(archived_note)

      conn = get(conn, ~p"/api/dashboard?recent_limit=1")

      assert %{
               "data" => %{
                 "user" => %{"id" => ^user_id},
                 "summary" => %{
                   "active_notes" => 2,
                   "archived_notes" => 1,
                   "recent_notes" => recent_notes
                 }
               }
             } = json_response(conn, 200)

      assert length(recent_notes) == 1
    end
  end
end
