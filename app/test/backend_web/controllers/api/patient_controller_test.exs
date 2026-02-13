defmodule BackendWeb.API.PatientControllerTest do
  use BackendWeb.ConnCase, async: true

  alias Backend.Notes

  setup %{conn: conn} do
    user_id = "patient_#{System.unique_integer([:positive])}"

    conn =
      conn
      |> init_test_session(%{
        current_user: %{
          "provider_uid" => user_id,
          "email" => "patient@example.com",
          "name" => "Patient Test",
          "first_name" => "Patient",
          "last_name" => "Test",
          "image" => "https://example.com/avatar.png",
          "provider" => "google"
        }
      })

    {:ok, conn: conn, user_id: user_id}
  end

  describe "GET /api/patient/profile" do
    test "returns normalized patient profile", %{conn: conn, user_id: user_id} do
      conn = get(conn, ~p"/api/patient/profile")

      assert %{
               "data" => %{
                 "id" => ^user_id,
                 "email" => "patient@example.com",
                 "name" => "Patient Test",
                 "auth_provider" => "google"
               }
             } = json_response(conn, 200)
    end
  end

  describe "GET /api/patient/dashboard" do
    test "returns dashboard with note summary and recent notes", %{conn: conn, user_id: user_id} do
      {:ok, _note1} =
        Notes.create_note(%{"title" => "A1C follow-up", "content" => "Schedule lab"}, user_id)

      {:ok, _note2} =
        Notes.create_note(%{"title" => "Blood pressure", "content" => "Daily logs"}, user_id)

      {:ok, archived_note} = Notes.create_note(%{"title" => "Archived note"}, user_id)
      Notes.archive_note(archived_note)

      conn = get(conn, ~p"/api/patient/dashboard?recent_limit=1")

      assert %{
               "data" => %{
                 "patient" => %{"id" => ^user_id},
                 "care_summary" => %{
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
