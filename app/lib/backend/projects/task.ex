defmodule Backend.Projects.Task do
  @moduledoc false

  use Ecto.Schema
  import Ecto.Changeset

  @statuses ~w(todo in_progress done)
  @primary_key {:id, :binary_id, autogenerate: true}

  schema "tasks" do
    field(:title, :string)
    field(:details, :string)
    field(:status, :string, default: "todo")
    field(:due_date, :date)
    field(:user_id, :string)

    belongs_to(:project, Backend.Projects.Project, type: :binary_id)

    timestamps(type: :utc_datetime_usec)
  end

  def create_changeset(task, attrs, user_id, project_id) do
    task
    |> cast(attrs, [:title, :details, :status, :due_date])
    |> put_change(:user_id, user_id)
    |> put_change(:project_id, project_id)
    |> validate_required([:title, :status, :user_id, :project_id])
    |> validate_length(:title, min: 1, max: 160)
    |> validate_inclusion(:status, @statuses)
  end

  def changeset(task, attrs) do
    task
    |> cast(attrs, [:title, :details, :status, :due_date])
    |> validate_required([:title, :status])
    |> validate_length(:title, min: 1, max: 160)
    |> validate_inclusion(:status, @statuses)
  end
end
