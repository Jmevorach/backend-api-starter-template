defmodule BackendWeb.API.UploadsControllerTest do
  @moduledoc """
  Tests for the uploads API controller.

  These tests verify the HTTP API for file upload management including:
  - Presigned URL generation
  - File listing
  - File metadata retrieval
  - File deletion
  - Authentication and authorization

  Note: These tests mock the S3 operations to test controller logic without
  requiring actual AWS credentials.
  """

  # async: false because tests manipulate global environment variables
  use ExUnit.Case, async: false

  import Phoenix.ConnTest

  @endpoint BackendWeb.Endpoint

  # Test user data
  @test_user %{
    id: "test_user_123",
    email: "test@example.com",
    name: "Test User"
  }

  describe "presign endpoint" do
    test "returns 400 when filename is missing" do
      conn =
        build_conn()
        |> init_test_session(%{current_user: @test_user})
        |> post("/api/uploads/presign", %{"content_type" => "image/jpeg"})

      assert json_response(conn, 400)["error"] == "invalid_request"
    end

    test "returns 400 when content_type is missing" do
      conn =
        build_conn()
        |> init_test_session(%{current_user: @test_user})
        |> post("/api/uploads/presign", %{"filename" => "photo.jpg"})

      assert json_response(conn, 400)["error"] == "invalid_request"
    end

    test "returns 400 for invalid content type" do
      conn =
        build_conn()
        |> init_test_session(%{current_user: @test_user})
        |> post("/api/uploads/presign", %{
          "filename" => "malware.exe",
          "content_type" => "application/x-executable"
        })

      response = json_response(conn, 400)
      assert response["error"] == "invalid_content_type"
      assert is_list(response["allowed_types"])
    end

    test "returns 503 when S3 not configured" do
      # Ensure S3 is not configured
      original_bucket = System.get_env("UPLOADS_BUCKET")
      System.delete_env("UPLOADS_BUCKET")

      try do
        conn =
          build_conn()
          |> init_test_session(%{current_user: @test_user})
          |> post("/api/uploads/presign", %{
            "filename" => "photo.jpg",
            "content_type" => "image/jpeg"
          })

        assert json_response(conn, 503)["error"] == "service_unavailable"
      after
        if original_bucket, do: System.put_env("UPLOADS_BUCKET", original_bucket)
      end
    end
  end

  describe "index endpoint" do
    test "returns 503 when S3 not configured" do
      original_bucket = System.get_env("UPLOADS_BUCKET")
      System.delete_env("UPLOADS_BUCKET")

      try do
        conn =
          build_conn()
          |> init_test_session(%{current_user: @test_user})
          |> get("/api/uploads")

        assert json_response(conn, 503)["error"] == "service_unavailable"
      after
        if original_bucket, do: System.put_env("UPLOADS_BUCKET", original_bucket)
      end
    end
  end

  describe "show endpoint" do
    test "returns 403 for key belonging to different user" do
      # The user_id from @test_user is "test_user_123"
      # This key belongs to a different user
      conn =
        build_conn()
        |> init_test_session(%{current_user: @test_user})
        |> get("/api/uploads/users%2Fother_user%2Fuploads%2Ffile.jpg")

      assert json_response(conn, 403)["error"] == "forbidden"
    end

    test "returns 503 when S3 not configured for valid user key" do
      original_bucket = System.get_env("UPLOADS_BUCKET")
      System.delete_env("UPLOADS_BUCKET")

      try do
        # Use a key that belongs to the test user
        conn =
          build_conn()
          |> init_test_session(%{current_user: @test_user})
          |> get("/api/uploads/users%2Ftest_user_123%2Fuploads%2Ffile.jpg")

        assert json_response(conn, 503)["error"] == "service_unavailable"
      after
        if original_bucket, do: System.put_env("UPLOADS_BUCKET", original_bucket)
      end
    end
  end

  describe "download endpoint" do
    test "returns 403 for key belonging to different user" do
      conn =
        build_conn()
        |> init_test_session(%{current_user: @test_user})
        |> get("/api/uploads/users%2Fother_user%2Fuploads%2Ffile.jpg/download")

      assert json_response(conn, 403)["error"] == "forbidden"
    end

    test "returns 503 when S3 not configured for valid user key" do
      original_bucket = System.get_env("UPLOADS_BUCKET")
      System.delete_env("UPLOADS_BUCKET")

      try do
        conn =
          build_conn()
          |> init_test_session(%{current_user: @test_user})
          |> get("/api/uploads/users%2Ftest_user_123%2Fuploads%2Ffile.jpg/download")

        assert json_response(conn, 503)["error"] == "service_unavailable"
      after
        if original_bucket, do: System.put_env("UPLOADS_BUCKET", original_bucket)
      end
    end
  end

  describe "delete endpoint" do
    test "returns 403 for key belonging to different user" do
      conn =
        build_conn()
        |> init_test_session(%{current_user: @test_user})
        |> delete("/api/uploads/users%2Fother_user%2Fuploads%2Ffile.jpg")

      assert json_response(conn, 403)["error"] == "forbidden"
    end

    test "returns 503 when S3 not configured for valid user key" do
      original_bucket = System.get_env("UPLOADS_BUCKET")
      System.delete_env("UPLOADS_BUCKET")

      try do
        conn =
          build_conn()
          |> init_test_session(%{current_user: @test_user})
          |> delete("/api/uploads/users%2Ftest_user_123%2Fuploads%2Ffile.jpg")

        assert json_response(conn, 503)["error"] == "service_unavailable"
      after
        if original_bucket, do: System.put_env("UPLOADS_BUCKET", original_bucket)
      end
    end
  end

  describe "allowed_types endpoint" do
    test "returns list of allowed content types" do
      conn =
        build_conn()
        |> init_test_session(%{current_user: @test_user})
        |> get("/api/uploads/types")

      response = json_response(conn, 200)
      assert is_list(response["content_types"])
      assert "image/jpeg" in response["content_types"]
      assert "application/pdf" in response["content_types"]
    end
  end

  describe "authentication" do
    test "returns 401 when not authenticated" do
      conn =
        build_conn()
        |> init_test_session(%{})
        |> post("/api/uploads/presign", %{
          "filename" => "photo.jpg",
          "content_type" => "image/jpeg"
        })

      assert json_response(conn, 401)["error"] == "Authentication required"
    end

    test "returns 401 for index when not authenticated" do
      conn =
        build_conn()
        |> init_test_session(%{})
        |> get("/api/uploads")

      assert json_response(conn, 401)["error"] == "Authentication required"
    end
  end
end
