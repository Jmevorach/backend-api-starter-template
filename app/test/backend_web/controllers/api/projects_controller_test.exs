defmodule BackendWeb.API.ProjectsControllerTest do
  use BackendWeb.ConnCase, async: true

  @valid_attrs %{"name" => "Platform", "description" => "Core APIs"}

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

    {:ok, conn: conn, other_conn: other_conn, user_id: user_id}
  end

  test "creates and lists projects", %{conn: conn} do
    create_conn = post(conn, ~p"/api/v1/projects", @valid_attrs)
    assert %{"data" => %{"id" => id, "name" => "Platform"}} = json_response(create_conn, 201)

    list_conn = get(conn, ~p"/api/v1/projects")
    assert %{"data" => projects} = json_response(list_conn, 200)
    assert Enum.any?(projects, &(&1["id"] == id))
  end

  test "returns 422 for invalid payload", %{conn: conn} do
    conn = post(conn, ~p"/api/v1/projects", %{"name" => ""})

    assert %{"error" => "Validation failed", "code" => "validation_failed"} =
             json_response(conn, 422)
  end

  test "shows a project for owner and includes tasks", %{conn: conn} do
    create_conn = post(conn, ~p"/api/v1/projects", @valid_attrs)
    project_id = json_response(create_conn, 201)["data"]["id"]

    _task_conn =
      post(conn, ~p"/api/v1/tasks", %{
        "project_id" => project_id,
        "title" => "Task in project",
        "status" => "todo"
      })

    show_conn = get(conn, ~p"/api/v1/projects/#{project_id}")
    body = json_response(show_conn, 200)
    assert body["data"]["id"] == project_id
    assert is_list(body["data"]["tasks"])
    assert Enum.any?(body["data"]["tasks"], &(&1["title"] == "Task in project"))
  end

  test "returns 404 when showing unknown or unauthorized project", %{
    conn: conn,
    other_conn: other_conn
  } do
    create_conn = post(conn, ~p"/api/v1/projects", @valid_attrs)
    project_id = json_response(create_conn, 201)["data"]["id"]

    missing_conn = get(conn, ~p"/api/v1/projects/#{Ecto.UUID.generate()}")
    assert %{"code" => "project_not_found"} = json_response(missing_conn, 404)

    forbidden_conn = get(other_conn, ~p"/api/v1/projects/#{project_id}")
    assert %{"code" => "project_not_found"} = json_response(forbidden_conn, 404)
  end

  test "updates project and validates payload", %{conn: conn} do
    create_conn = post(conn, ~p"/api/v1/projects", @valid_attrs)
    project_id = json_response(create_conn, 201)["data"]["id"]

    update_conn =
      put(conn, ~p"/api/v1/projects/#{project_id}", %{
        "name" => "Platform v2",
        "archived" => true
      })

    assert %{"data" => %{"name" => "Platform v2", "archived" => true}} =
             json_response(update_conn, 200)

    invalid_conn = put(conn, ~p"/api/v1/projects/#{project_id}", %{"name" => ""})
    assert %{"code" => "validation_failed"} = json_response(invalid_conn, 422)
  end

  test "returns 404 when updating unknown project", %{conn: conn} do
    conn = put(conn, ~p"/api/v1/projects/#{Ecto.UUID.generate()}", %{"name" => "Nope"})
    assert %{"code" => "project_not_found"} = json_response(conn, 404)
  end

  test "deletes project and returns 404 for unknown delete", %{conn: conn} do
    create_conn = post(conn, ~p"/api/v1/projects", @valid_attrs)
    project_id = json_response(create_conn, 201)["data"]["id"]

    delete_conn = delete(conn, ~p"/api/v1/projects/#{project_id}")
    assert response(delete_conn, 204)

    missing_delete = delete(conn, ~p"/api/v1/projects/#{Ecto.UUID.generate()}")
    assert %{"code" => "project_not_found"} = json_response(missing_delete, 404)
  end
end
