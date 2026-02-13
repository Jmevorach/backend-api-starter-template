defmodule BackendWeb.API.TasksController do
  use BackendWeb, :controller

  alias Backend.Projects
  alias Backend.Projects.Task
  alias BackendWeb.ErrorResponse

  action_fallback(BackendWeb.FallbackController)

  def index(conn, params) do
    user_id = user_id(conn)

    tasks =
      Projects.list_tasks(user_id, status: params["status"], project_id: params["project_id"])

    json(conn, %{data: Enum.map(tasks, &task_json/1)})
  end

  def show(conn, %{"id" => id}) do
    user_id = user_id(conn)

    case Projects.get_task(id, user_id) do
      nil -> ErrorResponse.send(conn, :not_found, "task_not_found", "Task not found")
      task -> json(conn, %{data: task_json(task)})
    end
  end

  def create(conn, %{"project_id" => project_id} = params) do
    user_id = user_id(conn)

    case Projects.create_task(project_id, params, user_id) do
      {:ok, task} ->
        conn
        |> put_status(:created)
        |> json(%{data: task_json(task)})

      {:error, :project_not_found} ->
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

  def create(conn, _params) do
    ErrorResponse.send(conn, :bad_request, "invalid_request", "project_id is required")
  end

  def update(conn, %{"id" => id} = params) do
    user_id = user_id(conn)

    with %Task{} = task <- Projects.get_task(id, user_id),
         {:ok, updated} <- Projects.update_task(task, params) do
      json(conn, %{data: task_json(updated)})
    else
      nil ->
        ErrorResponse.send(conn, :not_found, "task_not_found", "Task not found")

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

    with %Task{} = task <- Projects.get_task(id, user_id),
         {:ok, _} <- Projects.delete_task(task) do
      send_resp(conn, :no_content, "")
    else
      nil ->
        ErrorResponse.send(conn, :not_found, "task_not_found", "Task not found")
    end
  end

  defp user_id(conn) do
    user = get_session(conn, :current_user) || %{}
    user["provider_uid"] || user[:provider_uid]
  end

  defp task_json(task) do
    %{
      id: task.id,
      project_id: task.project_id,
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
