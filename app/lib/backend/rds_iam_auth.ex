defmodule Backend.RdsIamAuth do
  @moduledoc """
  AWS RDS IAM Authentication token generator.

  This module generates short-lived authentication tokens for connecting
  to RDS/Aurora databases via RDS Proxy using IAM credentials.

  ## How It Works

  1. The ECS task has an IAM role with `rds-db:connect` permission
  2. This module uses AWS SDK to generate a pre-signed URL
  3. The URL (minus scheme) is used as the password for PostgreSQL
  4. Tokens are valid for 15 minutes

  ## Benefits

  - No static passwords to manage or rotate
  - Credentials tied to IAM role identity
  - Automatic credential refresh via ECS task role
  - Audit trail via CloudTrail
  """

  require Logger

  # 15 minutes (RDS IAM token lifetime)
  @token_ttl_seconds 900

  @doc """
  Generate an IAM authentication token for RDS connection.

  ## Parameters

  - `hostname` - RDS Proxy or database endpoint hostname
  - `port` - Database port (usually 5432 for PostgreSQL)
  - `username` - Database username configured for IAM auth
  - `region` - AWS region where the database is located

  ## Returns

  - `{:ok, token}` - Authentication token string
  - `{:error, reason}` - Error if token generation fails

  ## Example

      iex> Backend.RdsIamAuth.generate_token("my-proxy.proxy-xxx.us-east-1.rds.amazonaws.com", 5432, "app_user", "us-east-1")
      {:ok, "my-proxy.proxy-xxx.us-east-1.rds.amazonaws.com:5432/?Action=connect&DBUser=app_user&X-Amz-..."}
  """
  @spec generate_token(String.t(), integer(), String.t(), String.t()) ::
          {:ok, String.t()} | {:error, term()}
  def generate_token(hostname, port, username, region) do
    # Build the canonical request for RDS IAM auth
    # This is a pre-signed URL that RDS accepts as a password
    datetime = DateTime.utc_now()
    date = Calendar.strftime(datetime, "%Y%m%d")
    datetime_str = Calendar.strftime(datetime, "%Y%m%dT%H%M%SZ")

    # Get AWS credentials from environment/instance metadata
    credentials = get_credentials()

    # Construct the request to sign
    host_port = "#{hostname}:#{port}"
    canonical_uri = "/"
    canonical_querystring = build_querystring(username, datetime_str, credentials, region, date)

    # Create the string to sign
    canonical_request = build_canonical_request(host_port, canonical_uri, canonical_querystring)
    string_to_sign = build_string_to_sign(datetime_str, date, region, canonical_request)

    # Calculate the signature
    signing_key = derive_signing_key(credentials.secret_access_key, date, region)
    signature = hmac_sha256_hex(signing_key, string_to_sign)

    # Build the final token
    token = "#{host_port}/?#{canonical_querystring}&X-Amz-Signature=#{signature}"

    {:ok, token}
  rescue
    e ->
      Logger.error("Failed to generate RDS IAM token: #{inspect(e)}")
      {:error, e}
  end

  defp get_credentials do
    # Try environment variables first, then instance metadata
    access_key = System.get_env("AWS_ACCESS_KEY_ID")
    secret_key = System.get_env("AWS_SECRET_ACCESS_KEY")
    session_token = System.get_env("AWS_SESSION_TOKEN")

    if access_key && secret_key do
      %{
        access_key_id: access_key,
        secret_access_key: secret_key,
        session_token: session_token
      }
    else
      # Fetch from ECS task role via container credentials
      fetch_container_credentials()
    end
  end

  defp fetch_container_credentials do
    # ECS injects credentials via AWS_CONTAINER_CREDENTIALS_RELATIVE_URI
    relative_uri = System.get_env("AWS_CONTAINER_CREDENTIALS_RELATIVE_URI")

    if relative_uri do
      url = "http://169.254.170.2#{relative_uri}"

      case :httpc.request(:get, {String.to_charlist(url), []}, [], []) do
        {:ok, {{_, 200, _}, _, body}} ->
          creds = Jason.decode!(to_string(body))

          %{
            access_key_id: creds["AccessKeyId"],
            secret_access_key: creds["SecretAccessKey"],
            session_token: creds["Token"]
          }

        error ->
          raise "Failed to fetch ECS credentials: #{inspect(error)}"
      end
    else
      raise "No AWS credentials available"
    end
  end

  defp build_querystring(username, datetime_str, credentials, region, date) do
    params = [
      {"Action", "connect"},
      {"DBUser", username},
      {"X-Amz-Algorithm", "AWS4-HMAC-SHA256"},
      {"X-Amz-Credential", "#{credentials.access_key_id}/#{date}/#{region}/rds-db/aws4_request"},
      {"X-Amz-Date", datetime_str},
      {"X-Amz-Expires", to_string(@token_ttl_seconds)}
    ]

    params =
      if credentials.session_token do
        params ++ [{"X-Amz-Security-Token", credentials.session_token}]
      else
        params
      end

    params
    |> Enum.sort_by(fn {k, _} -> k end)
    |> Enum.map_join("&", fn {k, v} -> "#{URI.encode(k)}=#{URI.encode(v)}" end)
  end

  defp build_canonical_request(host, uri, querystring) do
    [
      "GET",
      uri,
      querystring,
      "host:#{host}",
      "",
      "host",
      # SHA256 of empty string
      "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
    ]
    |> Enum.join("\n")
  end

  defp build_string_to_sign(datetime_str, date, region, canonical_request) do
    [
      "AWS4-HMAC-SHA256",
      datetime_str,
      "#{date}/#{region}/rds-db/aws4_request",
      sha256_hex(canonical_request)
    ]
    |> Enum.join("\n")
  end

  defp derive_signing_key(secret_key, date, region) do
    ("AWS4" <> secret_key)
    |> hmac_sha256(date)
    |> hmac_sha256(region)
    |> hmac_sha256("rds-db")
    |> hmac_sha256("aws4_request")
  end

  defp hmac_sha256(key, data) do
    :crypto.mac(:hmac, :sha256, key, data)
  end

  defp hmac_sha256_hex(key, data) do
    hmac_sha256(key, data) |> Base.encode16(case: :lower)
  end

  defp sha256_hex(data) do
    :crypto.hash(:sha256, data) |> Base.encode16(case: :lower)
  end
end
