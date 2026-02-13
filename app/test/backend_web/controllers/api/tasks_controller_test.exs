defmodule BackendWeb.API.TasksControllerTest do
  use BackendWeb.ConnCase, async: true

  setup %{conn: conn} do
    user_id = "test_user_#{System.unique_integer()}"
    other_user_id = "other_user_#{System.unique_integer()}"

    conn =
      conn
      |> init_test_session(%{
        current_user: %{
          "provider_uid" => user_id,
          "email" => "test@example.com",
          "name" => "Test User"
        }
      })

    other_conn =
      build_conn()
      |> init_test_session(%{
        current_user: %{
          "provider_uid" => other_user_id,
          "email" => "other@example.com",
          "name" => "Other User"
        }
      })

    {:ok, conn: conn, other_conn: other_conn}
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

  test "returns 400 when project_id is missing", %{conn: conn} do
    conn = post(conn, ~p"/api/v1/tasks", %{"title" => "No project"})
    assert %{"code" => "invalid_request"} = json_response(conn, 400)
  end

  test "shows, updates and deletes task", %{conn: conn} do
    project_id = json_response(post(conn, ~p"/api/v1/projects", %{"name" => "Build"}), 201)["data"]["id"]

    task_id =
      json_response(
        post(conn, ~p"/api/v1/tasks", %{"project_id" => project_id, "title" => "Initial", "status" => "todo"}),
        201
      )["data"]["id"]

    show_conn = get(conn, ~p"/api/v1/tasks/#{task_id}")
    assert %{"data" => %{"id" => ^task_id, "title" => "Initial"}} = json_response(show_conn, 200)

    update_conn = put(conn, ~p"/api/v1/tasks/#{task_id}", %{"title" => "Updated", "status" => "done"})
    assert %{"data" => %{"title" => "Updated", "status" => "done"}} = json_response(update_conn, 200)

    delete_conn = delete(conn, ~p"/api/v1/tasks/#{task_id}")
    assert response(delete_conn, 204)
  end

  test "returns validation error for invalid update payload", %{conn: conn} do
    project_id = json_response(post(conn, ~p"/api/v1/projects", %{"name" => "Build"}), 201)["data"]["id"]

    task_id =
      json_response(
        post(conn, ~p"/api/v1/tasks", %{"project_id" => project_id, "title" => "Initial", "status" => "todo"}),
        201
      )["data"]["id"]

    conn = put(conn, ~p"/api/v1/tasks/#{task_id}", %{"status" => "bad_status"})
    assert %{"code" => "validation_failed"} = json_response(conn, 422)
  end

  test "returns 404 for unknown and unauthorized task access", %{conn: conn, other_conn: other_conn} do
    project_id = json_response(post(conn, ~p"/api/v1/projects", %{"name" => "Build"}), 201)["data"]["id"]

    task_id =
      json_response(
        post(conn, ~p"/api/v1/tasks", %{"project_id" => project_id, "title" => "Initial", "status" => "todo"}),
        201
      )["data"]["id"]

    missing_show = get(conn, ~p"/api/v1/tasks/#{Ecto.UUID.generate()}")
    assert %{"code" => "task_not_found"} = json_response(missing_show, 404)

    other_show = get(other_conn, ~p"/api/v1/tasks/#{task_id}")
    assert %{"code" => "task_not_found"} = json_response(other_show, 404)

    missing_delete = delete(conn, ~p"/api/v1/tasks/#{Ecto.UUID.generate()}")
    assert %{"code" => "task_not_found"} = json_response(missing_delete, 404)
  end
end
