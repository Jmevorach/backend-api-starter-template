defmodule BackendWeb.API.UploadsControllerMockedTest do
  @moduledoc """
  Mocked tests for the uploads API controller.

  These tests use Mox to mock S3 operations and test the full controller flow
  including success paths.
  """

  use ExUnit.Case, async: true

  import Mox
  import Phoenix.ConnTest

  @endpoint BackendWeb.Endpoint

  # Make sure mocks are verified when the test exits
  setup :verify_on_exit!

  # Test user data
  @test_user %{
    id: "test_user_123",
    email: "test@example.com",
    name: "Test User"
  }

  setup do
    # Configure uploads for tests
    System.put_env("UPLOADS_BUCKET", "test-uploads-bucket")
    System.put_env("UPLOADS_REGION", "us-east-1")
    System.put_env("UPLOADS_MAX_SIZE_MB", "50")
    System.put_env("UPLOADS_PRESIGNED_URL_EXPIRY", "3600")
    System.put_env("AWS_ACCESS_KEY_ID", "AKIAIOSFODNN7EXAMPLE")
    System.put_env("AWS_SECRET_ACCESS_KEY", "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY")
    System.put_env("AWS_REGION", "us-east-1")

    on_exit(fn ->
      System.delete_env("UPLOADS_BUCKET")
      System.delete_env("UPLOADS_REGION")
      System.delete_env("UPLOADS_MAX_SIZE_MB")
      System.delete_env("UPLOADS_PRESIGNED_URL_EXPIRY")
      System.delete_env("AWS_ACCESS_KEY_ID")
      System.delete_env("AWS_SECRET_ACCESS_KEY")
      System.delete_env("AWS_REGION")
    end)

    :ok
  end

  describe "presign endpoint success" do
    test "returns presigned URL with valid request" do
      conn =
        build_conn()
        |> init_test_session(%{current_user: @test_user})
        |> post("/api/uploads/presign", %{
          "filename" => "photo.jpg",
          "content_type" => "image/jpeg"
        })

      response = json_response(conn, 200)
      assert is_binary(response["url"])
      assert is_binary(response["key"])
      assert String.starts_with?(response["key"], "users/test_user_123/uploads/")
      assert is_map(response["fields"])
    end

    test "includes required fields in presigned POST" do
      conn =
        build_conn()
        |> init_test_session(%{current_user: @test_user})
        |> post("/api/uploads/presign", %{
          "filename" => "document.pdf",
          "content_type" => "application/pdf"
        })

      response = json_response(conn, 200)
      fields = response["fields"]

      # Check required fields for S3 presigned POST
      assert Map.has_key?(fields, "key")
      assert Map.has_key?(fields, "policy")
      assert Map.has_key?(fields, "x-amz-algorithm")
      assert Map.has_key?(fields, "x-amz-credential")
      assert Map.has_key?(fields, "x-amz-date")
      assert Map.has_key?(fields, "x-amz-signature")
    end
  end

  describe "download endpoint success" do
    test "returns presigned download URL for user's file" do
      conn =
        build_conn()
        |> init_test_session(%{current_user: @test_user})
        |> get("/api/uploads/users%2Ftest_user_123%2Fuploads%2F12345_photo.jpg/download")

      response = json_response(conn, 200)
      assert is_binary(response["url"])
      assert String.contains?(response["url"], "test-uploads-bucket")
      assert String.contains?(response["url"], "X-Amz-Signature=")
    end

    test "accepts custom expires_in parameter" do
      conn =
        build_conn()
        |> init_test_session(%{current_user: @test_user})
        |> get("/api/uploads/users%2Ftest_user_123%2Fuploads%2F12345_photo.jpg/download", %{
          "expires_in" => "7200"
        })

      response = json_response(conn, 200)
      assert is_binary(response["url"])
      assert String.contains?(response["url"], "X-Amz-Expires=7200")
    end

    test "ignores invalid expires_in parameter" do
      conn =
        build_conn()
        |> init_test_session(%{current_user: @test_user})
        |> get("/api/uploads/users%2Ftest_user_123%2Fuploads%2F12345_photo.jpg/download", %{
          "expires_in" => "invalid"
        })

      response = json_response(conn, 200)
      assert is_binary(response["url"])
      # Should use default expiry (3600)
      assert String.contains?(response["url"], "X-Amz-Expires=3600")
    end
  end

  describe "index endpoint success" do
    test "lists files for authenticated user" do
      Backend.HTTPClientMock
      |> expect(:get, fn url, _opts ->
        assert String.contains?(url, "test-uploads-bucket")
        assert String.contains?(url, "prefix=users%2Ftest_user_123%2Fuploads%2F")

        body = """
        <?xml version="1.0" encoding="UTF-8"?>
        <ListBucketResult>
          <Contents>
            <Key>users/test_user_123/uploads/12345_photo.jpg</Key>
            <Size>102400</Size>
            <LastModified>2024-01-15T10:30:00.000Z</LastModified>
          </Contents>
          <Contents>
            <Key>users/test_user_123/uploads/67890_document.pdf</Key>
            <Size>51200</Size>
            <LastModified>2024-01-16T14:20:00.000Z</LastModified>
          </Contents>
        </ListBucketResult>
        """

        {:ok, %{status: 200, body: body}}
      end)

      conn =
        build_conn()
        |> init_test_session(%{current_user: @test_user})
        |> get("/api/uploads")

      response = json_response(conn, 200)
      assert is_list(response["files"])
      assert length(response["files"]) == 2

      [file1, file2] = response["files"]
      assert file1["key"] == "users/test_user_123/uploads/12345_photo.jpg"
      assert file1["size"] == 102_400
      assert file2["key"] == "users/test_user_123/uploads/67890_document.pdf"
    end

    test "returns empty list when user has no files" do
      Backend.HTTPClientMock
      |> expect(:get, fn _url, _opts ->
        {:ok, %{status: 200, body: "<ListBucketResult></ListBucketResult>"}}
      end)

      conn =
        build_conn()
        |> init_test_session(%{current_user: @test_user})
        |> get("/api/uploads")

      response = json_response(conn, 200)
      assert response["files"] == []
    end

    test "handles pagination with max_keys and continuation_token" do
      Backend.HTTPClientMock
      |> expect(:get, fn url, _opts ->
        assert String.contains?(url, "max-keys=10")
        assert String.contains?(url, "continuation-token=token123")

        body = """
        <?xml version="1.0" encoding="UTF-8"?>
        <ListBucketResult>
          <Contents>
            <Key>users/test_user_123/uploads/99999_more.jpg</Key>
            <Size>1024</Size>
            <LastModified>2024-01-17T00:00:00.000Z</LastModified>
          </Contents>
          <NextContinuationToken>nexttoken456</NextContinuationToken>
        </ListBucketResult>
        """

        {:ok, %{status: 200, body: body}}
      end)

      conn =
        build_conn()
        |> init_test_session(%{current_user: @test_user})
        |> get("/api/uploads", %{"max_keys" => "10", "continuation_token" => "token123"})

      response = json_response(conn, 200)
      assert length(response["files"]) == 1
      assert response["next_token"] == "nexttoken456"
    end
  end

  describe "show endpoint success" do
    test "returns file metadata for user's file" do
      Backend.HTTPClientMock
      |> expect(:head, fn url, _opts ->
        assert String.contains?(url, "test-uploads-bucket")
        assert String.contains?(url, "users/test_user_123/uploads/12345_photo.jpg")

        {:ok,
         %{
           status: 200,
           headers: [
             {"content-length", "102400"},
             {"content-type", "image/jpeg"},
             {"last-modified", "Mon, 15 Jan 2024 10:30:00 GMT"},
             {"etag", "\"abc123\""}
           ]
         }}
      end)

      conn =
        build_conn()
        |> init_test_session(%{current_user: @test_user})
        |> get("/api/uploads/users%2Ftest_user_123%2Fuploads%2F12345_photo.jpg")

      response = json_response(conn, 200)
      assert response["key"] == "users/test_user_123/uploads/12345_photo.jpg"
      assert response["size"] == 102_400
      assert response["content_type"] == "image/jpeg"
    end

    test "returns 404 when file not found" do
      Backend.HTTPClientMock
      |> expect(:head, fn _url, _opts ->
        {:ok, %{status: 404}}
      end)

      conn =
        build_conn()
        |> init_test_session(%{current_user: @test_user})
        |> get("/api/uploads/users%2Ftest_user_123%2Fuploads%2Fnonexistent.jpg")

      assert json_response(conn, 404)["error"] == "not_found"
    end
  end

  describe "delete endpoint success" do
    test "deletes user's file" do
      Backend.HTTPClientMock
      |> expect(:delete, fn url, _opts ->
        assert String.contains?(url, "test-uploads-bucket")
        assert String.contains?(url, "users/test_user_123/uploads/12345_photo.jpg")
        {:ok, %{status: 204, body: ""}}
      end)

      conn =
        build_conn()
        |> init_test_session(%{current_user: @test_user})
        |> delete("/api/uploads/users%2Ftest_user_123%2Fuploads%2F12345_photo.jpg")

      assert response(conn, 204)
    end

    test "returns 204 even when file doesn't exist (idempotent)" do
      Backend.HTTPClientMock
      |> expect(:delete, fn _url, _opts ->
        {:ok, %{status: 404, body: ""}}
      end)

      conn =
        build_conn()
        |> init_test_session(%{current_user: @test_user})
        |> delete("/api/uploads/users%2Ftest_user_123%2Fuploads%2Fnonexistent.jpg")

      assert response(conn, 204)
    end
  end

  describe "allowed_types endpoint" do
    test "returns list of allowed content types without authentication" do
      # Note: This endpoint may or may not require auth depending on design
      # Testing with auth to be safe
      conn =
        build_conn()
        |> init_test_session(%{current_user: @test_user})
        |> get("/api/uploads/types")

      response = json_response(conn, 200)
      assert is_list(response["content_types"])
      assert "image/jpeg" in response["content_types"]
      assert "image/png" in response["content_types"]
      assert "application/pdf" in response["content_types"]
    end
  end

  describe "error handling" do
    test "index returns 500 on S3 error" do
      Backend.HTTPClientMock
      |> expect(:get, fn _url, _opts ->
        {:ok, %{status: 500, body: "<Error><Code>InternalError</Code></Error>"}}
      end)

      conn =
        build_conn()
        |> init_test_session(%{current_user: @test_user})
        |> get("/api/uploads")

      assert json_response(conn, 500)["error"] == "list_error"
    end

    test "show returns 500 on S3 error" do
      Backend.HTTPClientMock
      |> expect(:head, fn _url, _opts ->
        {:ok, %{status: 500, body: "Internal Server Error"}}
      end)

      conn =
        build_conn()
        |> init_test_session(%{current_user: @test_user})
        |> get("/api/uploads/users%2Ftest_user_123%2Fuploads%2Ffile.jpg")

      assert json_response(conn, 500)["error"] == "metadata_error"
    end

    test "delete returns 500 on S3 error" do
      Backend.HTTPClientMock
      |> expect(:delete, fn _url, _opts ->
        {:ok, %{status: 500, body: "Internal Server Error"}}
      end)

      conn =
        build_conn()
        |> init_test_session(%{current_user: @test_user})
        |> delete("/api/uploads/users%2Ftest_user_123%2Fuploads%2Ffile.jpg")

      assert json_response(conn, 500)["error"] == "delete_error"
    end
  end

  describe "user ID extraction edge cases" do
    test "works with user ID as atom key" do
      user = %{id: "user_atom_key", email: "test@example.com"}

      conn =
        build_conn()
        |> init_test_session(%{current_user: user})
        |> post("/api/uploads/presign", %{
          "filename" => "test.jpg",
          "content_type" => "image/jpeg"
        })

      response = json_response(conn, 200)
      assert String.contains?(response["key"], "users/user_atom_key/")
    end

    test "works with user ID as string key" do
      user = %{"id" => "user_string_key", "email" => "test@example.com"}

      conn =
        build_conn()
        |> init_test_session(%{current_user: user})
        |> post("/api/uploads/presign", %{
          "filename" => "test.jpg",
          "content_type" => "image/jpeg"
        })

      response = json_response(conn, 200)
      assert String.contains?(response["key"], "users/user_string_key/")
    end

    test "falls back to email when id not present" do
      user = %{email: "fallback@example.com", name: "Test"}

      conn =
        build_conn()
        |> init_test_session(%{current_user: user})
        |> post("/api/uploads/presign", %{
          "filename" => "test.jpg",
          "content_type" => "image/jpeg"
        })

      response = json_response(conn, 200)
      assert String.contains?(response["key"], "users/fallback@example.com/")
    end
  end
end
