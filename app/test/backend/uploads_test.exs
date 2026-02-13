defmodule Backend.UploadsTest do
  @moduledoc """
  Unit tests for Backend.Uploads module.

  These tests verify the uploads module functionality including:
  - Content type validation
  - User key validation
  - Configuration handling
  - Presigned URL generation (mocked)
  """

  # async: false because tests manipulate global environment variables
  use ExUnit.Case, async: false

  alias Backend.Uploads

  describe "allowed_content_types/0" do
    test "returns a list of allowed MIME types" do
      types = Uploads.allowed_content_types()

      assert is_list(types)
      refute Enum.empty?(types)
      assert "image/jpeg" in types
      assert "image/png" in types
      assert "application/pdf" in types
    end
  end

  describe "allowed_content_type?/1" do
    test "returns true for allowed image types" do
      assert Uploads.allowed_content_type?("image/jpeg")
      assert Uploads.allowed_content_type?("image/png")
      assert Uploads.allowed_content_type?("image/gif")
      assert Uploads.allowed_content_type?("image/webp")
      assert Uploads.allowed_content_type?("image/svg+xml")
    end

    test "returns true for allowed document types" do
      assert Uploads.allowed_content_type?("application/pdf")
      assert Uploads.allowed_content_type?("application/msword")

      assert Uploads.allowed_content_type?(
               "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
             )

      assert Uploads.allowed_content_type?("application/vnd.ms-excel")

      assert Uploads.allowed_content_type?(
               "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
             )
    end

    test "returns true for allowed text types" do
      assert Uploads.allowed_content_type?("text/plain")
      assert Uploads.allowed_content_type?("text/csv")
    end

    test "returns true for allowed video types" do
      assert Uploads.allowed_content_type?("video/mp4")
      assert Uploads.allowed_content_type?("video/webm")
      assert Uploads.allowed_content_type?("video/quicktime")
    end

    test "returns true for allowed audio types" do
      assert Uploads.allowed_content_type?("audio/mpeg")
      assert Uploads.allowed_content_type?("audio/wav")
      assert Uploads.allowed_content_type?("audio/ogg")
    end

    test "returns false for disallowed types" do
      refute Uploads.allowed_content_type?("application/x-executable")
      refute Uploads.allowed_content_type?("application/x-msdownload")
      refute Uploads.allowed_content_type?("text/html")
      refute Uploads.allowed_content_type?("application/javascript")
      refute Uploads.allowed_content_type?("application/x-sh")
    end

    test "returns false for empty or nil" do
      refute Uploads.allowed_content_type?("")
      refute Uploads.allowed_content_type?(nil)
    end
  end

  describe "valid_user_key?/2" do
    test "returns true for valid user key" do
      assert Uploads.valid_user_key?("user_123", "users/user_123/uploads/file.jpg")
      assert Uploads.valid_user_key?("abc", "users/abc/uploads/1234_xyz_photo.png")
      assert Uploads.valid_user_key?("user-456", "users/user-456/uploads/doc.pdf")
    end

    test "returns false for key belonging to different user" do
      refute Uploads.valid_user_key?("user_123", "users/user_456/uploads/file.jpg")
      refute Uploads.valid_user_key?("abc", "users/xyz/uploads/file.jpg")
    end

    test "returns false for invalid key format" do
      refute Uploads.valid_user_key?("user_123", "invalid/path/file.jpg")
      refute Uploads.valid_user_key?("user_123", "users/user_123/file.jpg")
      refute Uploads.valid_user_key?("user_123", "file.jpg")
    end

    test "returns false for empty key" do
      refute Uploads.valid_user_key?("user_123", "")
    end

    test "returns false for partial prefix match" do
      # Should not match user_1234 when looking for user_123
      refute Uploads.valid_user_key?("user_123", "users/user_1234/uploads/file.jpg")
    end
  end

  describe "presigned_upload_url/3" do
    test "returns error for invalid content type" do
      result = Uploads.presigned_upload_url("user_123", "malware.exe", "application/x-executable")
      assert {:error, :invalid_content_type} = result
    end

    test "returns error when not configured" do
      # Clear environment variables to simulate unconfigured state
      original_bucket = System.get_env("UPLOADS_BUCKET")
      original_region = System.get_env("UPLOADS_REGION")
      original_aws_region = System.get_env("AWS_REGION")

      System.delete_env("UPLOADS_BUCKET")
      System.delete_env("UPLOADS_REGION")
      System.delete_env("AWS_REGION")

      try do
        result = Uploads.presigned_upload_url("user_123", "photo.jpg", "image/jpeg")
        assert {:error, :not_configured} = result
      after
        # Restore environment variables
        if original_bucket, do: System.put_env("UPLOADS_BUCKET", original_bucket)
        if original_region, do: System.put_env("UPLOADS_REGION", original_region)
        if original_aws_region, do: System.put_env("AWS_REGION", original_aws_region)
      end
    end
  end

  describe "presigned_download_url/2" do
    test "returns error when not configured" do
      original_bucket = System.get_env("UPLOADS_BUCKET")
      original_region = System.get_env("UPLOADS_REGION")
      original_aws_region = System.get_env("AWS_REGION")

      System.delete_env("UPLOADS_BUCKET")
      System.delete_env("UPLOADS_REGION")
      System.delete_env("AWS_REGION")

      try do
        result = Uploads.presigned_download_url("users/123/uploads/file.jpg")
        assert {:error, :not_configured} = result
      after
        if original_bucket, do: System.put_env("UPLOADS_BUCKET", original_bucket)
        if original_region, do: System.put_env("UPLOADS_REGION", original_region)
        if original_aws_region, do: System.put_env("AWS_REGION", original_aws_region)
      end
    end
  end

  describe "delete_file/1" do
    test "returns error when not configured" do
      original_bucket = System.get_env("UPLOADS_BUCKET")
      original_region = System.get_env("UPLOADS_REGION")
      original_aws_region = System.get_env("AWS_REGION")

      System.delete_env("UPLOADS_BUCKET")
      System.delete_env("UPLOADS_REGION")
      System.delete_env("AWS_REGION")

      try do
        result = Uploads.delete_file("users/123/uploads/file.jpg")
        assert {:error, :not_configured} = result
      after
        if original_bucket, do: System.put_env("UPLOADS_BUCKET", original_bucket)
        if original_region, do: System.put_env("UPLOADS_REGION", original_region)
        if original_aws_region, do: System.put_env("AWS_REGION", original_aws_region)
      end
    end
  end

  describe "list_files/2" do
    test "returns error when not configured" do
      original_bucket = System.get_env("UPLOADS_BUCKET")
      original_region = System.get_env("UPLOADS_REGION")
      original_aws_region = System.get_env("AWS_REGION")

      System.delete_env("UPLOADS_BUCKET")
      System.delete_env("UPLOADS_REGION")
      System.delete_env("AWS_REGION")

      try do
        result = Uploads.list_files("user_123")
        assert {:error, :not_configured} = result
      after
        if original_bucket, do: System.put_env("UPLOADS_BUCKET", original_bucket)
        if original_region, do: System.put_env("UPLOADS_REGION", original_region)
        if original_aws_region, do: System.put_env("AWS_REGION", original_aws_region)
      end
    end
  end

  describe "get_file_metadata/1" do
    test "returns error when not configured" do
      original_bucket = System.get_env("UPLOADS_BUCKET")
      original_region = System.get_env("UPLOADS_REGION")
      original_aws_region = System.get_env("AWS_REGION")

      System.delete_env("UPLOADS_BUCKET")
      System.delete_env("UPLOADS_REGION")
      System.delete_env("AWS_REGION")

      try do
        result = Uploads.get_file_metadata("users/123/uploads/file.jpg")
        assert {:error, :not_configured} = result
      after
        if original_bucket, do: System.put_env("UPLOADS_BUCKET", original_bucket)
        if original_region, do: System.put_env("UPLOADS_REGION", original_region)
        if original_aws_region, do: System.put_env("AWS_REGION", original_aws_region)
      end
    end
  end
end
