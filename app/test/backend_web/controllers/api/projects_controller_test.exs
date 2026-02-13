defmodule BackendWeb.API.ProjectsControllerTest do
  use BackendWeb.ConnCase, async: true

  @valid_attrs %{"name" => "Platform", "description" => "Core APIs"}

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

    {:ok, conn: conn, user_id: user_id}
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
end
