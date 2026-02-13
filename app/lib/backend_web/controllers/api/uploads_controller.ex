defmodule BackendWeb.API.UploadsController do
  @moduledoc """
  API controller for file upload management.

  Provides endpoints for:
  - Generating presigned URLs for direct S3 uploads
  - Generating presigned URLs for downloads
  - Listing user's uploaded files
  - Deleting uploaded files

  ## Authentication

  All endpoints require authentication via session.
  Users can only access their own files.

  ## Direct Upload Flow

  1. Client requests presigned upload URL: `POST /api/uploads/presign`
  2. Server returns URL + form fields
  3. Client POSTs file directly to S3 with provided fields
  4. Client notifies server of upload completion (optional)

  ## Example Usage

      # 1. Get presigned URL
      POST /api/uploads/presign
      {"filename": "photo.jpg", "content_type": "image/jpeg"}

      # Response:
      {
        "url": "https://bucket.s3.region.amazonaws.com",
        "key": "users/123/uploads/1234_abc_photo.jpg",
        "fields": {...}
      }

      # 2. Upload directly to S3
      POST {url} with multipart/form-data including all fields + file

      # 3. Get download URL
      GET /api/uploads/users/123/uploads/1234_abc_photo.jpg/download

      # Response:
      {"url": "https://...presigned-download-url..."}
  """

  use BackendWeb, :controller

  alias Backend.Uploads
  alias BackendWeb.ErrorResponse

  action_fallback(BackendWeb.FallbackController)

  @doc """
  Generate a presigned URL for uploading a file.

  ## Request Body

  - `filename` (required) - Original filename
  - `content_type` (required) - MIME type of the file

  ## Response

  - `url` - S3 endpoint to POST to
  - `key` - S3 object key (save this to reference the file later)
  - `fields` - Form fields to include in the POST request

  ## Errors

  - 400 - Invalid content type or missing parameters
  - 401 - Not authenticated
  - 503 - S3 not configured
  """
  def presign(conn, %{"filename" => filename, "content_type" => content_type}) do
    user_id = get_user_id(conn)

    case Uploads.presigned_upload_url(user_id, filename, content_type) do
      {:ok, result} ->
        conn
        |> put_status(:ok)
        |> json(%{
          url: result.url,
          key: result.key,
          fields: result.fields
        })

      {:error, :invalid_content_type} ->
        conn
        |> put_status(:bad_request)
        |> json(%{
          error: "invalid_content_type",
          code: "invalid_content_type",
          message: "Content type not allowed",
          allowed_types: Uploads.allowed_content_types()
        })

      {:error, :invalid_extension} ->
        conn
        |> ErrorResponse.send(
          :bad_request,
          "invalid_extension",
          "File extension not allowed",
          %{allowed_extensions: Uploads.allowed_extensions()},
          error: "invalid_extension"
        )

      {:error, :invalid_filename} ->
        conn
        |> ErrorResponse.send(
          :bad_request,
          "invalid_filename",
          "Filename is invalid",
          nil,
          error: "invalid_filename"
        )

      {:error, :filename_too_long} ->
        conn
        |> ErrorResponse.send(
          :bad_request,
          "filename_too_long",
          "Filename exceeds maximum length",
          %{max_length: 255},
          error: "filename_too_long"
        )

      {:error, :not_configured} ->
        conn
        |> ErrorResponse.send(
          :service_unavailable,
          "service_unavailable",
          "File uploads are not configured",
          nil,
          error: "service_unavailable"
        )

      {:error, reason} ->
        conn
        |> ErrorResponse.send(
          :internal_server_error,
          "upload_error",
          "Failed to generate upload URL",
          %{reason: inspect(reason)},
          error: "upload_error"
        )
    end
  end

  def presign(conn, _params) do
    conn
    |> ErrorResponse.send(
      :bad_request,
      "invalid_request",
      "Missing required parameters: filename, content_type",
      nil,
      error: "invalid_request"
    )
  end

  @doc """
  Generate a presigned URL for downloading a file.

  ## URL Parameters

  - `key` - S3 object key (URL-encoded)

  ## Query Parameters

  - `expires_in` (optional) - URL expiration in seconds (default: 3600)

  ## Response

  - `url` - Presigned download URL

  ## Errors

  - 400 - Invalid key
  - 401 - Not authenticated
  - 403 - Key belongs to another user
  - 503 - S3 not configured
  """
  def download(conn, %{"key" => key} = params) do
    user_id = get_user_id(conn)

    # Verify the key belongs to this user
    if Uploads.valid_user_key?(user_id, key) do
      expires_in = parse_expires_in(params["expires_in"])
      opts = if expires_in, do: [expires_in: expires_in], else: []

      case Uploads.presigned_download_url(key, opts) do
        {:ok, url} ->
          conn
          |> put_status(:ok)
          |> json(%{url: url, key: key})

        {:error, :not_configured} ->
          conn
          |> ErrorResponse.send(
            :service_unavailable,
            "service_unavailable",
            "File uploads are not configured",
            nil,
            error: "service_unavailable"
          )

        {:error, reason} ->
          conn
          |> ErrorResponse.send(
            :internal_server_error,
            "download_error",
            "Failed to generate download URL",
            %{reason: inspect(reason)},
            error: "download_error"
          )
      end
    else
      conn
      |> ErrorResponse.send(:forbidden, "forbidden", "You don't have access to this file", nil,
        error: "forbidden"
      )
    end
  end

  @doc """
  List files uploaded by the current user.

  ## Query Parameters

  - `max_keys` (optional) - Maximum number of files to return (default: 100, max: 1000)
  - `continuation_token` (optional) - Token for pagination

  ## Response

  - `files` - Array of file objects with key, size, last_modified, filename
  - `next_token` - Token for next page (null if no more pages)

  ## Errors

  - 401 - Not authenticated
  - 503 - S3 not configured
  """
  def index(conn, params) do
    user_id = get_user_id(conn)

    max_keys = parse_max_keys(params["max_keys"])
    continuation_token = params["continuation_token"]

    opts = [max_keys: max_keys]

    opts =
      if continuation_token,
        do: Keyword.put(opts, :continuation_token, continuation_token),
        else: opts

    case Uploads.list_files(user_id, opts) do
      {:ok, result} ->
        conn
        |> put_status(:ok)
        |> json(%{
          files: result.files,
          next_token: result.next_token
        })

      {:error, :not_configured} ->
        conn
        |> ErrorResponse.send(
          :service_unavailable,
          "service_unavailable",
          "File uploads are not configured",
          nil,
          error: "service_unavailable"
        )

      {:error, reason} ->
        conn
        |> ErrorResponse.send(
          :internal_server_error,
          "list_error",
          "Failed to list files",
          %{reason: inspect(reason)},
          error: "list_error"
        )
    end
  end

  @doc """
  Get metadata for a specific file.

  ## URL Parameters

  - `key` - S3 object key (URL-encoded)

  ## Response

  - `key` - S3 object key
  - `size` - File size in bytes
  - `content_type` - MIME type
  - `last_modified` - Last modification timestamp
  - `etag` - File ETag

  ## Errors

  - 401 - Not authenticated
  - 403 - Key belongs to another user
  - 404 - File not found
  - 503 - S3 not configured
  """
  def show(conn, %{"key" => key}) do
    user_id = get_user_id(conn)

    # Verify the key belongs to this user
    if Uploads.valid_user_key?(user_id, key) do
      case Uploads.get_file_metadata(key) do
        {:ok, metadata} ->
          conn
          |> put_status(:ok)
          |> json(metadata)

        {:error, :not_found} ->
          conn
          |> ErrorResponse.send(:not_found, "not_found", "File not found", nil,
            error: "not_found"
          )

        {:error, :not_configured} ->
          conn
          |> ErrorResponse.send(
            :service_unavailable,
            "service_unavailable",
            "File uploads are not configured",
            nil,
            error: "service_unavailable"
          )

        {:error, reason} ->
          conn
          |> ErrorResponse.send(
            :internal_server_error,
            "metadata_error",
            "Failed to get file metadata",
            %{reason: inspect(reason)},
            error: "metadata_error"
          )
      end
    else
      conn
      |> ErrorResponse.send(:forbidden, "forbidden", "You don't have access to this file", nil,
        error: "forbidden"
      )
    end
  end

  @doc """
  Delete a file.

  ## URL Parameters

  - `key` - S3 object key (URL-encoded)

  ## Response

  - 204 No Content on success

  ## Errors

  - 401 - Not authenticated
  - 403 - Key belongs to another user
  - 503 - S3 not configured
  """
  def delete(conn, %{"key" => key}) do
    user_id = get_user_id(conn)

    # Verify the key belongs to this user
    if Uploads.valid_user_key?(user_id, key) do
      case Uploads.delete_file(key) do
        :ok ->
          send_resp(conn, :no_content, "")

        {:error, :not_configured} ->
          conn
          |> ErrorResponse.send(
            :service_unavailable,
            "service_unavailable",
            "File uploads are not configured",
            nil,
            error: "service_unavailable"
          )

        {:error, reason} ->
          conn
          |> ErrorResponse.send(
            :internal_server_error,
            "delete_error",
            "Failed to delete file",
            %{reason: inspect(reason)},
            error: "delete_error"
          )
      end
    else
      conn
      |> ErrorResponse.send(:forbidden, "forbidden", "You don't have access to this file", nil,
        error: "forbidden"
      )
    end
  end

  @doc """
  Get list of allowed content types for uploads.

  ## Response

  - `content_types` - Array of allowed MIME types
  """
  def allowed_types(conn, _params) do
    conn
    |> put_status(:ok)
    |> json(%{
      content_types: Uploads.allowed_content_types()
    })
  end

  # ---------------------------------------------------------------------------
  # Private Helpers
  # ---------------------------------------------------------------------------

  defp get_user_id(conn) do
    # Get user ID from session
    # The EnsureAuthenticated plug guarantees :current_user exists in session
    case get_session(conn, :current_user) do
      %{id: id} when is_binary(id) ->
        id

      %{"id" => id} when is_binary(id) ->
        id

      user when is_map(user) ->
        # Try various common ID keys
        user[:id] || user["id"] || user[:user_id] || user["user_id"] ||
          user[:email] || user["email"]

      _ ->
        nil
    end
  end

  defp parse_expires_in(nil), do: nil

  defp parse_expires_in(value) when is_binary(value) do
    case Integer.parse(value) do
      {int, ""} when int > 0 and int <= 604_800 -> int
      _ -> nil
    end
  end

  defp parse_expires_in(value) when is_integer(value) and value > 0 and value <= 604_800,
    do: value

  defp parse_expires_in(_), do: nil

  defp parse_max_keys(nil), do: 100

  defp parse_max_keys(value) when is_binary(value) do
    case Integer.parse(value) do
      {int, ""} when int > 0 and int <= 1000 -> int
      _ -> 100
    end
  end

  defp parse_max_keys(value) when is_integer(value) and value > 0 and value <= 1000, do: value
  defp parse_max_keys(_), do: 100
end
