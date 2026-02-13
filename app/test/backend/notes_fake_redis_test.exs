defmodule Backend.NotesFakeRedisTest do
  use Backend.DataCase, async: false

  alias Backend.Notes

  setup do
    original = Process.whereis(:redix)

    if original, do: Process.unregister(:redix)

    fake =
      spawn_link(fn ->
        loop(%{})
      end)

    Process.register(fake, :redix)

    on_exit(fn ->
      if Process.alive?(fake), do: Process.exit(fake, :kill)

      if Process.whereis(:redix) == fake do
        Process.unregister(:redix)
      end

      if original && Process.alive?(original) do
        Process.register(original, :redix)
      end
    end)

    :ok
  end

  test "list_notes can return cached values and parse invalid datetimes as nil" do
    user_id = "fake_cache_user_#{System.unique_integer()}"
    key = "notes:#{user_id}:false:50:0:nil"

    payload =
      Jason.encode!([
        %{
          "id" => Ecto.UUID.generate(),
          "title" => "From cache",
          "content" => "cached",
          "user_id" => user_id,
          "archived" => false,
          "inserted_at" => "not-an-iso-datetime",
          "updated_at" => nil
        }
      ])

    assert {:ok, "OK"} = Redix.command(:redix, ["SETEX", key, "300", payload])

    [cached] = Notes.list_notes(user_id)
    assert cached.title == "From cache"
    assert cached.inserted_at == nil
    assert cached.updated_at == nil
  end

  test "falls back to database when cache contains invalid json" do
    user_id = "fake_cache_user_#{System.unique_integer()}"
    key = "notes:#{user_id}:false:50:0:nil"

    assert {:ok, "OK"} = Redix.command(:redix, ["SETEX", key, "300", "{invalid-json"])

    {:ok, db_note} = Notes.create_note(%{title: "DB value"}, user_id)

    [note] = Notes.list_notes(user_id)
    assert note.id == db_note.id
  end

  test "create_note invalidates cached keys for that user" do
    user_id = "fake_cache_user_#{System.unique_integer()}"
    key = "notes:#{user_id}:false:50:0:nil"
    assert {:ok, "OK"} = Redix.command(:redix, ["SETEX", key, "300", "[]"])
    assert {:ok, "[]"} = Redix.command(:redix, ["GET", key])

    assert {:ok, _} = Notes.create_note(%{title: "new note"}, user_id)

    assert {:ok, nil} = Redix.command(:redix, ["GET", key])
  end

  defp loop(state) do
    receive do
      {:"$gen_cast", {:pipeline, commands, {caller, ref}, _timeout}} ->
        {responses, new_state} = run_pipeline(commands, state)
        send(caller, {ref, {:ok, responses}})
        loop(new_state)
    end
  end

  defp run_pipeline(commands, state) do
    Enum.map_reduce(commands, state, fn command, acc ->
      execute(command, acc)
    end)
  end

  defp execute(["GET", key], state), do: {Map.get(state, key), state}

  defp execute(["SETEX", key, _ttl, value], state), do: {"OK", Map.put(state, key, value)}

  defp execute(["KEYS", pattern], state) do
    prefix = String.replace_suffix(pattern, "*", "")

    keys =
      state
      |> Map.keys()
      |> Enum.filter(&String.starts_with?(&1, prefix))

    {keys, state}
  end

  defp execute(["DEL" | keys], state) do
    new_state = Enum.reduce(keys, state, &Map.delete(&2, &1))
    {length(keys), new_state}
  end

  defp execute(_unknown, state), do: {nil, state}
end
