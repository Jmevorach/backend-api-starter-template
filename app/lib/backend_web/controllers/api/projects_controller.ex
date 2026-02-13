defmodule BackendWeb.API.ProjectsController do
  use BackendWeb, :controller

  alias Backend.Projects
  alias Backend.Projects.Project
  alias BackendWeb.ErrorResponse

  action_fallback(BackendWeb.FallbackController)

  def index(conn, _params) do
    user_id = user_id(conn)
    projects = Projects.list_projects(user_id)

    json(conn, %{data: Enum.map(projects, &project_json/1)})
  end

  def show(conn, %{"id" => id}) do
    user_id = user_id(conn)

    case Projects.get_project(id, user_id) do
      nil -> ErrorResponse.send(conn, :not_found, "project_not_found", "Project not found")
      project -> json(conn, %{data: project_json(project, true)})
    end
  end

  def create(conn, params) do
    user_id = user_id(conn)

    case Projects.create_project(params, user_id) do
      {:ok, project} ->
        conn
        |> put_status(:created)
        |> json(%{data: project_json(project)})

      {:error, changeset} ->
        conn
        |> ErrorResponse.send(
          :unprocessable_entity,
          "validation_failed",
          "Validation failed",
          translate_errors(changeset)
        )
    end
  end

  def update(conn, %{"id" => id} = params) do
    user_id = user_id(conn)

    with %Project{} = project <- Projects.get_project(id, user_id),
         {:ok, updated} <- Projects.update_project(project, params) do
      json(conn, %{data: project_json(updated)})
    else
      nil ->
        ErrorResponse.send(conn, :not_found, "project_not_found", "Project not found")

      {:error, changeset} ->
        ErrorResponse.send(
          conn,
          :unprocessable_entity,
          "validation_failed",
          "Validation failed",
          translate_errors(changeset)
        )
    end
  end

  def delete(conn, %{"id" => id}) do
    user_id = user_id(conn)

    with %Project{} = project <- Projects.get_project(id, user_id),
         {:ok, _} <- Projects.delete_project(project) do
      send_resp(conn, :no_content, "")
    else
      nil -> ErrorResponse.send(conn, :not_found, "project_not_found", "Project not found")
    end
  end

  defp user_id(conn) do
    user = get_session(conn, :current_user) || %{}
    user["provider_uid"] || user[:provider_uid]
  end

  defp project_json(project, include_tasks \\ false) do
    base = %{
      id: project.id,
      name: project.name,
      description: project.description,
      archived: project.archived,
      inserted_at: project.inserted_at,
      updated_at: project.updated_at
    }

    if include_tasks do
      Map.put(base, :tasks, Enum.map(project.tasks || [], &task_json/1))
    else
      base
    end
  end

  defp task_json(task) do
    %{
      id: task.id,
      title: task.title,
      details: task.details,
      status: task.status,
      due_date: task.due_date,
      inserted_at: task.inserted_at,
      updated_at: task.updated_at
    }
  end

  defp translate_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
  end
end
