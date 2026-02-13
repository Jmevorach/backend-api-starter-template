defmodule BackendWeb.API.ProfileController do
  @moduledoc """
  Profile-focused endpoints for authenticated users.

  These endpoints return frontend-ready account context derived from the
  authenticated session plus lightweight notes summary data.
  """

  use BackendWeb, :controller

  alias Backend.Notes

  action_fallback(BackendWeb.FallbackController)

  @default_recent_limit 5
  @max_recent_limit 20

  @doc """
  Returns normalized profile data for the authenticated user.
  """
  def profile(conn, _params) do
    user = get_current_user(conn)

    json(conn, %{
      data: %{
        id: user_value(user, "provider_uid"),
        email: user_value(user, "email"),
        name: user_value(user, "name"),
        first_name: user_value(user, "first_name"),
        last_name: user_value(user, "last_name"),
        avatar_url: user_value(user, "image"),
        auth_provider: user_value(user, "provider")
      }
    })
  end

  @doc """
  Returns a dashboard summary tailored for frontend bootstrapping.
  """
  def dashboard(conn, params) do
    user = get_current_user(conn)
    user_id = user_value(user, "provider_uid")
    recent_limit = parse_limit(params["recent_limit"])

    active_total = Notes.count_notes(user_id, archived: false)
    archived_total = Notes.count_notes(user_id, archived: true)

    recent_notes =
      Notes.list_notes(user_id,
        archived: false,
        limit: recent_limit,
        offset: 0
      )

    json(conn, %{
      data: %{
        user: %{
          id: user_value(user, "provider_uid"),
          name: user_value(user, "name"),
          email: user_value(user, "email")
        },
        summary: %{
          active_notes: active_total,
          archived_notes: archived_total,
          recent_notes: Enum.map(recent_notes, &note_json/1)
        }
      }
    })
  end

  defp get_current_user(conn) do
    case get_session(conn, :current_user) do
      %{} = user -> user
      _ -> raise "User not authenticated"
    end
  end

  defp user_value(user, "provider_uid"), do: user["provider_uid"] || user[:provider_uid]
  defp user_value(user, "email"), do: user["email"] || user[:email]
  defp user_value(user, "name"), do: user["name"] || user[:name]
  defp user_value(user, "first_name"), do: user["first_name"] || user[:first_name]
  defp user_value(user, "last_name"), do: user["last_name"] || user[:last_name]
  defp user_value(user, "image"), do: user["image"] || user[:image]
  defp user_value(user, "provider"), do: user["provider"] || user[:provider]

  defp parse_limit(nil), do: @default_recent_limit

  defp parse_limit(value) when is_binary(value) do
    case Integer.parse(value) do
      {parsed, _} when parsed > 0 -> min(parsed, @max_recent_limit)
      _ -> @default_recent_limit
    end
  end

  defp parse_limit(_), do: @default_recent_limit

  defp note_json(note) do
    %{
      id: note.id,
      title: note.title,
      content: note.content,
      archived: note.archived,
      inserted_at: note.inserted_at,
      updated_at: note.updated_at
    }
  end
end
