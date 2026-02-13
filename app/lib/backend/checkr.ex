defmodule Backend.Checkr do
  @moduledoc """
  Checkr API client for background check workflows.
  """

  require Logger

  @sandbox_url "https://api.checkr-staging.com/v1"
  @production_url "https://api.checkr.com/v1"

  @spec create_candidate(map()) :: {:ok, map()} | {:error, term()}
  def create_candidate(params), do: post("/candidates", params)

  @spec get_candidate(String.t()) :: {:ok, map()} | {:error, term()}
  def get_candidate(candidate_id), do: get("/candidates/#{candidate_id}")

  @spec list_candidates(map()) :: {:ok, map()} | {:error, term()}
  def list_candidates(params \\ %{}), do: get("/candidates", params)

  @spec create_invitation(map()) :: {:ok, map()} | {:error, term()}
  def create_invitation(params), do: post("/invitations", params)

  @spec get_invitation(String.t()) :: {:ok, map()} | {:error, term()}
  def get_invitation(invitation_id), do: get("/invitations/#{invitation_id}")

  @spec list_invitations(map()) :: {:ok, map()} | {:error, term()}
  def list_invitations(params \\ %{}), do: get("/invitations", params)

  @spec cancel_invitation(String.t()) :: {:ok, map()} | {:error, term()}
  def cancel_invitation(invitation_id), do: delete("/invitations/#{invitation_id}")

  @spec create_report(map()) :: {:ok, map()} | {:error, term()}
  def create_report(params), do: post("/reports", params)

  @spec get_report(String.t()) :: {:ok, map()} | {:error, term()}
  def get_report(report_id), do: get("/reports/#{report_id}")

  @spec list_reports(map()) :: {:ok, map()} | {:error, term()}
  def list_reports(params \\ %{}), do: get("/reports", params)

  @spec list_packages() :: {:ok, map()} | {:error, term()}
  def list_packages, do: get("/packages")

  @spec get_package(String.t()) :: {:ok, map()} | {:error, term()}
  def get_package(package_slug), do: get("/packages/#{package_slug}")

  @spec get_screening(String.t()) :: {:ok, map()} | {:error, term()}
  def get_screening(screening_id), do: get("/screenings/#{screening_id}")

  @spec verify_webhook_signature(String.t(), String.t(), String.t()) ::
          {:ok, map()} | {:error, term()}
  def verify_webhook_signature(payload, signature, webhook_secret) do
    computed =
      :crypto.mac(:hmac, :sha256, webhook_secret, payload)
      |> Base.encode16(case: :lower)

    cond do
      not secure_compare(computed, signature) ->
        {:error, :invalid_signature}

      true ->
        case Jason.decode(payload) do
          {:ok, event} -> {:ok, event}
          {:error, _} -> {:error, :invalid_payload}
        end
    end
  end

  defp get(path, params \\ %{}), do: request(:get, path, params)
  defp post(path, params), do: request(:post, path, params)
  defp delete(path), do: request(:delete, path, %{})

  defp request(method, path, params) do
    case get_api_key() do
      nil ->
        {:error, :api_key_not_configured}

      api_key ->
        opts = [
          auth: {:basic, "#{api_key}:"},
          headers: [{"content-type", "application/json"}]
        ]

        opts =
          case method do
            :get -> Keyword.put(opts, :params, params)
            :delete -> opts
            _ -> Keyword.put(opts, :json, params)
          end

        case apply(http_client(), method, [base_url() <> path, opts]) do
          {:ok, %{status: status, body: body}} when status in 200..299 ->
            {:ok, body}

          {:ok, %{status: _status, body: %{"error" => error}}} ->
            {:error, error}

          {:ok, %{status: status, body: body}} ->
            {:error, {:unexpected_status, status, body}}

          {:error, reason} ->
            Logger.error("Checkr request failed: #{inspect(reason)}")
            {:error, reason}
        end
    end
  end

  defp get_api_key do
    Application.get_env(:backend, :checkr)[:api_key]
  end

  defp base_url do
    case Application.get_env(:backend, :checkr)[:environment] do
      "production" -> @production_url
      :production -> @production_url
      _ -> @sandbox_url
    end
  end

  defp http_client do
    Application.get_env(:backend, :http_client, Backend.HTTPClient.Impl)
  end

  defp secure_compare(a, b) when byte_size(a) != byte_size(b), do: false

  defp secure_compare(a, b) do
    a
    |> :binary.bin_to_list()
    |> Enum.zip(:binary.bin_to_list(b))
    |> Enum.reduce(0, fn {x, y}, acc -> Bitwise.bor(acc, Bitwise.bxor(x, y)) end)
    |> Kernel.==(0)
  end
end
