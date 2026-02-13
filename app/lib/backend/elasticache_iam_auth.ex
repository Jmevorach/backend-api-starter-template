defmodule Backend.ElasticacheIamAuth do
  @moduledoc """
  AWS ElastiCache IAM Authentication token generator.

  This module generates short-lived authentication tokens for connecting
  to ElastiCache Serverless (Valkey/Redis) using IAM credentials.

  ## How It Works

  1. The ECS task has an IAM role with `elasticache:Connect` permission
  2. This module uses AWS SigV4 to generate a pre-signed URL
  3. The URL is used as the password for Valkey/Redis AUTH
  4. Tokens are valid for 15 minutes

  ## Benefits

  - No static passwords to manage or rotate
  - Credentials tied to IAM role identity
  - Automatic credential refresh via ECS task role
  - Audit trail via CloudTrail
  """

  require Logger

  # 15 minutes
  @token_ttl_seconds 900

  @doc """
  Generate an IAM authentication token for ElastiCache connection.

  ## Parameters

  - `cluster_id` - ElastiCache Serverless cache name
  - `username` - ElastiCache user ID configured for IAM auth
  - `region` - AWS region where the cache is located

  ## Returns

  - `{:ok, token}` - Authentication token string
  - `{:error, reason}` - Error if token generation fails

  ## Example

      iex> Backend.ElasticacheIamAuth.generate_token("my-cache", "app_user", "us-east-1")
      {:ok, "my-cache/?Action=connect&User=app_user&X-Amz-..."}
  """
  @spec generate_token(String.t(), String.t(), String.t()) ::
          {:ok, String.t()} | {:error, term()}
  def generate_token(cluster_id, username, region) do
    datetime = DateTime.utc_now()
    date = Calendar.strftime(datetime, "%Y%m%d")
    datetime_str = Calendar.strftime(datetime, "%Y%m%dT%H%M%SZ")

    credentials = get_credentials()

    # Build the canonical request for ElastiCache IAM auth
    canonical_querystring = build_querystring(username, datetime_str, credentials, region, date)

    canonical_request = build_canonical_request(cluster_id, canonical_querystring)
    string_to_sign = build_string_to_sign(datetime_str, date, region, canonical_request)

    signing_key = derive_signing_key(credentials.secret_access_key, date, region)
    signature = hmac_sha256_hex(signing_key, string_to_sign)

    token = "#{cluster_id}/?#{canonical_querystring}&X-Amz-Signature=#{signature}"

    {:ok, token}
  rescue
    e ->
      if Mix.env() == :test do
        Logger.debug("Failed to generate ElastiCache IAM token in test: #{inspect(e)}")
      else
        Logger.error("Failed to generate ElastiCache IAM token: #{inspect(e)}")
      end

      {:error, e}
  end

  defp get_credentials do
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
      fetch_container_credentials()
    end
  end

  defp fetch_container_credentials do
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
      {"User", username},
      {"X-Amz-Algorithm", "AWS4-HMAC-SHA256"},
      {"X-Amz-Credential",
       "#{credentials.access_key_id}/#{date}/#{region}/elasticache/aws4_request"},
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

  defp build_canonical_request(cluster_id, querystring) do
    [
      "GET",
      "/",
      querystring,
      "host:#{cluster_id}",
      "",
      "host",
      "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
    ]
    |> Enum.join("\n")
  end

  defp build_string_to_sign(datetime_str, date, region, canonical_request) do
    [
      "AWS4-HMAC-SHA256",
      datetime_str,
      "#{date}/#{region}/elasticache/aws4_request",
      sha256_hex(canonical_request)
    ]
    |> Enum.join("\n")
  end

  defp derive_signing_key(secret_key, date, region) do
    ("AWS4" <> secret_key)
    |> hmac_sha256(date)
    |> hmac_sha256(region)
    |> hmac_sha256("elasticache")
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
