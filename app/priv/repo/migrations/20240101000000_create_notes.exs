defmodule Backend.Repo.Migrations.CreateNotes do
  @moduledoc """
  Creates the notes table for demonstrating database operations.

  This migration shows:
  - UUID primary keys (better for distributed systems)
  - Proper indexing strategies
  - Timestamp handling with microsecond precision
  - NOT NULL constraints for required fields
  """

  use Ecto.Migration

  def change do
    create table(:notes, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :title, :string, null: false
      add :content, :text
      add :user_id, :string, null: false
      add :archived, :boolean, default: false, null: false

      timestamps(type: :utc_datetime_usec)
    end

    # Index for user lookups (most common query pattern)
    create index(:notes, [:user_id])

    # Compound index for user + archived status (common filter)
    create index(:notes, [:user_id, :archived])

    # Index for sorting by creation date
    create index(:notes, [:inserted_at])
  end
end
