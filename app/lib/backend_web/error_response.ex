defmodule BackendWeb.ErrorResponse do
  @moduledoc """
  Centralized JSON error rendering for API responses.
  """

  import Phoenix.Controller, only: [json: 2]
  import Plug.Conn, only: [get_resp_header: 2, put_status: 2]

  @spec send(Plug.Conn.t(), Plug.Conn.status(), String.t(), String.t(), map() | nil, keyword()) ::
          Plug.Conn.t()
  def send(conn, status, code, message, details \\ nil, opts \\ []) do
    request_id = request_id(conn)
    legacy_error = Keyword.get(opts, :error, message)

    payload = %{
      error: legacy_error,
      code: code,
      message: message,
      request_id: request_id
    }

    payload =
      if is_map(details) and map_size(details) > 0 do
        Map.put(payload, :details, details)
      else
        payload
      end

    conn
    |> put_status(status)
    |> json(payload)
  end

  defp request_id(conn) do
    case get_resp_header(conn, "x-request-id") do
      [id | _] -> id
      _ -> nil
    end
  end
end
