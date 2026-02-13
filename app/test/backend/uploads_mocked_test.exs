defmodule Backend.UploadsMockedTest do
  @moduledoc """
  Mocked tests for the Uploads module.

  These tests use Mox to mock HTTP responses for S3 operations,
  allowing us to test all code paths without making real AWS API calls.
  """

  use ExUnit.Case, async: true

  import Mox

  alias Backend.Uploads

  # Make sure mocks are verified when the test exits
  setup :verify_on_exit!

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

  # ===========================================================================
  # presigned_upload_url/3 Tests
  # ===========================================================================

  describe "presigned_upload_url/3" do
    test "generates presigned upload URL successfully" do
      result = Uploads.presigned_upload_url("user_123", "test.jpg", "image/jpeg")

      assert {:ok, response} = result
      assert is_binary(response.url)
      assert String.contains?(response.url, "test-uploads-bucket")
      assert is_binary(response.key)
      assert String.starts_with?(response.key, "users/user_123/uploads/")
      assert String.ends_with?(response.key, "_test.jpg")
      assert is_map(response.fields)
    end

    test "rejects invalid content type" do
      result = Uploads.presigned_upload_url("user_123", "test.exe", "application/x-executable")

      assert {:error, :invalid_content_type} = result
    end

    test "generates unique keys for same filename" do
      {:ok, result1} = Uploads.presigned_upload_url("user_123", "test.jpg", "image/jpeg")
      {:ok, result2} = Uploads.presigned_upload_url("user_123", "test.jpg", "image/jpeg")

      assert result1.key != result2.key
    end

    test "supports various allowed content types" do
      allowed_types = [
        {"photo.jpg", "image/jpeg"},
        {"photo.png", "image/png"},
        {"photo.gif", "image/gif"},
        {"photo.webp", "image/webp"},
        {"doc.pdf", "application/pdf"},
        {"doc.txt", "text/plain"}
      ]

      for {filename, content_type} <- allowed_types do
        result = Uploads.presigned_upload_url("user_123", filename, content_type)
        assert {:ok, _} = result, "Expected #{content_type} to be allowed"
      end
    end

    test "sanitizes filename in key" do
      {:ok, result} = Uploads.presigned_upload_url("user_123", "my file (1).jpg", "image/jpeg")

      # The key should contain a sanitized version of the filename
      # Spaces and special characters are replaced with underscores
      assert String.contains?(result.key, "my_file__1_.jpg")
    end
  end

  # ===========================================================================
  # presigned_download_url/2 Tests
  # ===========================================================================

  describe "presigned_download_url/2" do
    test "generates presigned download URL with default expiry" do
      key = "users/user_123/uploads/12345_test.jpg"
      result = Uploads.presigned_download_url(key)

      assert {:ok, url} = result
      assert is_binary(url)
      assert String.contains?(url, "test-uploads-bucket")
      assert String.contains?(url, "X-Amz-Expires=3600")
    end

    test "generates presigned download URL with custom expiry" do
      key = "users/user_123/uploads/12345_test.jpg"
      result = Uploads.presigned_download_url(key, expires_in: 7200)

      assert {:ok, url} = result
      assert String.contains?(url, "X-Amz-Expires=7200")
    end

    test "includes required signature parameters" do
      key = "users/user_123/uploads/12345_test.jpg"
      {:ok, url} = Uploads.presigned_download_url(key)

      assert String.contains?(url, "X-Amz-Algorithm=AWS4-HMAC-SHA256")
      assert String.contains?(url, "X-Amz-Credential=")
      assert String.contains?(url, "X-Amz-Date=")
      assert String.contains?(url, "X-Amz-SignedHeaders=host")
      assert String.contains?(url, "X-Amz-Signature=")
    end
  end

  # ===========================================================================
  # delete_file/1 Tests
  # ===========================================================================

  describe "delete_file/1" do
    test "deletes file successfully" do
      Backend.HTTPClientMock
      |> expect(:delete, fn url, opts ->
        assert String.contains?(url, "test-uploads-bucket")
        assert String.contains?(url, "users/user_123/uploads/test.jpg")
        assert Keyword.has_key?(opts, :headers)
        {:ok, %{status: 204, body: ""}}
      end)

      key = "users/user_123/uploads/test.jpg"
      result = Uploads.delete_file(key)

      assert :ok = result
    end

    test "returns ok when file not found (idempotent delete)" do
      Backend.HTTPClientMock
      |> expect(:delete, fn _url, _opts ->
        {:ok, %{status: 404, body: ""}}
      end)

      key = "users/user_123/uploads/nonexistent.jpg"
      result = Uploads.delete_file(key)

      assert :ok = result
    end

    test "handles S3 error responses" do
      Backend.HTTPClientMock
      |> expect(:delete, fn _url, _opts ->
        {:ok, %{status: 403, body: "<Error><Code>AccessDenied</Code></Error>"}}
      end)

      key = "users/user_123/uploads/test.jpg"
      result = Uploads.delete_file(key)

      assert {:error, %{status_code: 403}} = result
    end

    test "handles network errors" do
      Backend.HTTPClientMock
      |> expect(:delete, fn _url, _opts ->
        {:error, %Req.TransportError{reason: :timeout}}
      end)

      key = "users/user_123/uploads/test.jpg"
      result = Uploads.delete_file(key)

      assert {:error, %Req.TransportError{reason: :timeout}} = result
    end
  end

  # ===========================================================================
  # list_files/2 Tests
  # ===========================================================================

  describe "list_files/2" do
    test "lists files successfully" do
      Backend.HTTPClientMock
      |> expect(:get, fn url, opts ->
        assert String.contains?(url, "test-uploads-bucket")
        assert String.contains?(url, "prefix=users%2Fuser_123%2Fuploads%2F")
        assert String.contains?(url, "list-type=2")
        assert Keyword.has_key?(opts, :headers)

        body = """
        <?xml version="1.0" encoding="UTF-8"?>
        <ListBucketResult>
          <Contents>
            <Key>users/user_123/uploads/12345_photo.jpg</Key>
            <Size>102400</Size>
            <LastModified>2024-01-15T10:30:00.000Z</LastModified>
          </Contents>
          <Contents>
            <Key>users/user_123/uploads/67890_document.pdf</Key>
            <Size>51200</Size>
            <LastModified>2024-01-16T14:20:00.000Z</LastModified>
          </Contents>
        </ListBucketResult>
        """

        {:ok, %{status: 200, body: body}}
      end)

      result = Uploads.list_files("user_123")

      assert {:ok, %{files: files, next_token: nil}} = result
      assert length(files) == 2

      [file1, file2] = files
      assert file1.key == "users/user_123/uploads/12345_photo.jpg"
      assert file1.size == 102_400
      assert file1.filename == "12345_photo.jpg"

      assert file2.key == "users/user_123/uploads/67890_document.pdf"
      assert file2.size == 51_200
    end

    test "returns empty list when no files" do
      Backend.HTTPClientMock
      |> expect(:get, fn _url, _opts ->
        body = """
        <?xml version="1.0" encoding="UTF-8"?>
        <ListBucketResult>
        </ListBucketResult>
        """

        {:ok, %{status: 200, body: body}}
      end)

      result = Uploads.list_files("user_123")

      assert {:ok, %{files: [], next_token: nil}} = result
    end

    test "handles pagination with continuation token" do
      Backend.HTTPClientMock
      |> expect(:get, fn url, _opts ->
        assert String.contains?(url, "continuation-token=token123")

        body = """
        <?xml version="1.0" encoding="UTF-8"?>
        <ListBucketResult>
          <Contents>
            <Key>users/user_123/uploads/99999_more.jpg</Key>
            <Size>1024</Size>
            <LastModified>2024-01-17T00:00:00.000Z</LastModified>
          </Contents>
          <NextContinuationToken>nexttoken456</NextContinuationToken>
        </ListBucketResult>
        """

        {:ok, %{status: 200, body: body}}
      end)

      result = Uploads.list_files("user_123", continuation_token: "token123")

      assert {:ok, %{files: files, next_token: "nexttoken456"}} = result
      assert length(files) == 1
    end

    test "respects max_keys option" do
      Backend.HTTPClientMock
      |> expect(:get, fn url, _opts ->
        assert String.contains?(url, "max-keys=10")
        {:ok, %{status: 200, body: "<ListBucketResult></ListBucketResult>"}}
      end)

      Uploads.list_files("user_123", max_keys: 10)
    end

    test "handles S3 error responses" do
      Backend.HTTPClientMock
      |> expect(:get, fn _url, _opts ->
        {:ok, %{status: 500, body: "<Error><Code>InternalError</Code></Error>"}}
      end)

      result = Uploads.list_files("user_123")

      assert {:error, %{status_code: 500}} = result
    end
  end

  # ===========================================================================
  # get_file_metadata/1 Tests
  # ===========================================================================

  describe "get_file_metadata/1" do
    test "gets file metadata successfully" do
      Backend.HTTPClientMock
      |> expect(:head, fn url, opts ->
        assert String.contains?(url, "test-uploads-bucket")
        assert String.contains?(url, "users/user_123/uploads/test.jpg")
        assert Keyword.has_key?(opts, :headers)

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

      key = "users/user_123/uploads/test.jpg"
      result = Uploads.get_file_metadata(key)

      assert {:ok, metadata} = result
      assert metadata.key == key
      assert metadata.size == 102_400
      assert metadata.content_type == "image/jpeg"
      assert metadata.last_modified == "Mon, 15 Jan 2024 10:30:00 GMT"
      assert metadata.etag == "\"abc123\""
    end

    test "returns not_found for missing file" do
      Backend.HTTPClientMock
      |> expect(:head, fn _url, _opts ->
        {:ok, %{status: 404}}
      end)

      key = "users/user_123/uploads/nonexistent.jpg"
      result = Uploads.get_file_metadata(key)

      assert {:error, :not_found} = result
    end

    test "handles S3 error responses" do
      Backend.HTTPClientMock
      |> expect(:head, fn _url, _opts ->
        {:ok, %{status: 403, body: "Forbidden"}}
      end)

      key = "users/user_123/uploads/test.jpg"
      result = Uploads.get_file_metadata(key)

      assert {:error, %{status_code: 403}} = result
    end

    test "handles network errors" do
      Backend.HTTPClientMock
      |> expect(:head, fn _url, _opts ->
        {:error, %Req.TransportError{reason: :econnrefused}}
      end)

      key = "users/user_123/uploads/test.jpg"
      result = Uploads.get_file_metadata(key)

      assert {:error, %Req.TransportError{}} = result
    end
  end

  # ===========================================================================
  # valid_user_key?/2 Tests
  # ===========================================================================

  describe "valid_user_key?/2" do
    test "returns true for matching user key" do
      assert Uploads.valid_user_key?("user_123", "users/user_123/uploads/test.jpg")
    end

    test "returns false for different user key" do
      refute Uploads.valid_user_key?("user_123", "users/user_456/uploads/test.jpg")
    end

    test "returns false for malformed key" do
      refute Uploads.valid_user_key?("user_123", "invalid/path/test.jpg")
    end

    test "returns false for empty key" do
      refute Uploads.valid_user_key?("user_123", "")
    end

    test "handles special characters in user_id" do
      assert Uploads.valid_user_key?(
               "user@example.com",
               "users/user@example.com/uploads/test.jpg"
             )
    end
  end

  # ===========================================================================
  # allowed_content_types/0 Tests
  # ===========================================================================

  describe "allowed_content_types/0" do
    test "returns list of allowed MIME types" do
      types = Uploads.allowed_content_types()

      assert is_list(types)
      refute Enum.empty?(types)

      # Check common types are included
      assert "image/jpeg" in types
      assert "image/png" in types
      assert "image/gif" in types
      assert "application/pdf" in types
    end
  end

  # ===========================================================================
  # allowed_content_type?/1 Tests
  # ===========================================================================

  describe "allowed_content_type?/1" do
    test "returns true for allowed types" do
      assert Uploads.allowed_content_type?("image/jpeg")
      assert Uploads.allowed_content_type?("image/png")
      assert Uploads.allowed_content_type?("application/pdf")
    end

    test "returns false for disallowed types" do
      refute Uploads.allowed_content_type?("application/x-executable")
      refute Uploads.allowed_content_type?("application/javascript")
      refute Uploads.allowed_content_type?("text/html")
    end
  end

  # ===========================================================================
  # Configuration Error Tests
  # ===========================================================================

  describe "configuration errors" do
    setup do
      # Clear the bucket configuration
      System.delete_env("UPLOADS_BUCKET")

      on_exit(fn ->
        System.put_env("UPLOADS_BUCKET", "test-uploads-bucket")
      end)

      :ok
    end

    test "presigned_upload_url returns not_configured when bucket missing" do
      result = Uploads.presigned_upload_url("user_123", "test.jpg", "image/jpeg")
      assert {:error, :not_configured} = result
    end

    test "presigned_download_url returns not_configured when bucket missing" do
      result = Uploads.presigned_download_url("users/user_123/uploads/test.jpg")
      assert {:error, :not_configured} = result
    end

    test "delete_file returns not_configured when bucket missing" do
      result = Uploads.delete_file("users/user_123/uploads/test.jpg")
      assert {:error, :not_configured} = result
    end

    test "list_files returns not_configured when bucket missing" do
      result = Uploads.list_files("user_123")
      assert {:error, :not_configured} = result
    end

    test "get_file_metadata returns not_configured when bucket missing" do
      result = Uploads.get_file_metadata("users/user_123/uploads/test.jpg")
      assert {:error, :not_configured} = result
    end
  end

  # ===========================================================================
  # AWS Credentials Error Tests
  # ===========================================================================

  describe "AWS credentials errors" do
    setup do
      # Clear AWS credentials
      System.delete_env("AWS_ACCESS_KEY_ID")
      System.delete_env("AWS_SECRET_ACCESS_KEY")
      System.delete_env("AWS_CONTAINER_CREDENTIALS_RELATIVE_URI")

      on_exit(fn ->
        System.put_env("AWS_ACCESS_KEY_ID", "AKIAIOSFODNN7EXAMPLE")
        System.put_env("AWS_SECRET_ACCESS_KEY", "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY")
      end)

      :ok
    end

    test "delete_file returns error when no credentials" do
      result = Uploads.delete_file("users/user_123/uploads/test.jpg")
      assert {:error, :no_credentials} = result
    end

    test "list_files returns error when no credentials" do
      result = Uploads.list_files("user_123")
      assert {:error, :no_credentials} = result
    end

    test "get_file_metadata returns error when no credentials" do
      result = Uploads.get_file_metadata("users/user_123/uploads/test.jpg")
      assert {:error, :no_credentials} = result
    end
  end

  # ===========================================================================
  # ECS Task Role Credentials Tests
  # ===========================================================================

  describe "ECS task role credentials" do
    setup do
      # Clear static credentials but set ECS credentials URI
      System.delete_env("AWS_ACCESS_KEY_ID")
      System.delete_env("AWS_SECRET_ACCESS_KEY")
      System.put_env("AWS_CONTAINER_CREDENTIALS_RELATIVE_URI", "/v2/credentials/test-guid")

      on_exit(fn ->
        System.put_env("AWS_ACCESS_KEY_ID", "AKIAIOSFODNN7EXAMPLE")
        System.put_env("AWS_SECRET_ACCESS_KEY", "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY")
        System.delete_env("AWS_CONTAINER_CREDENTIALS_RELATIVE_URI")
      end)

      :ok
    end

    test "fetches credentials from ECS metadata endpoint" do
      # Mock the ECS credentials endpoint
      Backend.HTTPClientMock
      |> expect(:get, fn url, _opts ->
        assert url == "http://169.254.170.2/v2/credentials/test-guid"

        {:ok,
         %{
           status: 200,
           body: %{
             "AccessKeyId" => "ASIATEMP123",
             "SecretAccessKey" => "tempsecret456",
             "Token" => "sessiontoken789"
           }
         }}
      end)
      # Then expect the S3 delete call
      |> expect(:delete, fn _url, _opts ->
        {:ok, %{status: 204, body: ""}}
      end)

      result = Uploads.delete_file("users/user_123/uploads/test.jpg")
      assert :ok = result
    end

    test "returns error when ECS credentials endpoint fails" do
      Backend.HTTPClientMock
      |> expect(:get, fn _url, _opts ->
        {:ok, %{status: 500, body: "Internal Server Error"}}
      end)

      result = Uploads.delete_file("users/user_123/uploads/test.jpg")
      assert {:error, :no_credentials} = result
    end
  end
end
