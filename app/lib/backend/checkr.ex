defmodule Backend.Checkr do
  @moduledoc """
  Checkr API client for background checks.

  This module provides an interface to the Checkr API for running background
  checks on candidates. It supports the full workflow: create candidate,
  send invitation, and retrieve reports.

  ## Configuration

  Set the following environment variables:

    * `CHECKR_API_KEY` - Your Checkr API key (from dashboard)
    * `CHECKR_ENVIRONMENT` - `sandbox` (default) or `production`

  In production, these should be injected via AWS Secrets Manager.

  ## Workflow

  The typical background check workflow is:

  1. Create a candidate with their basic information
  2. Create an invitation to start the background check process
  3. The candidate receives an email and completes the authorization
  4. Poll or use webhooks to get the report status and results

  ## Usage

      # Create a candidate
      {:ok, candidate} = Backend.Checkr.create_candidate(%{
        first_name: "John",
        last_name: "Doe",
        email: "john@example.com"
      })

      # Create an invitation (sends email to candidate)
      {:ok, invitation} = Backend.Checkr.create_invitation(%{
        candidate_id: candidate["id"],
        package: "tasker_standard"
      })

      # Later, retrieve the report
      {:ok, report} = Backend.Checkr.get_report(report_id)

  ## Error Handling

  All functions return `{:ok, result}` on success or `{:error, reason}` on failure.
  """

  require Logger

  @sandbox_url "https://api.checkr-staging.com/v1"
  @production_url "https://api.checkr.com/v1"

  # Candidate Operations

  @doc """
  Creates a new candidate for background checks.

  ## Parameters

    * `params` - Map containing candidate details:
      * `:first_name` - Candidate's first name (required)
      * `:last_name` - Candidate's last name (required)
      * `:email` - Candidate's email address (required for invitations)
      * `:phone` - Candidate's phone number
      * `:dob` - Date of birth (YYYY-MM-DD format)
      * `:ssn` - Social Security Number (last 4 digits or full)
      * `:zipcode` - Candidate's zipcode
      * `:work_locations` - List of work location objects

  ## Examples

      {:ok, candidate} = Backend.Checkr.create_candidate(%{
        first_name: "John",
        last_name: "Doe",
        email: "john@example.com",
        dob: "1990-01-15",
        zipcode: "94107"
      })
  """
  @spec create_candidate(map()) :: {:ok, map()} | {:error, term()}
  def create_candidate(params) do
    post("/candidates", params)
  end

  @doc """
  Retrieves a candidate by ID.

  ## Examples

      {:ok, candidate} = Backend.Checkr.get_candidate("abc123")
  """
  @spec get_candidate(String.t()) :: {:ok, map()} | {:error, term()}
  def get_candidate(candidate_id) do
    get("/candidates/#{candidate_id}")
  end

  @doc """
  Lists candidates with optional filtering.

  ## Parameters

    * `params` - Optional map containing:
      * `:per_page` - Number of candidates per page (default 25, max 100)
      * `:page` - Page number (default 1)
      * `:email` - Filter by email

  ## Examples

      {:ok, %{"data" => candidates}} = Backend.Checkr.list_candidates(%{per_page: 10})
  """
  @spec list_candidates(map()) :: {:ok, map()} | {:error, term()}
  def list_candidates(params \\ %{}) do
    get("/candidates", params)
  end

  # Invitation Operations

  @doc """
  Creates an invitation to start the background check process.

  This sends an email to the candidate with a link to provide consent
  and additional information required for the background check.

  ## Parameters

    * `params` - Map containing:
      * `:candidate_id` - ID of the candidate (required)
      * `:package` - Background check package slug (required)
      * `:work_locations` - Optional list of work location objects

  ## Available Packages (common ones)

    * `tasker_standard` - Standard background check
    * `driver_standard` - Driver background check with MVR
    * `basic_criminal` - Basic criminal check only
    * `pro` - Professional background check

  Use `list_packages/0` to see all available packages for your account.

  ## Examples

      {:ok, invitation} = Backend.Checkr.create_invitation(%{
        candidate_id: "abc123",
        package: "tasker_standard"
      })
  """
  @spec create_invitation(map()) :: {:ok, map()} | {:error, term()}
  def create_invitation(params) do
    post("/invitations", params)
  end

  @doc """
  Retrieves an invitation by ID.
  """
  @spec get_invitation(String.t()) :: {:ok, map()} | {:error, term()}
  def get_invitation(invitation_id) do
    get("/invitations/#{invitation_id}")
  end

  @doc """
  Lists invitations with optional filtering.
  """
  @spec list_invitations(map()) :: {:ok, map()} | {:error, term()}
  def list_invitations(params \\ %{}) do
    get("/invitations", params)
  end

  @doc """
  Cancels a pending invitation.
  """
  @spec cancel_invitation(String.t()) :: {:ok, map()} | {:error, term()}
  def cancel_invitation(invitation_id) do
    delete("/invitations/#{invitation_id}")
  end

  # Report Operations

  @doc """
  Creates a report directly (bypasses invitation flow).

  Note: This requires the candidate to have already provided consent.
  In most cases, you should use `create_invitation/1` instead.

  ## Parameters

    * `params` - Map containing:
      * `:candidate_id` - ID of the candidate (required)
      * `:package` - Background check package slug (required)
  """
  @spec create_report(map()) :: {:ok, map()} | {:error, term()}
  def create_report(params) do
    post("/reports", params)
  end

  @doc """
  Retrieves a report by ID.

  The report contains the status and results of the background check.

  ## Report Statuses

    * `pending` - Report is being processed
    * `clear` - No adverse information found
    * `consider` - Adverse information found, review recommended
    * `suspended` - Report suspended (usually needs more info)
    * `dispute` - Candidate disputed the results

  ## Examples

      {:ok, report} = Backend.Checkr.get_report("report_abc123")
  """
  @spec get_report(String.t()) :: {:ok, map()} | {:error, term()}
  def get_report(report_id) do
    get("/reports/#{report_id}")
  end

  @doc """
  Lists reports with optional filtering.

  ## Parameters

    * `params` - Optional map containing:
      * `:per_page` - Number of reports per page
      * `:page` - Page number
      * `:candidate_id` - Filter by candidate
      * `:status` - Filter by status
  """
  @spec list_reports(map()) :: {:ok, map()} | {:error, term()}
  def list_reports(params \\ %{}) do
    get("/reports", params)
  end

  # Package Operations

  @doc """
  Lists available background check packages for your account.

  Each package defines what screenings are included (criminal, MVR,
  employment verification, etc.) and their pricing.

  ## Examples

      {:ok, %{"data" => packages}} = Backend.Checkr.list_packages()
  """
  @spec list_packages() :: {:ok, map()} | {:error, term()}
  def list_packages do
    get("/packages")
  end

  @doc """
  Retrieves a specific package by slug.
  """
  @spec get_package(String.t()) :: {:ok, map()} | {:error, term()}
  def get_package(package_slug) do
    get("/packages/#{package_slug}")
  end

  # Screening Operations

  @doc """
  Retrieves details of a specific screening within a report.

  Screenings are individual checks within a report (e.g., SSN trace,
  criminal search, MVR).
  """
  @spec get_screening(String.t()) :: {:ok, map()} | {:error, term()}
  def get_screening(screening_id) do
    get("/screenings/#{screening_id}")
  end

  # Webhook signature verification

  @doc """
  Verifies a Checkr webhook signature.

  ## Parameters

    * `payload` - Raw request body
    * `signature` - Value of `X-Checkr-Signature` header
    * `webhook_secret` - Your webhook signing secret

  ## Examples

      case Backend.Checkr.verify_webhook_signature(body, sig_header, secret) do
        {:ok, event} -> handle_event(event)
        {:error, _} -> {:error, :invalid_signature}
      end
  """
  @spec verify_webhook_signature(String.t(), String.t(), String.t()) ::
          {:ok, map()} | {:error, term()}
  def verify_webhook_signature(payload, signature, webhook_secret) do
    computed_sig =
      :crypto.mac(:hmac, :sha256, webhook_secret, payload)
      |> Base.encode16(case: :lower)

    if secure_compare(computed_sig, signature) do
      case Jason.decode(payload) do
        {:ok, event} -> {:ok, event}
        {:error, _} -> {:error, :invalid_payload}
      end
    else
      {:error, :invalid_signature}
    end
  end

  # Private helper functions

  defp get(path, params \\ %{}) do
    request(:get, path, params)
  end

  defp post(path, params) do
    request(:post, path, params)
  end

  defp delete(path) do
    request(:delete, path, %{})
  end

  defp request(method, path, params) do
    case get_api_key() do
      nil ->
        {:error, :api_key_not_configured}

      api_key ->
        url = base_url() <> path

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

        result = apply(http_client(), method, [url, opts])

        case result do
          {:ok, %{status: status, body: body}} when status in 200..299 ->
            {:ok, body}

          {:ok, %{status: _status, body: %{"error" => error}}} ->
            Logger.warning("Checkr API error: #{inspect(error)}")
            {:error, error}

          {:ok, %{status: status, body: body}} ->
            Logger.warning("Checkr API unexpected response: #{status} - #{inspect(body)}")
            {:error, {:unexpected_status, status, body}}

          {:error, reason} ->
            Logger.error("Checkr API request failed: #{inspect(reason)}")
            {:error, reason}
        end
    end
  end

  defp get_api_key do
    Application.get_env(:backend, :checkr)[:api_key]
  end

  defp http_client do
    Application.get_env(:backend, :http_client, Backend.HTTPClient.Impl)
  end

  defp base_url do
    environment = Application.get_env(:backend, :checkr)[:environment] || "sandbox"

    case environment do
      "production" -> @production_url
      _ -> @sandbox_url
    end
  end

  # Constant-time string comparison to prevent timing attacks
  defp secure_compare(a, b) when byte_size(a) != byte_size(b), do: false

  defp secure_compare(a, b) do
    a_bytes = :binary.bin_to_list(a)
    b_bytes = :binary.bin_to_list(b)

    result =
      Enum.zip(a_bytes, b_bytes)
      |> Enum.reduce(0, fn {x, y}, acc -> Bitwise.bor(acc, Bitwise.bxor(x, y)) end)

    result == 0
  end
end
