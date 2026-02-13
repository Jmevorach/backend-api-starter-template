defmodule BackendWeb.API.TasksControllerTest do
  use BackendWeb.ConnCase, async: true

  setup %{conn: conn} do
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

    {:ok, conn: conn}
  end

  test "creates and lists tasks", %{conn: conn} do
    project_conn = post(conn, ~p"/api/v1/projects", %{"name" => "Build"})
    project_id = json_response(project_conn, 201)["data"]["id"]

    task_conn =
      post(conn, ~p"/api/v1/tasks", %{
        "project_id" => project_id,
        "title" => "Wire API",
        "status" => "todo"
      })

    assert %{"data" => %{"title" => "Wire API", "project_id" => ^project_id}} =
             json_response(task_conn, 201)

    list_conn = get(conn, ~p"/api/v1/tasks?project_id=#{project_id}")
    assert %{"data" => tasks} = json_response(list_conn, 200)
    assert Enum.any?(tasks, &(&1["title"] == "Wire API"))
  end

  test "returns 404 when project does not exist", %{conn: conn} do
    conn =
      post(conn, ~p"/api/v1/tasks", %{
        "project_id" => Ecto.UUID.generate(),
        "title" => "Orphan"
      })

    assert %{"error" => "Project not found", "code" => "project_not_found"} =
             json_response(conn, 404)
  end
end
