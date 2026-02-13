defmodule Backend.Notes.Note do
  @moduledoc """
  Note schema for demonstrating database operations.

  This is a simple example that shows:
  - Ecto schema definition with UUID primary keys
  - Field validation with changesets
  - User association via OAuth provider UID
  - Soft archiving instead of hard deletes

  ## Example

      iex> changeset = Note.changeset(%Note{}, %{title: "My Note", content: "Hello"})
      iex> changeset.valid?
      true

  ## Fields

  - `id` - UUID primary key (auto-generated)
  - `title` - Note title (required, 1-255 characters)
  - `content` - Note body text (optional, max 10,000 characters)
  - `user_id` - OAuth provider UID of the note owner
  - `archived` - Soft delete flag (default: false)
  - `inserted_at` - Creation timestamp
  - `updated_at` - Last update timestamp
  """

  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{
          id: Ecto.UUID.t() | nil,
          title: String.t() | nil,
          content: String.t() | nil,
          user_id: String.t() | nil,
          archived: boolean(),
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  @primary_key {:id, :binary_id, autogenerate: true}

  schema "notes" do
    field(:title, :string)
    field(:content, :string)
    field(:user_id, :string)
    field(:archived, :boolean, default: false)

    timestamps(type: :utc_datetime_usec)
  end

  @doc """
  Creates a changeset for updating an existing note.

  ## Parameters

  - `note` - The note struct to update
  - `attrs` - Map of attributes to change

  ## Validations

  - `title` - Required, 1-255 characters
  - `content` - Optional, max 10,000 characters
  - `archived` - Optional boolean

  ## Examples

      iex> Note.changeset(%Note{}, %{title: "Valid"})
      %Ecto.Changeset{valid?: true}

      iex> Note.changeset(%Note{}, %{title: ""})
      %Ecto.Changeset{valid?: false}
  """
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(note, attrs) do
    note
    |> cast(attrs, [:title, :content, :archived])
    |> validate_required([:title])
    |> validate_length(:title, min: 1, max: 255)
    |> validate_length(:content, max: 10_000)
  end

  @doc """
  Creates a changeset for creating a new note with user association.

  ## Parameters

  - `note` - A new note struct (typically `%Note{}`)
  - `attrs` - Map of note attributes
  - `user_id` - OAuth provider UID of the note owner

  ## Examples

      iex> Note.create_changeset(%Note{}, %{title: "My Note"}, "google:123")
      %Ecto.Changeset{valid?: true}
  """
  @spec create_changeset(t(), map(), String.t()) :: Ecto.Changeset.t()
  def create_changeset(note, attrs, user_id) do
    note
    |> changeset(attrs)
    |> put_change(:user_id, user_id)
    |> validate_required([:user_id])
  end
end
