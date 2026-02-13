defmodule BackendWeb.FallbackController do
  @moduledoc """
  Fallback controller for handling errors from action_fallback.

  This controller handles common error patterns returned by controllers:
  - `{:error, %Ecto.Changeset{}}` - Validation errors
  - `{:error, :not_found}` - Resource not found
  - `{:error, :unauthorized}` - Authentication required
  - `{:error, :forbidden}` - Permission denied
  """

  use BackendWeb, :controller

  @doc """
  Handles error tuples returned by controller actions.

  ## Supported error patterns

  - `{:error, %Ecto.Changeset{}}` - Returns 422 with validation errors
  - `{:error, :not_found}` - Returns 404
  - `{:error, :unauthorized}` - Returns 401
  - `{:error, :forbidden}` - Returns 403
  """
  def call(conn, {:error, %Ecto.Changeset{} = changeset}) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{
      error: "Validation failed",
      details: translate_errors(changeset)
    })
  end

  def call(conn, {:error, :not_found}) do
    conn
    |> put_status(:not_found)
    |> json(%{error: "Resource not found"})
  end

  def call(conn, {:error, :unauthorized}) do
    conn
    |> put_status(:unauthorized)
    |> json(%{error: "Authentication required"})
  end

  def call(conn, {:error, :forbidden}) do
    conn
    |> put_status(:forbidden)
    |> json(%{error: "Permission denied"})
  end

  defp translate_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
  end
end
