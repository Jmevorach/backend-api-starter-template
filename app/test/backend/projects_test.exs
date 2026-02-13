defmodule Backend.ProjectsTest do
  use Backend.DataCase, async: true

  alias Backend.Projects

  test "project lifecycle and scoped listing" do
    user_id = "user_#{System.unique_integer()}"
    other_user_id = "user_#{System.unique_integer()}"

    assert {:ok, p1} = Projects.create_project(%{name: "One"}, user_id)
    assert {:ok, _p2} = Projects.create_project(%{name: "Two"}, other_user_id)

    list = Projects.list_projects(user_id)
    assert Enum.map(list, & &1.id) == [p1.id]

    assert nil == Projects.get_project(p1.id, other_user_id)
    assert %{} = Projects.get_project(p1.id, user_id)

    assert {:ok, updated} = Projects.update_project(p1, %{name: "Renamed", archived: true})
    assert updated.name == "Renamed"
    assert updated.archived == true

    assert {:ok, _} = Projects.delete_project(updated)
    assert [] == Projects.list_projects(user_id)
  end

  test "task lifecycle, filtering and ownership checks" do
    user_id = "user_#{System.unique_integer()}"
    other_user_id = "user_#{System.unique_integer()}"
    {:ok, project} = Projects.create_project(%{name: "Main"}, user_id)
    {:ok, other_project} = Projects.create_project(%{name: "Other"}, other_user_id)

    assert {:error, :project_not_found} =
             Projects.create_task(other_project.id, %{title: "Nope"}, user_id)

    assert {:ok, t1} =
             Projects.create_task(project.id, %{title: "A", status: "todo"}, user_id)

    assert {:ok, t2} =
             Projects.create_task(project.id, %{title: "B", status: "in_progress"}, user_id)

    all_tasks = Projects.list_tasks(user_id)
    assert Enum.map(all_tasks, & &1.id) == [t1.id, t2.id]

    todo_tasks = Projects.list_tasks(user_id, status: "todo")
    assert Enum.map(todo_tasks, & &1.id) == [t1.id]

    scoped = Projects.list_tasks(user_id, project_id: project.id)
    assert length(scoped) == 2

    assert nil == Projects.get_task(t1.id, other_user_id)
    assert %{} = Projects.get_task(t1.id, user_id)

    assert {:ok, updated} = Projects.update_task(t1, %{title: "A2", status: "done"})
    assert updated.title == "A2"
    assert updated.status == "done"

    assert {:ok, _} = Projects.delete_task(t2)
    assert length(Projects.list_tasks(user_id)) == 1
  end
end
