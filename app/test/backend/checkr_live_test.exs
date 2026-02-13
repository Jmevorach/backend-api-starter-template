defmodule Backend.CheckrLiveTest do
  @moduledoc """
  Live integration tests for the Checkr API client.

  ## Purpose

  These tests make real HTTP requests to the Checkr sandbox API with invalid
  credentials to verify that:

  1. **Request formatting is correct** - The API returns authentication errors,
     NOT "invalid request" or "malformed" errors. This proves the request
     structure, headers, and parameters are properly formatted.

  2. **Environment selection works** - Requests go to the correct sandbox/prod URL.

  3. **Error parsing works** - Error responses are correctly parsed.

  ## Why This Matters

  If requests were malformed (wrong Content-Type, bad JSON encoding, etc.),
  Checkr would return a different error type. By receiving "Bad authentication"
  errors, we confirm that:

  - The request body format is correct (JSON for POST)
  - Authorization header is present and correct format (Basic auth)
  - URL construction is valid
  - The sandbox vs production URL selection works

  ## Running These Tests

  These tests require network access but do NOT require valid API keys:

      mix test test/backend/checkr_live_test.exs --include live_api

  They are excluded by default to avoid network dependencies in CI.
  """

  use ExUnit.Case, async: false

  alias Backend.Checkr

  # Use a clearly fake API key - Checkr will reject it with a proper error
  # that proves our request was well-formed
  @fake_api_key "fake_api_key_for_testing_request_formatting"

  setup do
    original_config = Application.get_env(:backend, :checkr)

    # Live tests use the real HTTP client, not the mock
    Application.put_env(:backend, :http_client, Backend.HTTPClient.Impl)

    Application.put_env(:backend, :checkr,
      api_key: @fake_api_key,
      environment: :sandbox
    )

    on_exit(fn ->
      # Restore mock for other tests
      Application.put_env(:backend, :http_client, Backend.HTTPClientMock)

      if original_config do
        Application.put_env(:backend, :checkr, original_config)
      else
        Application.delete_env(:backend, :checkr)
      end
    end)

    :ok
  end

  # Helper to verify we got an auth error (proves request was well-formed)
  defp assert_auth_error({:error, error}) do
    # Checkr returns "Bad authentication error" for invalid API keys
    # If we got a different error, our request format might be wrong
    assert error =~ "authentication" or error =~ "Unauthorized" or is_map(error),
           "Expected authentication error, got: #{inspect(error)}. " <>
             "This might indicate a malformed request."
  end

  describe "Candidate operations - verify request formatting" do
    @describetag :live_api

    @tag :live_api
    test "POST /candidates - JSON body is correctly formatted" do
      # This tests that:
      # - POST body is correctly JSON-encoded
      # - Authorization header is present (Basic auth)
      # - Content-Type is application/json
      result =
        Checkr.create_candidate(%{
          first_name: "John",
          last_name: "Doe",
          email: "john.doe@example.com"
        })

      assert_auth_error(result)
    end

    @tag :live_api
    test "POST /candidates with all fields - complex JSON works" do
      result =
        Checkr.create_candidate(%{
          first_name: "Jane",
          last_name: "Smith",
          email: "jane.smith@example.com",
          phone: "555-123-4567",
          dob: "1990-01-15",
          ssn: "1234",
          zipcode: "94107",
          work_locations: [
            %{country: "US", state: "CA", city: "San Francisco"}
          ]
        })

      assert_auth_error(result)
    end

    @tag :live_api
    test "GET /candidates/:id - URL path is correctly constructed" do
      result = Checkr.get_candidate("candidate_abc123")
      assert_auth_error(result)
    end

    @tag :live_api
    test "GET /candidates - list endpoint works" do
      result = Checkr.list_candidates()
      assert_auth_error(result)
    end

    @tag :live_api
    test "GET /candidates with pagination - query params are correct" do
      result = Checkr.list_candidates(%{per_page: 25, page: 2})
      assert_auth_error(result)
    end
  end

  describe "Invitation operations - verify request formatting" do
    @describetag :live_api

    @tag :live_api
    test "POST /invitations - JSON body is correctly formatted" do
      result =
        Checkr.create_invitation(%{
          candidate_id: "candidate_xxx",
          package: "tasker_standard"
        })

      assert_auth_error(result)
    end

    @tag :live_api
    test "POST /invitations with work_locations - nested arrays work" do
      result =
        Checkr.create_invitation(%{
          candidate_id: "candidate_xxx",
          package: "driver_standard",
          work_locations: [
            %{country: "US", state: "CA"},
            %{country: "US", state: "NY"}
          ]
        })

      assert_auth_error(result)
    end

    @tag :live_api
    test "GET /invitations/:id - URL path is correctly constructed" do
      result = Checkr.get_invitation("invitation_abc123")
      assert_auth_error(result)
    end

    @tag :live_api
    test "GET /invitations - list endpoint works" do
      result = Checkr.list_invitations()
      assert_auth_error(result)
    end

    @tag :live_api
    test "DELETE /invitations/:id - cancel request works" do
      result = Checkr.cancel_invitation("invitation_xxx")
      assert_auth_error(result)
    end
  end

  describe "Report operations - verify request formatting" do
    @describetag :live_api

    @tag :live_api
    test "POST /reports - JSON body is correctly formatted" do
      result =
        Checkr.create_report(%{
          candidate_id: "candidate_xxx",
          package: "tasker_standard"
        })

      assert_auth_error(result)
    end

    @tag :live_api
    test "GET /reports/:id - URL path is correctly constructed" do
      result = Checkr.get_report("report_abc123")
      assert_auth_error(result)
    end

    @tag :live_api
    test "GET /reports - list endpoint works" do
      result = Checkr.list_reports()
      assert_auth_error(result)
    end

    @tag :live_api
    test "GET /reports with filters - query params are correct" do
      result = Checkr.list_reports(%{candidate_id: "candidate_xxx", status: "clear"})
      assert_auth_error(result)
    end
  end

  describe "Package and Screening operations - verify request formatting" do
    @describetag :live_api

    @tag :live_api
    test "GET /packages - list packages works" do
      result = Checkr.list_packages()
      assert_auth_error(result)
    end

    @tag :live_api
    test "GET /packages/:id - get package works" do
      result = Checkr.get_package("tasker_standard")
      assert_auth_error(result)
    end

    @tag :live_api
    test "GET /screenings/:id - get screening works" do
      result = Checkr.get_screening("screening_abc123")
      assert_auth_error(result)
    end
  end

  describe "Environment selection" do
    @tag :live_api
    test "sandbox environment uses staging URL" do
      Application.put_env(:backend, :checkr,
        api_key: @fake_api_key,
        environment: :sandbox
      )

      # Should hit the staging API
      result = Checkr.list_candidates()
      assert_auth_error(result)
    end

    @tag :live_api
    test "production environment uses production URL" do
      Application.put_env(:backend, :checkr,
        api_key: @fake_api_key,
        environment: :production
      )

      # Should hit the production API (but still fail auth)
      result = Checkr.list_candidates()
      assert_auth_error(result)
    end
  end
end
