defmodule Backend.Projects.Project do
  @moduledoc false

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}

  schema "projects" do
    field(:name, :string)
    field(:description, :string)
    field(:user_id, :string)
    field(:archived, :boolean, default: false)

    has_many(:tasks, Backend.Projects.Task)

    timestamps(type: :utc_datetime_usec)
  end

  def create_changeset(project, attrs, user_id) do
    project
    |> cast(attrs, [:name, :description, :archived])
    |> put_change(:user_id, user_id)
    |> validate_required([:name, :user_id])
    |> validate_length(:name, min: 1, max: 120)
  end

  def changeset(project, attrs) do
    project
    |> cast(attrs, [:name, :description, :archived])
    |> validate_required([:name])
    |> validate_length(:name, min: 1, max: 120)
  end
end
