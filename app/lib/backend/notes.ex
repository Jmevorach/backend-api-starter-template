defmodule Backend.Notes do
  @moduledoc """
  Notes context for managing notes.

  This context demonstrates:
  - Phoenix context pattern (business logic separation)
  - Database operations with Ecto (CRUD)
  - Caching with Valkey/Redis
  - Graceful degradation when cache is unavailable
  - Query optimization (filtering, pagination)

  ## Usage

      # List notes for a user
      Notes.list_notes("user123")

      # List with filters
      Notes.list_notes("user123", archived: true, limit: 10)

      # Get a single note
      Notes.get_note("uuid", "user123")

      # Create a note
      Notes.create_note(%{title: "Hello"}, "user123")

      # Update a note
      Notes.update_note(note, %{title: "Updated"})

      # Delete a note
      Notes.delete_note(note)

  ## Caching Strategy

  Notes are cached per-user with a 5-minute TTL. Cache is invalidated on any
  write operation (create, update, delete). If Valkey is unavailable, the
  system gracefully falls back to database queries.
  """

  import Ecto.Query, warn: false
  alias Backend.Notes.Note
  alias Backend.Repo

  require Logger

  # Cache configuration
  @cache_ttl 300
  @cache_prefix "notes"

  # Pagination defaults
  @default_limit 50
  @max_limit 100

  @doc """
  Lists notes for a user with optional filtering and pagination.

  ## Parameters

  - `user_id` - OAuth provider UID of the note owner
  - `opts` - Keyword list of options:
    - `:archived` - Filter by archived status (default: false)
    - `:limit` - Maximum number of results (default: 50, max: 100)
    - `:offset` - Number of results to skip (default: 0)
    - `:search` - Search term for title (optional)

  ## Returns

  List of `%Note{}` structs ordered by creation date (newest first).

  ## Examples

      iex> Notes.list_notes("user123")
      [%Note{}, ...]

      iex> Notes.list_notes("user123", archived: true, limit: 10)
      [%Note{}, ...]

      iex> Notes.list_notes("user123", search: "hello")
      [%Note{title: "hello world"}, ...]
  """
  @spec list_notes(String.t(), keyword()) :: [Note.t()]
  def list_notes(user_id, opts \\ []) do
    archived = Keyword.get(opts, :archived, false)
    limit = opts |> Keyword.get(:limit, @default_limit) |> min(@max_limit)
    offset = Keyword.get(opts, :offset, 0)
    search = Keyword.get(opts, :search)

    cache_key = build_cache_key(user_id, archived, limit, offset, search)

    case get_from_cache(cache_key) do
      {:ok, notes} ->
        Logger.debug("Cache hit for #{cache_key}")
        notes

      :miss ->
        Logger.debug("Cache miss for #{cache_key}")

        notes =
          Note
          |> where([n], n.user_id == ^user_id)
          |> where([n], n.archived == ^archived)
          |> maybe_search(search)
          |> order_by([n], desc: n.inserted_at)
          |> limit(^limit)
          |> offset(^offset)
          |> Repo.all()

        put_in_cache(cache_key, notes)
        notes
    end
  end

  @doc """
  Returns the count of notes for a user.

  ## Parameters

  - `user_id` - OAuth provider UID of the note owner
  - `opts` - Keyword list of options:
    - `:archived` - Filter by archived status (default: false)

  ## Examples

      iex> Notes.count_notes("user123")
      42

      iex> Notes.count_notes("user123", archived: true)
      5
  """
  @spec count_notes(String.t(), keyword()) :: non_neg_integer()
  def count_notes(user_id, opts \\ []) do
    archived = Keyword.get(opts, :archived, false)

    Note
    |> where([n], n.user_id == ^user_id)
    |> where([n], n.archived == ^archived)
    |> Repo.aggregate(:count, :id)
  end

  @doc """
  Gets a single note by ID and user.

  Returns `nil` if the note doesn't exist or belongs to another user.

  ## Parameters

  - `id` - Note UUID
  - `user_id` - OAuth provider UID (for authorization)

  ## Examples

      iex> Notes.get_note("valid-uuid", "user123")
      %Note{}

      iex> Notes.get_note("invalid-uuid", "user123")
      nil

      iex> Notes.get_note("other-users-note", "user123")
      nil
  """
  @spec get_note(String.t(), String.t()) :: Note.t() | nil
  def get_note(id, user_id) do
    Note
    |> where([n], n.id == ^id and n.user_id == ^user_id)
    |> Repo.one()
  end

  @doc """
  Gets a single note, raising if not found.

  ## Raises

  - `Ecto.NoResultsError` if note not found or belongs to another user

  ## Examples

      iex> Notes.get_note!("valid-uuid", "user123")
      %Note{}

      iex> Notes.get_note!("invalid-uuid", "user123")
      ** (Ecto.NoResultsError)
  """
  @spec get_note!(String.t(), String.t()) :: Note.t()
  def get_note!(id, user_id) do
    Note
    |> where([n], n.id == ^id and n.user_id == ^user_id)
    |> Repo.one!()
  end

  @doc """
  Creates a note for a user.

  ## Parameters

  - `attrs` - Map of note attributes (`:title`, `:content`)
  - `user_id` - OAuth provider UID of the note owner

  ## Returns

  - `{:ok, %Note{}}` on success
  - `{:error, %Ecto.Changeset{}}` on validation failure

  ## Examples

      iex> Notes.create_note(%{title: "Hello"}, "user123")
      {:ok, %Note{title: "Hello"}}

      iex> Notes.create_note(%{title: ""}, "user123")
      {:error, %Ecto.Changeset{}}
  """
  @spec create_note(map(), String.t()) :: {:ok, Note.t()} | {:error, Ecto.Changeset.t()}
  def create_note(attrs, user_id) do
    %Note{}
    |> Note.create_changeset(attrs, user_id)
    |> Repo.insert()
    |> tap_ok(fn _note ->
      invalidate_user_cache(user_id)
      Logger.info("Created note for user #{user_id}")
    end)
  end

  @doc """
  Updates a note.

  ## Parameters

  - `note` - The note to update
  - `attrs` - Map of attributes to change

  ## Returns

  - `{:ok, %Note{}}` on success
  - `{:error, %Ecto.Changeset{}}` on validation failure

  ## Examples

      iex> Notes.update_note(note, %{title: "Updated"})
      {:ok, %Note{title: "Updated"}}
  """
  @spec update_note(Note.t(), map()) :: {:ok, Note.t()} | {:error, Ecto.Changeset.t()}
  def update_note(%Note{} = note, attrs) do
    note
    |> Note.changeset(attrs)
    |> Repo.update()
    |> tap_ok(fn _note ->
      invalidate_user_cache(note.user_id)
      Logger.info("Updated note #{note.id}")
    end)
  end

  @doc """
  Archives a note (soft delete).

  ## Examples

      iex> Notes.archive_note(note)
      {:ok, %Note{archived: true}}
  """
  @spec archive_note(Note.t()) :: {:ok, Note.t()} | {:error, Ecto.Changeset.t()}
  def archive_note(%Note{} = note) do
    update_note(note, %{archived: true})
  end

  @doc """
  Unarchives a note.

  ## Examples

      iex> Notes.unarchive_note(note)
      {:ok, %Note{archived: false}}
  """
  @spec unarchive_note(Note.t()) :: {:ok, Note.t()} | {:error, Ecto.Changeset.t()}
  def unarchive_note(%Note{} = note) do
    update_note(note, %{archived: false})
  end

  @doc """
  Deletes a note permanently.

  ## Parameters

  - `note` - The note to delete

  ## Returns

  - `{:ok, %Note{}}` on success
  - `{:error, %Ecto.Changeset{}}` on failure

  ## Examples

      iex> Notes.delete_note(note)
      {:ok, %Note{}}
  """
  @spec delete_note(Note.t()) :: {:ok, Note.t()} | {:error, Ecto.Changeset.t()}
  def delete_note(%Note{} = note) do
    user_id = note.user_id

    Repo.delete(note)
    |> tap_ok(fn _note ->
      invalidate_user_cache(user_id)
      Logger.info("Deleted note #{note.id}")
    end)
  end

  # ---------------------------------------------------------------------------
  # Private Functions
  # ---------------------------------------------------------------------------

  defp maybe_search(query, nil), do: query
  defp maybe_search(query, ""), do: query

  defp maybe_search(query, search) do
    search_term = "%#{search}%"
    where(query, [n], ilike(n.title, ^search_term) or ilike(n.content, ^search_term))
  end

  defp build_cache_key(user_id, archived, limit, offset, search) do
    search_hash = if search, do: :erlang.phash2(search), else: "nil"
    "#{@cache_prefix}:#{user_id}:#{archived}:#{limit}:#{offset}:#{search_hash}"
  end

  defp get_from_cache(key) do
    case Redix.command(:redix, ["GET", key]) do
      {:ok, nil} ->
        :miss

      {:ok, value} ->
        case Jason.decode(value) do
          {:ok, data} -> {:ok, decode_notes(data)}
          _ -> :miss
        end

      {:error, reason} ->
        Logger.warning("Cache read failed: #{inspect(reason)}")
        :miss
    end
  rescue
    error ->
      Logger.warning("Cache error: #{inspect(error)}")
      :miss
  catch
    :exit, reason ->
      Logger.debug("Cache unavailable: #{inspect(reason)}")
      :miss
  end

  defp put_in_cache(key, notes) do
    case Jason.encode(encode_notes(notes)) do
      {:ok, json} ->
        Redix.command(:redix, ["SETEX", key, @cache_ttl, json])

      {:error, reason} ->
        Logger.warning("Cache encode failed: #{inspect(reason)}")
    end
  rescue
    error ->
      Logger.warning("Cache write error: #{inspect(error)}")
      :ok
  catch
    :exit, reason ->
      Logger.debug("Cache unavailable for write: #{inspect(reason)}")
      :ok
  end

  defp invalidate_user_cache(user_id) do
    pattern = "#{@cache_prefix}:#{user_id}:*"

    case Redix.command(:redix, ["KEYS", pattern]) do
      {:ok, keys} when is_list(keys) and keys != [] ->
        Redix.command(:redix, ["DEL" | keys])

      _ ->
        :ok
    end
  rescue
    error ->
      Logger.warning("Cache invalidation error: #{inspect(error)}")
      :ok
  catch
    :exit, reason ->
      Logger.debug("Cache unavailable for invalidation: #{inspect(reason)}")
      :ok
  end

  # Encode notes for JSON serialization
  defp encode_notes(notes) do
    Enum.map(notes, fn note ->
      %{
        "id" => note.id,
        "title" => note.title,
        "content" => note.content,
        "user_id" => note.user_id,
        "archived" => note.archived,
        "inserted_at" => DateTime.to_iso8601(note.inserted_at),
        "updated_at" => DateTime.to_iso8601(note.updated_at)
      }
    end)
  end

  # Decode notes from JSON
  defp decode_notes(data) do
    Enum.map(data, fn note ->
      %Note{
        id: note["id"],
        title: note["title"],
        content: note["content"],
        user_id: note["user_id"],
        archived: note["archived"],
        inserted_at: parse_datetime(note["inserted_at"]),
        updated_at: parse_datetime(note["updated_at"])
      }
    end)
  end

  defp parse_datetime(nil), do: nil

  defp parse_datetime(str) do
    case DateTime.from_iso8601(str) do
      {:ok, dt, _} -> dt
      _ -> nil
    end
  end

  defp tap_ok({:ok, value} = result, fun) do
    fun.(value)
    result
  end

  defp tap_ok(error, _fun), do: error
end
