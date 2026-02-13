defmodule Backend.Uploads do
  @moduledoc """
  File upload management using S3 with presigned URLs.

  This module provides secure file upload functionality using AWS S3 presigned URLs.
  Files are uploaded directly from clients to S3, bypassing the application server
  for better performance and reduced load.

  ## Features

  - **Presigned Upload URLs**: Generate secure, time-limited URLs for direct uploads
  - **Presigned Download URLs**: Generate secure, time-limited URLs for downloads
  - **User-scoped Storage**: Files are organized by user ID for isolation
  - **Content-Type Validation**: Restrict uploads to allowed MIME types
  - **File Size Limits**: Enforce maximum file size via presigned URL conditions

  ## Configuration

  The following environment variables must be set:

  - `UPLOADS_BUCKET` - S3 bucket name for uploads
  - `UPLOADS_REGION` - AWS region where the bucket is located
  - `UPLOADS_MAX_SIZE_MB` - Maximum file size in megabytes (default: 50)
  - `UPLOADS_PRESIGNED_URL_EXPIRY` - URL expiration in seconds (default: 3600)
  - `AWS_REGION` - AWS region for SDK operations

  ## Usage

      # Generate an upload URL for a user
      {:ok, %{url: url, key: key, fields: fields}} =
        Backend.Uploads.presigned_upload_url(user_id, "profile.jpg", "image/jpeg")

      # Generate a download URL
      {:ok, url} = Backend.Uploads.presigned_download_url(key)

      # Delete a file
      :ok = Backend.Uploads.delete_file(key)

      # List user's files
      {:ok, files} = Backend.Uploads.list_files(user_id)

  ## File Organization

  Files are stored with the following key structure:

      users/{user_id}/uploads/{timestamp}_{original_filename}

  This provides:
  - Natural isolation by user
  - Chronological ordering within a user's uploads
  - Retention of original filename for reference

  ## Security

  - All access is via presigned URLs (bucket is not public)
  - URLs expire after configured duration
  - Content-type is restricted to allowed MIME types
  - File size is enforced via presigned POST conditions
  - Server-side encryption is applied to all uploads
  """

  require Logger

  # Allowed MIME types for uploads (expand as needed)
  @allowed_content_types [
    # Images
    "image/jpeg",
    "image/png",
    "image/gif",
    "image/webp",
    "image/svg+xml",
    # Documents
    "application/pdf",
    "application/msword",
    "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
    "application/vnd.ms-excel",
    "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
    # Text
    "text/plain",
    "text/csv",
    # Video
    "video/mp4",
    "video/webm",
    "video/quicktime",
    # Audio
    "audio/mpeg",
    "audio/wav",
    "audio/ogg"
  ]

  @allowed_extensions [
    ".jpg",
    ".jpeg",
    ".png",
    ".gif",
    ".webp",
    ".svg",
    ".pdf",
    ".doc",
    ".docx",
    ".xls",
    ".xlsx",
    ".txt",
    ".csv",
    ".mp4",
    ".webm",
    ".mov",
    ".mp3",
    ".wav",
    ".ogg"
  ]

  @doc """
  Returns the list of allowed content types for uploads.

  ## Example

      iex> Backend.Uploads.allowed_content_types()
      ["image/jpeg", "image/png", ...]
  """
  def allowed_content_types, do: @allowed_content_types

  @doc """
  Returns supported file extensions for uploads.
  """
  def allowed_extensions, do: @allowed_extensions

  @doc """
  Checks if a content type is allowed for uploads.

  ## Examples

      iex> Backend.Uploads.allowed_content_type?("image/jpeg")
      true

      iex> Backend.Uploads.allowed_content_type?("application/x-executable")
      false
  """
  def allowed_content_type?(content_type) do
    content_type in @allowed_content_types
  end

  @doc """
  Generate a presigned POST URL for uploading a file.

  Returns a map with the upload URL and form fields that must be included
  in the multipart POST request.

  ## Parameters

  - `user_id` - ID of the user uploading the file
  - `filename` - Original filename (used for key generation)
  - `content_type` - MIME type of the file

  ## Returns

  - `{:ok, %{url: String.t(), key: String.t(), fields: map()}}` - Success
  - `{:error, :invalid_content_type}` - Content type not allowed
  - `{:error, :not_configured}` - S3 bucket not configured
  - `{:error, reason}` - AWS error

  ## Example

      {:ok, %{url: url, key: key, fields: fields}} =
        Backend.Uploads.presigned_upload_url("user_123", "photo.jpg", "image/jpeg")

      # Client should POST to url with form-data:
      # - All fields from the fields map
      # - file: the actual file content (must be last)
  """
  def presigned_upload_url(user_id, filename, content_type) do
    with :ok <- validate_filename(filename),
         :ok <- validate_content_type(content_type),
         :ok <- validate_extension(filename),
         {:ok, config} <- get_config() do
      key = generate_key(user_id, filename)
      expiry = config.presigned_url_expiry
      max_size = config.max_size_bytes

      # Build presigned POST with conditions
      case generate_presigned_post(
             config.bucket,
             config.region,
             key,
             content_type,
             expiry,
             max_size
           ) do
        {:ok, result} ->
          Logger.info("Generated presigned upload URL for user #{user_id}, key: #{key}")
          {:ok, Map.put(result, :key, key)}

        {:error, reason} = error ->
          Logger.error("Failed to generate presigned upload URL: #{inspect(reason)}")
          error
      end
    end
  end

  @doc """
  Generate a presigned GET URL for downloading a file.

  ## Parameters

  - `key` - S3 object key
  - `opts` - Options:
    - `:expires_in` - Override expiration time in seconds

  ## Returns

  - `{:ok, url}` - Success with presigned URL
  - `{:error, :not_configured}` - S3 bucket not configured
  - `{:error, reason}` - AWS error

  ## Example

      {:ok, url} = Backend.Uploads.presigned_download_url("users/123/uploads/file.jpg")
  """
  def presigned_download_url(key, opts \\ []) do
    with {:ok, config} <- get_config() do
      expires_in = Keyword.get(opts, :expires_in, config.presigned_url_expiry)

      case generate_presigned_get(config.bucket, config.region, key, expires_in) do
        {:ok, url} ->
          {:ok, url}

        {:error, reason} = error ->
          Logger.error("Failed to generate presigned download URL: #{inspect(reason)}")
          error
      end
    end
  end

  @doc """
  Delete a file from S3.

  ## Parameters

  - `key` - S3 object key to delete

  ## Returns

  - `:ok` - Success
  - `{:error, :not_configured}` - S3 bucket not configured
  - `{:error, reason}` - AWS error

  ## Example

      :ok = Backend.Uploads.delete_file("users/123/uploads/file.jpg")
  """
  def delete_file(key) do
    with {:ok, config} <- get_config() do
      case s3_delete_object(config.bucket, config.region, key) do
        {:ok, _} ->
          Logger.info("Deleted file: #{key}")
          :ok

        {:error, reason} = error ->
          Logger.error("Failed to delete file #{key}: #{inspect(reason)}")
          error
      end
    end
  end

  @doc """
  List files for a user.

  ## Parameters

  - `user_id` - ID of the user
  - `opts` - Options:
    - `:max_keys` - Maximum number of keys to return (default: 1000)
    - `:continuation_token` - Token for pagination

  ## Returns

  - `{:ok, %{files: list(), next_token: String.t() | nil}}` - Success
  - `{:error, :not_configured}` - S3 bucket not configured
  - `{:error, reason}` - AWS error

  ## Example

      {:ok, %{files: files}} = Backend.Uploads.list_files("user_123")
  """
  def list_files(user_id, opts \\ []) do
    with {:ok, config} <- get_config() do
      prefix = "users/#{user_id}/uploads/"
      max_keys = Keyword.get(opts, :max_keys, 1000)
      continuation_token = Keyword.get(opts, :continuation_token)

      case s3_list_objects(config.bucket, config.region, prefix, max_keys, continuation_token) do
        {:ok, result} ->
          files = transform_s3_objects(result.contents)
          {:ok, %{files: files, next_token: result.next_continuation_token}}

        {:error, reason} = error ->
          Logger.error("Failed to list files for user #{user_id}: #{inspect(reason)}")
          error
      end
    end
  end

  defp transform_s3_objects(contents) do
    Enum.map(contents, fn obj ->
      %{
        key: obj.key,
        size: obj.size,
        last_modified: obj.last_modified,
        filename: extract_filename(obj.key)
      }
    end)
  end

  @doc """
  Get metadata for a specific file.

  ## Parameters

  - `key` - S3 object key

  ## Returns

  - `{:ok, map()}` - Success with file metadata
  - `{:error, :not_found}` - File does not exist
  - `{:error, :not_configured}` - S3 bucket not configured
  - `{:error, reason}` - AWS error
  """
  def get_file_metadata(key) do
    with {:ok, config} <- get_config() do
      case s3_head_object(config.bucket, config.region, key) do
        {:ok, result} ->
          {:ok,
           %{
             key: key,
             size: result.content_length,
             content_type: result.content_type,
             last_modified: result.last_modified,
             etag: result.etag
           }}

        {:error, %{status_code: 404}} ->
          {:error, :not_found}

        {:error, reason} = error ->
          Logger.error("Failed to get file metadata for #{key}: #{inspect(reason)}")
          error
      end
    end
  end

  @doc """
  Validate that a key belongs to a specific user.

  Ensures the key follows the expected pattern and belongs to the user.

  ## Example

      Backend.Uploads.valid_user_key?("user_123", "users/user_123/uploads/file.jpg")
      # => true

      Backend.Uploads.valid_user_key?("user_123", "users/user_456/uploads/file.jpg")
      # => false
  """
  def valid_user_key?(user_id, key) do
    prefix = "users/#{user_id}/uploads/"
    String.starts_with?(key, prefix)
  end

  # ==========================================================================
  # Private Functions
  # ==========================================================================

  defp validate_content_type(content_type) do
    if allowed_content_type?(content_type) do
      :ok
    else
      {:error, :invalid_content_type}
    end
  end

  defp validate_filename(filename) when is_binary(filename) do
    cond do
      byte_size(filename) < 1 -> {:error, :invalid_filename}
      byte_size(filename) > 255 -> {:error, :filename_too_long}
      String.contains?(filename, ["/", "\\"]) -> {:error, :invalid_filename}
      true -> :ok
    end
  end

  defp validate_filename(_), do: {:error, :invalid_filename}

  defp validate_extension(filename) do
    ext =
      filename
      |> String.downcase()
      |> Path.extname()

    if ext in @allowed_extensions do
      :ok
    else
      {:error, :invalid_extension}
    end
  end

  defp get_config do
    bucket = System.get_env("UPLOADS_BUCKET")
    region = System.get_env("UPLOADS_REGION") || System.get_env("AWS_REGION")

    if bucket && region do
      max_size_mb =
        System.get_env("UPLOADS_MAX_SIZE_MB", "50")
        |> String.to_integer()

      presigned_url_expiry =
        System.get_env("UPLOADS_PRESIGNED_URL_EXPIRY", "3600")
        |> String.to_integer()

      {:ok,
       %{
         bucket: bucket,
         region: region,
         max_size_bytes: max_size_mb * 1024 * 1024,
         presigned_url_expiry: presigned_url_expiry
       }}
    else
      {:error, :not_configured}
    end
  end

  defp generate_key(user_id, filename) do
    # Sanitize filename
    safe_filename =
      filename
      |> Path.basename()
      |> String.replace(~r/[^a-zA-Z0-9._-]/, "_")

    timestamp = DateTime.utc_now() |> DateTime.to_unix()
    random_suffix = :crypto.strong_rand_bytes(4) |> Base.encode16(case: :lower)

    "users/#{user_id}/uploads/#{timestamp}_#{random_suffix}_#{safe_filename}"
  end

  defp extract_filename(key) do
    key
    |> String.split("/")
    |> List.last()
    # Remove timestamp and random prefix
    |> String.replace(~r/^\d+_[a-f0-9]+_/, "")
  end

  # ==========================================================================
  # S3 Operations (using AWS SDK via Req + SigV4)
  # ==========================================================================

  defp generate_presigned_post(bucket, region, key, content_type, expires_in, max_size) do
    # Generate presigned POST URL with policy conditions
    # Using a simplified approach compatible with AWS S3

    expiration =
      DateTime.utc_now()
      |> DateTime.add(expires_in)
      |> DateTime.to_iso8601()

    # Build the policy
    policy = %{
      expiration: expiration,
      conditions: [
        %{bucket: bucket},
        ["eq", "$key", key],
        ["eq", "$Content-Type", content_type],
        ["content-length-range", 0, max_size],
        ["eq", "$x-amz-server-side-encryption", "aws:kms"]
      ]
    }

    policy_base64 = Jason.encode!(policy) |> Base.encode64()

    # Get credentials and sign the policy
    case get_aws_credentials() do
      {:ok, credentials} ->
        amz_date = amz_date_now()
        date_stamp = String.slice(amz_date, 0, 8)
        credential_scope = "#{date_stamp}/#{region}/s3/aws4_request"
        credential = "#{credentials.access_key_id}/#{credential_scope}"

        string_to_sign = policy_base64

        signing_key =
          compute_signing_key(
            credentials.secret_access_key,
            date_stamp,
            region,
            "s3"
          )

        signature =
          :crypto.mac(:hmac, :sha256, signing_key, string_to_sign)
          |> Base.encode16(case: :lower)

        fields = %{
          "key" => key,
          "Content-Type" => content_type,
          "x-amz-server-side-encryption" => "aws:kms",
          "x-amz-algorithm" => "AWS4-HMAC-SHA256",
          "x-amz-credential" => credential,
          "x-amz-date" => amz_date,
          "policy" => policy_base64,
          "x-amz-signature" => signature
        }

        fields =
          if credentials.session_token do
            Map.put(fields, "x-amz-security-token", credentials.session_token)
          else
            fields
          end

        url = "https://#{bucket}.s3.#{region}.amazonaws.com"

        {:ok, %{url: url, fields: fields}}

      {:error, _} = error ->
        error
    end
  end

  defp generate_presigned_get(bucket, region, key, expires_in) do
    # Generate presigned GET URL using AWS SigV4
    case get_aws_credentials() do
      {:ok, credentials} ->
        host = "#{bucket}.s3.#{region}.amazonaws.com"
        amz_date = amz_date_now()
        date_stamp = String.slice(amz_date, 0, 8)

        credential_scope = "#{date_stamp}/#{region}/s3/aws4_request"
        credential = "#{credentials.access_key_id}/#{credential_scope}"

        # Build query parameters
        query_params =
          [
            {"X-Amz-Algorithm", "AWS4-HMAC-SHA256"},
            {"X-Amz-Credential", credential},
            {"X-Amz-Date", amz_date},
            {"X-Amz-Expires", to_string(expires_in)},
            {"X-Amz-SignedHeaders", "host"}
          ]
          |> maybe_add_token(credentials.session_token)
          |> Enum.sort()

        query_string =
          Enum.map_join(query_params, "&", fn {k, v} ->
            "#{URI.encode_www_form(k)}=#{URI.encode_www_form(v)}"
          end)

        # Create canonical request
        encoded_key = encode_uri_path(key)

        canonical_request = """
        GET
        /#{encoded_key}
        #{query_string}
        host:#{host}

        host
        UNSIGNED-PAYLOAD\
        """

        # Create string to sign
        string_to_sign = """
        AWS4-HMAC-SHA256
        #{amz_date}
        #{credential_scope}
        #{hash(canonical_request)}\
        """

        # Calculate signature
        signing_key =
          compute_signing_key(
            credentials.secret_access_key,
            date_stamp,
            region,
            "s3"
          )

        signature =
          :crypto.mac(:hmac, :sha256, signing_key, string_to_sign)
          |> Base.encode16(case: :lower)

        url = "https://#{host}/#{encoded_key}?#{query_string}&X-Amz-Signature=#{signature}"

        {:ok, url}

      {:error, _} = error ->
        error
    end
  end

  defp s3_delete_object(bucket, region, key) do
    case get_aws_credentials() do
      {:ok, credentials} ->
        host = "#{bucket}.s3.#{region}.amazonaws.com"
        url = "https://#{host}/#{encode_uri_path(key)}"

        headers = sign_request("DELETE", url, host, region, credentials)

        case http_client().delete(url, headers: headers) do
          {:ok, %{status: status}} when status in 200..299 ->
            {:ok, :deleted}

          {:ok, %{status: 404}} ->
            {:ok, :not_found}

          {:ok, %{status: status, body: body}} ->
            {:error, %{status_code: status, body: body}}

          {:error, reason} ->
            {:error, reason}
        end

      {:error, _} = error ->
        error
    end
  end

  defp s3_list_objects(bucket, region, prefix, max_keys, continuation_token) do
    case get_aws_credentials() do
      {:ok, credentials} ->
        host = "#{bucket}.s3.#{region}.amazonaws.com"

        query_params =
          [
            {"list-type", "2"},
            {"prefix", prefix},
            {"max-keys", to_string(max_keys)}
          ]
          |> maybe_add_continuation_token(continuation_token)

        query_string =
          Enum.map_join(query_params, "&", fn {k, v} ->
            "#{URI.encode_www_form(k)}=#{URI.encode_www_form(v)}"
          end)

        url = "https://#{host}/?#{query_string}"

        headers = sign_request("GET", url, host, region, credentials)

        case http_client().get(url, headers: headers) do
          {:ok, %{status: 200, body: body}} ->
            {:ok, parse_list_objects_response(body)}

          {:ok, %{status: status, body: body}} ->
            {:error, %{status_code: status, body: body}}

          {:error, reason} ->
            {:error, reason}
        end

      {:error, _} = error ->
        error
    end
  end

  defp s3_head_object(bucket, region, key) do
    case get_aws_credentials() do
      {:ok, credentials} ->
        host = "#{bucket}.s3.#{region}.amazonaws.com"
        url = "https://#{host}/#{encode_uri_path(key)}"

        headers = sign_request("HEAD", url, host, region, credentials)

        case http_client().head(url, headers: headers) do
          {:ok, %{status: 200, headers: resp_headers}} ->
            {:ok, parse_head_response(resp_headers)}

          {:ok, %{status: 404}} ->
            {:error, %{status_code: 404}}

          {:ok, %{status: status, body: body}} ->
            {:error, %{status_code: status, body: body}}

          {:error, reason} ->
            {:error, reason}
        end

      {:error, _} = error ->
        error
    end
  end

  # ==========================================================================
  # AWS Credential and Signing Helpers
  # ==========================================================================

  defp get_aws_credentials do
    # Try environment variables first, then instance metadata
    access_key = System.get_env("AWS_ACCESS_KEY_ID")
    secret_key = System.get_env("AWS_SECRET_ACCESS_KEY")
    session_token = System.get_env("AWS_SESSION_TOKEN")

    if access_key && secret_key do
      {:ok,
       %{
         access_key_id: access_key,
         secret_access_key: secret_key,
         session_token: session_token
       }}
    else
      # Try to get credentials from instance metadata (ECS task role)
      get_instance_credentials()
    end
  end

  defp get_instance_credentials do
    # Try ECS task role credentials endpoint
    uri = System.get_env("AWS_CONTAINER_CREDENTIALS_RELATIVE_URI")

    if uri do
      url = "http://169.254.170.2#{uri}"

      case http_client().get(url, []) do
        {:ok, %{status: 200, body: body}} when is_map(body) ->
          {:ok,
           %{
             access_key_id: body["AccessKeyId"],
             secret_access_key: body["SecretAccessKey"],
             session_token: body["Token"]
           }}

        _ ->
          {:error, :no_credentials}
      end
    else
      {:error, :no_credentials}
    end
  end

  defp sign_request(method, url, host, region, credentials) do
    amz_date = amz_date_now()
    date_stamp = String.slice(amz_date, 0, 8)

    uri = URI.parse(url)
    path = uri.path || "/"
    query = uri.query || ""

    canonical_headers = "host:#{host}\nx-amz-date:#{amz_date}\n"
    signed_headers = "host;x-amz-date"

    payload_hash = "UNSIGNED-PAYLOAD"

    canonical_request = """
    #{method}
    #{path}
    #{query}
    #{canonical_headers}
    #{signed_headers}
    #{payload_hash}\
    """

    credential_scope = "#{date_stamp}/#{region}/s3/aws4_request"

    string_to_sign = """
    AWS4-HMAC-SHA256
    #{amz_date}
    #{credential_scope}
    #{hash(canonical_request)}\
    """

    signing_key =
      compute_signing_key(
        credentials.secret_access_key,
        date_stamp,
        region,
        "s3"
      )

    signature =
      :crypto.mac(:hmac, :sha256, signing_key, string_to_sign)
      |> Base.encode16(case: :lower)

    auth_header =
      "AWS4-HMAC-SHA256 Credential=#{credentials.access_key_id}/#{credential_scope}, SignedHeaders=#{signed_headers}, Signature=#{signature}"

    headers = [
      {"Authorization", auth_header},
      {"x-amz-date", amz_date},
      {"x-amz-content-sha256", payload_hash}
    ]

    if credentials.session_token do
      [{"x-amz-security-token", credentials.session_token} | headers]
    else
      headers
    end
  end

  defp compute_signing_key(secret_key, date_stamp, region, service) do
    ("AWS4" <> secret_key)
    |> hmac_sha256(date_stamp)
    |> hmac_sha256(region)
    |> hmac_sha256(service)
    |> hmac_sha256("aws4_request")
  end

  defp hmac_sha256(key, data) do
    :crypto.mac(:hmac, :sha256, key, data)
  end

  defp hash(data) do
    :crypto.hash(:sha256, data)
    |> Base.encode16(case: :lower)
  end

  defp amz_date_now do
    DateTime.utc_now()
    |> Calendar.strftime("%Y%m%dT%H%M%SZ")
  end

  defp encode_uri_path(path) do
    path
    |> String.split("/")
    |> Enum.map_join("/", &URI.encode_www_form/1)
  end

  defp maybe_add_token(params, nil), do: params
  defp maybe_add_token(params, token), do: params ++ [{"X-Amz-Security-Token", token}]

  defp maybe_add_continuation_token(params, nil), do: params

  defp maybe_add_continuation_token(params, token),
    do: params ++ [{"continuation-token", token}]

  defp parse_list_objects_response(body) when is_binary(body) do
    # Parse XML response - simplified parser for S3 list objects
    contents =
      Regex.scan(~r/<Contents>(.+?)<\/Contents>/s, body)
      |> Enum.map(fn [_, content] ->
        %{
          key: extract_xml_value(content, "Key"),
          size: extract_xml_value(content, "Size") |> String.to_integer(),
          last_modified: extract_xml_value(content, "LastModified")
        }
      end)

    next_token = extract_xml_value(body, "NextContinuationToken")

    %{
      contents: contents,
      next_continuation_token: if(next_token == "", do: nil, else: next_token)
    }
  end

  defp parse_list_objects_response(_body), do: %{contents: [], next_continuation_token: nil}

  defp extract_xml_value(xml, tag) do
    case Regex.run(~r/<#{tag}>(.+?)<\/#{tag}>/s, xml) do
      [_, value] -> value
      _ -> ""
    end
  end

  defp parse_head_response(headers) do
    headers_map = Map.new(headers)

    %{
      content_length:
        Map.get(headers_map, "content-length", "0")
        |> String.to_integer(),
      content_type: Map.get(headers_map, "content-type"),
      last_modified: Map.get(headers_map, "last-modified"),
      etag: Map.get(headers_map, "etag")
    }
  end

  defp http_client do
    Application.get_env(:backend, :http_client, Backend.HTTPClient.Impl)
  end
end
