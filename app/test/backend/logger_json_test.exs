defmodule Backend.LoggerJSONTest do
  @moduledoc """
  Tests for the JSON log formatter module.

  These tests verify:
  - JSON output format
  - Timestamp formatting
  - Metadata handling
  - Error recovery
  """

  use ExUnit.Case, async: true

  alias Backend.LoggerJSON

  describe "format/4" do
    test "formats basic log message as JSON" do
      timestamp = {{2024, 1, 15}, {10, 30, 45, 123}}
      metadata = []

      result = LoggerJSON.format(:info, "Test message", timestamp, metadata)
      json = result |> IO.iodata_to_binary() |> String.trim() |> Jason.decode!()

      assert json["level"] == "info"
      assert json["message"] == "Test message"
      assert json["time"] == "2024-01-15T10:30:45.123000Z"
    end

    test "formats different log levels" do
      timestamp = {{2024, 1, 1}, {0, 0, 0, 0}}

      for level <- [:debug, :info, :warning, :error] do
        result = LoggerJSON.format(level, "msg", timestamp, [])
        json = result |> IO.iodata_to_binary() |> String.trim() |> Jason.decode!()

        assert json["level"] == Atom.to_string(level)
      end
    end

    test "includes metadata when provided" do
      timestamp = {{2024, 1, 1}, {0, 0, 0, 0}}
      metadata = [request_id: "abc123", user_id: "user456", trace_id: "trace789"]

      result = LoggerJSON.format(:info, "Test", timestamp, metadata)
      json = result |> IO.iodata_to_binary() |> String.trim() |> Jason.decode!()

      assert json["metadata"]["request_id"] == "abc123"
      assert json["metadata"]["user_id"] == "user456"
      assert json["metadata"]["trace_id"] == "trace789"
    end

    test "filters out internal Erlang metadata" do
      timestamp = {{2024, 1, 1}, {0, 0, 0, 0}}

      metadata = [
        gl: self(),
        domain: [:elixir],
        erl_level: :info,
        mfa: {__MODULE__, :test, 0},
        file: "test.exs",
        line: 1,
        # This should be kept
        custom_key: "custom_value"
      ]

      result = LoggerJSON.format(:info, "Test", timestamp, metadata)
      json = result |> IO.iodata_to_binary() |> String.trim() |> Jason.decode!()

      # Internal metadata should be filtered
      refute Map.has_key?(json["metadata"], "gl")
      refute Map.has_key?(json["metadata"], "domain")
      refute Map.has_key?(json["metadata"], "erl_level")
      refute Map.has_key?(json["metadata"], "mfa")
      refute Map.has_key?(json["metadata"], "file")
      refute Map.has_key?(json["metadata"], "line")

      # Custom metadata should be kept
      assert json["metadata"]["custom_key"] == "custom_value"
    end

    test "omits metadata key when no user metadata" do
      timestamp = {{2024, 1, 1}, {0, 0, 0, 0}}
      metadata = [gl: self(), domain: [:elixir]]

      result = LoggerJSON.format(:info, "Test", timestamp, metadata)
      json = result |> IO.iodata_to_binary() |> String.trim() |> Jason.decode!()

      refute Map.has_key?(json, "metadata")
    end

    test "handles iodata messages" do
      timestamp = {{2024, 1, 1}, {0, 0, 0, 0}}
      # iodata can be a list of strings/chars
      message = ["Hello", ?\s, "World"]

      result = LoggerJSON.format(:info, message, timestamp, [])
      json = result |> IO.iodata_to_binary() |> String.trim() |> Jason.decode!()

      assert json["message"] == "Hello World"
    end

    test "handles unicode in messages" do
      timestamp = {{2024, 1, 1}, {0, 0, 0, 0}}

      result = LoggerJSON.format(:info, "日本語 🎉 émojis", timestamp, [])
      json = result |> IO.iodata_to_binary() |> String.trim() |> Jason.decode!()

      assert json["message"] == "日本語 🎉 émojis"
    end

    test "handles unicode in metadata" do
      timestamp = {{2024, 1, 1}, {0, 0, 0, 0}}
      metadata = [name: "José García", emoji: "🚀"]

      result = LoggerJSON.format(:info, "Test", timestamp, metadata)
      json = result |> IO.iodata_to_binary() |> String.trim() |> Jason.decode!()

      assert json["metadata"]["name"] == "José García"
      assert json["metadata"]["emoji"] == "🚀"
    end

    test "appends newline to output" do
      timestamp = {{2024, 1, 1}, {0, 0, 0, 0}}

      result = LoggerJSON.format(:info, "Test", timestamp, [])
      output = IO.iodata_to_binary(result)

      assert String.ends_with?(output, "\n")
    end

    test "handles metadata with various value types" do
      timestamp = {{2024, 1, 1}, {0, 0, 0, 0}}

      metadata = [
        string_val: "hello",
        int_val: 42,
        float_val: 3.14,
        bool_val: true,
        nil_val: nil,
        atom_val: :test
      ]

      result = LoggerJSON.format(:info, "Test", timestamp, metadata)
      json = result |> IO.iodata_to_binary() |> String.trim() |> Jason.decode!()

      assert json["metadata"]["string_val"] == "hello"
      assert json["metadata"]["int_val"] == 42
      assert json["metadata"]["float_val"] == 3.14
      assert json["metadata"]["bool_val"] == true
      assert json["metadata"]["nil_val"] == nil
      assert json["metadata"]["atom_val"] == "test"
    end
  end

  describe "timestamp formatting" do
    test "formats timestamp with zero milliseconds" do
      timestamp = {{2024, 12, 31}, {23, 59, 59, 0}}

      result = LoggerJSON.format(:info, "Test", timestamp, [])
      json = result |> IO.iodata_to_binary() |> String.trim() |> Jason.decode!()

      assert json["time"] == "2024-12-31T23:59:59.000000Z"
    end

    test "formats timestamp with max milliseconds" do
      timestamp = {{2024, 1, 1}, {0, 0, 0, 999}}

      result = LoggerJSON.format(:info, "Test", timestamp, [])
      json = result |> IO.iodata_to_binary() |> String.trim() |> Jason.decode!()

      assert json["time"] == "2024-01-01T00:00:00.999000Z"
    end

    test "formats single digit date components" do
      timestamp = {{2024, 1, 5}, {3, 7, 9, 1}}

      result = LoggerJSON.format(:info, "Test", timestamp, [])
      json = result |> IO.iodata_to_binary() |> String.trim() |> Jason.decode!()

      # ISO8601 format should zero-pad single digits
      assert json["time"] == "2024-01-05T03:07:09.001000Z"
    end
  end

  describe "empty message handling" do
    test "handles empty string message" do
      timestamp = {{2024, 1, 1}, {0, 0, 0, 0}}

      result = LoggerJSON.format(:info, "", timestamp, [])
      json = result |> IO.iodata_to_binary() |> String.trim() |> Jason.decode!()

      assert json["message"] == ""
    end

    test "handles empty iodata message" do
      timestamp = {{2024, 1, 1}, {0, 0, 0, 0}}

      result = LoggerJSON.format(:info, [], timestamp, [])
      json = result |> IO.iodata_to_binary() |> String.trim() |> Jason.decode!()

      assert json["message"] == ""
    end
  end
end
