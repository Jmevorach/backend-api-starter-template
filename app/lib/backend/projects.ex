defmodule Backend.Projects do
  @moduledoc """
  Canonical example context for a parent/child domain model.
  """

  import Ecto.Query, warn: false

  alias Backend.Projects.Project
  alias Backend.Projects.Task
  alias Backend.Repo

  def list_projects(user_id) do
    Project
    |> where([p], p.user_id == ^user_id)
    |> order_by([p], asc: p.inserted_at)
    |> Repo.all()
  end

  def get_project(id, user_id) do
    Project
    |> where([p], p.id == ^id and p.user_id == ^user_id)
    |> Repo.one()
    |> Repo.preload(:tasks)
  end

  def create_project(attrs, user_id) do
    %Project{}
    |> Project.create_changeset(attrs, user_id)
    |> Repo.insert()
  end

  def update_project(%Project{} = project, attrs) do
    project
    |> Project.changeset(attrs)
    |> Repo.update()
  end

  def delete_project(%Project{} = project), do: Repo.delete(project)

  def list_tasks(user_id, opts \\ []) do
    status = Keyword.get(opts, :status)
    project_id = Keyword.get(opts, :project_id)

    Task
    |> where([t], t.user_id == ^user_id)
    |> maybe_filter_status(status)
    |> maybe_filter_project(project_id)
    |> order_by([t], asc: t.inserted_at)
    |> Repo.all()
  end

  def get_task(id, user_id) do
    Task
    |> where([t], t.id == ^id and t.user_id == ^user_id)
    |> Repo.one()
  end

  def create_task(project_id, attrs, user_id) do
    case get_project(project_id, user_id) do
      %Project{} ->
        %Task{}
        |> Task.create_changeset(attrs, user_id, project_id)
        |> Repo.insert()

      _ ->
        {:error, :project_not_found}
    end
  end

  def update_task(%Task{} = task, attrs) do
    task
    |> Task.changeset(attrs)
    |> Repo.update()
  end

  def delete_task(%Task{} = task), do: Repo.delete(task)

  defp maybe_filter_status(query, nil), do: query
  defp maybe_filter_status(query, ""), do: query
  defp maybe_filter_status(query, status), do: where(query, [t], t.status == ^status)

  defp maybe_filter_project(query, nil), do: query
  defp maybe_filter_project(query, ""), do: query
  defp maybe_filter_project(query, project_id), do: where(query, [t], t.project_id == ^project_id)
end
