defmodule Backend.LoggerJSON do
  @moduledoc """
  JSON formatter for structured logging.

  This module provides a custom log formatter that outputs logs in JSON format,
  making them easier to parse by log aggregation tools like CloudWatch, ELK,
  or Datadog.

  ## Configuration

  In `config/prod.exs`:

      config :logger, :console,
        format: {Backend.LoggerJSON, :format},
        metadata: [:request_id, :user_id, :trace_id]

  ## Output Format

      {
        "time": "2024-01-01T00:00:00.000Z",
        "level": "info",
        "message": "GET /healthz",
        "metadata": {
          "request_id": "abc123",
          "duration_ms": 1.5
        }
      }

  ## Adding Context

  Use Logger metadata to add context to logs:

      Logger.metadata(user_id: "user123", trace_id: "trace456")
      Logger.info("User logged in")

  This produces:

      {
        "message": "User logged in",
        "metadata": {
          "user_id": "user123",
          "trace_id": "trace456"
        }
      }
  """

  @doc """
  Formats a log message as JSON.
  """
  @typep timestamp ::
           {{year :: integer, month :: integer, day :: integer},
            {hour :: integer, minute :: integer, second :: integer, millisecond :: integer}}

  @spec format(Logger.level(), Logger.message(), timestamp(), keyword()) ::
          IO.chardata()
  def format(level, message, timestamp, metadata) do
    json =
      %{
        time: format_timestamp(timestamp),
        level: level,
        message: to_string(message)
      }
      |> add_metadata(metadata)
      |> Jason.encode!()

    [json, "\n"]
  rescue
    _ ->
      # Fallback to simple format if JSON encoding fails
      "#{format_timestamp(timestamp)} [#{level}] #{message}\n"
  end

  defp format_timestamp({date, {hour, minute, second, microsecond}}) do
    {year, month, day} = date

    NaiveDateTime.new!(year, month, day, hour, minute, second, microsecond * 1000)
    |> DateTime.from_naive!("Etc/UTC")
    |> DateTime.to_iso8601()
  end

  defp add_metadata(json, metadata) do
    filtered =
      metadata
      |> Keyword.drop([:gl, :domain, :erl_level, :mfa, :file, :line])
      |> Enum.into(%{})

    if map_size(filtered) > 0 do
      Map.put(json, :metadata, filtered)
    else
      json
    end
  end
end
