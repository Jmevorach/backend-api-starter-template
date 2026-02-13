defmodule Backend.Repo.Migrations.CreateProjectsAndTasks do
  use Ecto.Migration

  def change do
    create table(:projects, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :description, :text
      add :user_id, :string, null: false
      add :archived, :boolean, default: false, null: false

      timestamps(type: :utc_datetime_usec)
    end

    create index(:projects, [:user_id])
    create index(:projects, [:user_id, :archived])

    create table(:tasks, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :title, :string, null: false
      add :details, :text
      add :status, :string, null: false, default: "todo"
      add :due_date, :date
      add :project_id, references(:projects, type: :binary_id, on_delete: :delete_all), null: false
      add :user_id, :string, null: false

      timestamps(type: :utc_datetime_usec)
    end

    create index(:tasks, [:project_id])
    create index(:tasks, [:user_id])
    create index(:tasks, [:user_id, :status])
  end
end
