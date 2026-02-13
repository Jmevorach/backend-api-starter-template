defmodule BackendWeb.FallbackControllerTest do
  @moduledoc """
  Tests for the FallbackController.

  These tests verify error handling for common error patterns.
  """

  use ExUnit.Case, async: true

  import Plug.Conn
  import Phoenix.ConnTest

  alias BackendWeb.FallbackController

  @endpoint BackendWeb.Endpoint

  # Build a test connection without database
  defp test_conn do
    build_conn()
    |> put_private(:phoenix_endpoint, @endpoint)
    |> put_req_header("accept", "application/json")
  end

  describe "call/2 with :not_found" do
    test "returns 404 with error message" do
      conn = test_conn()

      result = FallbackController.call(conn, {:error, :not_found})

      assert result.status == 404
      body = json_response(result, 404)
      assert body["error"] == "Resource not found"
    end
  end

  describe "call/2 with :unauthorized" do
    test "returns 401 with error message" do
      conn = test_conn()

      result = FallbackController.call(conn, {:error, :unauthorized})

      assert result.status == 401
      body = json_response(result, 401)
      assert body["error"] == "Authentication required"
    end
  end

  describe "call/2 with :forbidden" do
    test "returns 403 with error message" do
      conn = test_conn()

      result = FallbackController.call(conn, {:error, :forbidden})

      assert result.status == 403
      body = json_response(result, 403)
      assert body["error"] == "Permission denied"
    end
  end

  describe "call/2 with Ecto.Changeset" do
    test "returns 422 with validation errors" do
      conn = test_conn()

      # Create a changeset with errors
      changeset =
        {%{}, %{title: :string, email: :string}}
        |> Ecto.Changeset.cast(%{}, [:title, :email])
        |> Ecto.Changeset.validate_required([:title])
        |> Ecto.Changeset.add_error(:email, "is invalid")

      result = FallbackController.call(conn, {:error, changeset})

      assert result.status == 422
      body = json_response(result, 422)
      assert body["error"] == "Validation failed"
      assert is_map(body["details"])
    end

    test "translates changeset errors with interpolation" do
      conn = test_conn()

      changeset =
        {%{}, %{name: :string}}
        |> Ecto.Changeset.cast(%{name: "ab"}, [:name])
        |> Ecto.Changeset.validate_length(:name, min: 3)

      result = FallbackController.call(conn, {:error, changeset})

      assert result.status == 422
      body = json_response(result, 422)
      # Should have translated the error with count interpolation
      assert body["details"]["name"] != nil
      # The error message should have the count replaced
      [error_msg] = body["details"]["name"]
      assert error_msg =~ "3"
    end

    test "handles multiple field errors" do
      conn = test_conn()

      changeset =
        {%{}, %{title: :string, content: :string, email: :string}}
        |> Ecto.Changeset.cast(%{}, [:title, :content, :email])
        |> Ecto.Changeset.validate_required([:title, :content])
        |> Ecto.Changeset.add_error(:email, "must be valid")

      result = FallbackController.call(conn, {:error, changeset})

      assert result.status == 422
      body = json_response(result, 422)
      assert Map.has_key?(body["details"], "title")
      assert Map.has_key?(body["details"], "content")
      assert Map.has_key?(body["details"], "email")
    end

    test "handles nested changeset errors" do
      conn = test_conn()

      changeset =
        {%{}, %{name: :string}}
        |> Ecto.Changeset.cast(%{}, [:name])
        |> Ecto.Changeset.add_error(:name, "can't be blank")
        |> Ecto.Changeset.add_error(:name, "is too short")

      result = FallbackController.call(conn, {:error, changeset})

      assert result.status == 422
      body = json_response(result, 422)
      # Should have multiple errors for the same field
      assert length(body["details"]["name"]) == 2
    end
  end
end
