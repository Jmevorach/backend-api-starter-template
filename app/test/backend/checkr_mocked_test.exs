defmodule Backend.CheckrMockedTest do
  @moduledoc """
  Mocked tests for the Checkr API client.

  These tests use Mox to mock HTTP responses with realistic Checkr API
  response formats, allowing us to test all code paths without making real
  API calls.

  API response formats are based on:
  https://docs.checkr.com/
  """

  use ExUnit.Case, async: true

  import Mox

  alias Backend.Checkr

  # Make sure mocks are verified when the test exits
  setup :verify_on_exit!

  setup do
    # Configure API key for tests
    Application.put_env(:backend, :checkr,
      api_key: "test_api_key_mock",
      environment: :sandbox
    )

    on_exit(fn ->
      Application.delete_env(:backend, :checkr)
    end)

    :ok
  end

  # ===========================================================================
  # Realistic API Response Fixtures (based on Checkr API docs)
  # ===========================================================================

  defp candidate_response(overrides \\ %{}) do
    Map.merge(
      %{
        "id" => "e44aa283528e6fde7d542194",
        "object" => "candidate",
        "uri" => "/v1/candidates/e44aa283528e6fde7d542194",
        "created_at" => "2014-01-18T12:34:00Z",
        "first_name" => "John",
        "middle_name" => "Alfred",
        "last_name" => "Smith",
        "email" => "john.smith@example.com",
        "phone" => "5555555555",
        "zipcode" => "90401",
        "dob" => "1990-01-15",
        "ssn" => "XXX-XX-1234",
        "driver_license_number" => "F1234567",
        "driver_license_state" => "CA",
        "previous_driver_license_number" => nil,
        "previous_driver_license_state" => nil,
        "copy_requested" => false,
        "custom_id" => nil,
        "report_ids" => [],
        "geo_ids" => [],
        "adjudication" => nil,
        "metadata" => %{},
        "work_locations" => [
          %{
            "country" => "US",
            "state" => "CA",
            "city" => "San Francisco"
          }
        ]
      },
      overrides
    )
  end

  defp candidates_list_response(candidates \\ []) do
    %{
      "object" => "list",
      "next_href" => nil,
      "previous_href" => nil,
      "count" => length(candidates),
      "data" => candidates
    }
  end

  defp invitation_response(overrides \\ %{}) do
    Map.merge(
      %{
        "id" => "5b409f7b3e66c400014a1c1f",
        "object" => "invitation",
        "uri" => "/v1/invitations/5b409f7b3e66c400014a1c1f",
        "status" => "pending",
        "created_at" => "2018-07-07T17:29:47Z",
        "completed_at" => nil,
        "deleted_at" => nil,
        "expires_at" => "2018-07-14T17:29:47Z",
        "invitation_url" => "https://checkr.com/invitation/abc123",
        "package" => "tasker_standard",
        "candidate_id" => "e44aa283528e6fde7d542194"
      },
      overrides
    )
  end

  defp invitations_list_response(invitations \\ []) do
    %{
      "object" => "list",
      "next_href" => nil,
      "previous_href" => nil,
      "count" => length(invitations),
      "data" => invitations
    }
  end

  defp report_response(overrides \\ %{}) do
    Map.merge(
      %{
        "id" => "4722c07dd9a10c3985ae432a",
        "object" => "report",
        "uri" => "/v1/reports/4722c07dd9a10c3985ae432a",
        "status" => "complete",
        "result" => "clear",
        "created_at" => "2014-01-18T12:34:00Z",
        "completed_at" => "2014-01-18T12:35:00Z",
        "revised_at" => nil,
        "turnaround_time" => 60,
        "due_time" => "2014-01-20T12:34:00Z",
        "adjudication" => nil,
        "package" => "tasker_standard",
        "candidate_id" => "e44aa283528e6fde7d542194",
        "ssn_trace_id" => "539fd88c101897f7cd000001",
        "sex_offender_search_id" => "539fd88c101897f7cd000002",
        "national_criminal_search_id" => "539fd88c101897f7cd000003",
        "county_criminal_search_ids" => ["539fd88c101897f7cd000004"],
        "motor_vehicle_report_id" => nil,
        "federal_criminal_search_id" => nil,
        "document_ids" => [],
        "geo_ids" => [],
        "program_id" => nil,
        "estimated_completion_time" => nil
      },
      overrides
    )
  end

  defp reports_list_response(reports \\ []) do
    %{
      "object" => "list",
      "next_href" => nil,
      "previous_href" => nil,
      "count" => length(reports),
      "data" => reports
    }
  end

  defp package_response(overrides \\ %{}) do
    Map.merge(
      %{
        "id" => "tasker_standard",
        "object" => "package",
        "name" => "Tasker Standard",
        "slug" => "tasker_standard",
        "price" => 3500,
        "screenings" => [
          %{
            "type" => "ssn_trace",
            "subtype" => nil
          },
          %{
            "type" => "sex_offender_search",
            "subtype" => nil
          },
          %{
            "type" => "national_criminal_search",
            "subtype" => nil
          }
        ]
      },
      overrides
    )
  end

  defp screening_response(overrides \\ %{}) do
    Map.merge(
      %{
        "id" => "539fd88c101897f7cd000001",
        "object" => "ssn_trace",
        "uri" => "/v1/ssn_traces/539fd88c101897f7cd000001",
        "status" => "complete",
        "result" => "clear",
        "created_at" => "2014-01-18T12:34:00Z",
        "completed_at" => "2014-01-18T12:35:00Z",
        "turnaround_time" => 60,
        "ssn" => "XXX-XX-1234",
        "addresses" => [
          %{
            "street" => "123 Main St",
            "unit" => nil,
            "city" => "San Francisco",
            "state" => "CA",
            "zipcode" => "94102",
            "county" => "San Francisco",
            "from_date" => "2010-01-01",
            "to_date" => "2014-01-01"
          }
        ]
      },
      overrides
    )
  end

  defp error_response(message) do
    %{
      "error" => message
    }
  end

  defp deleted_response(id, type) do
    %{
      "id" => id,
      "object" => type,
      "deleted" => true
    }
  end

  # ===========================================================================
  # Candidate Tests
  # ===========================================================================

  describe "create_candidate/1 with mocked responses" do
    test "creates candidate successfully" do
      Backend.HTTPClientMock
      |> expect(:post, fn url, opts ->
        assert url =~ "api.checkr-staging.com/v1/candidates"
        assert opts[:auth] == {:basic, "test_api_key_mock:"}
        assert opts[:json][:first_name] == "John"
        assert opts[:json][:last_name] == "Smith"
        assert opts[:json][:email] == "john.smith@example.com"

        {:ok, %{status: 201, body: candidate_response()}}
      end)

      result =
        Checkr.create_candidate(%{
          first_name: "John",
          last_name: "Smith",
          email: "john.smith@example.com"
        })

      assert {:ok, candidate} = result
      assert candidate["id"] == "e44aa283528e6fde7d542194"
      assert candidate["first_name"] == "John"
      assert candidate["last_name"] == "Smith"
      assert candidate["email"] == "john.smith@example.com"
    end

    test "creates candidate with all fields" do
      Backend.HTTPClientMock
      |> expect(:post, fn _url, opts ->
        json = opts[:json]
        assert json[:dob] == "1990-01-15"
        assert json[:ssn] == "1234"
        assert json[:zipcode] == "94107"
        assert json[:work_locations]

        {:ok, %{status: 201, body: candidate_response()}}
      end)

      result =
        Checkr.create_candidate(%{
          first_name: "John",
          last_name: "Smith",
          email: "john@example.com",
          dob: "1990-01-15",
          ssn: "1234",
          zipcode: "94107",
          work_locations: [
            %{country: "US", state: "CA", city: "San Francisco"}
          ]
        })

      assert {:ok, _candidate} = result
    end

    test "handles validation error" do
      Backend.HTTPClientMock
      |> expect(:post, fn _url, _opts ->
        {:ok, %{status: 400, body: error_response("Email is invalid")}}
      end)

      result =
        Checkr.create_candidate(%{first_name: "John", last_name: "Smith", email: "invalid"})

      assert {:error, "Email is invalid"} = result
    end
  end

  describe "get_candidate/1 with mocked responses" do
    test "retrieves candidate successfully" do
      Backend.HTTPClientMock
      |> expect(:get, fn url, _opts ->
        assert url =~ "api.checkr-staging.com/v1/candidates/e44aa283528e6fde7d542194"

        {:ok, %{status: 200, body: candidate_response()}}
      end)

      result = Checkr.get_candidate("e44aa283528e6fde7d542194")

      assert {:ok, candidate} = result
      assert candidate["id"] == "e44aa283528e6fde7d542194"
    end

    test "handles candidate not found" do
      Backend.HTTPClientMock
      |> expect(:get, fn _url, _opts ->
        {:ok, %{status: 404, body: error_response("Candidate not found")}}
      end)

      result = Checkr.get_candidate("nonexistent")

      assert {:error, "Candidate not found"} = result
    end
  end

  describe "list_candidates/1 with mocked responses" do
    test "lists candidates successfully" do
      Backend.HTTPClientMock
      |> expect(:get, fn url, opts ->
        assert url =~ "api.checkr-staging.com/v1/candidates"
        assert opts[:params][:per_page] == 25

        {:ok, %{status: 200, body: candidates_list_response([candidate_response()])}}
      end)

      result = Checkr.list_candidates(%{per_page: 25})

      assert {:ok, response} = result
      assert response["object"] == "list"
      assert length(response["data"]) == 1
    end

    test "lists candidates with default params" do
      Backend.HTTPClientMock
      |> expect(:get, fn _url, _opts ->
        {:ok, %{status: 200, body: candidates_list_response([])}}
      end)

      result = Checkr.list_candidates()

      assert {:ok, response} = result
      assert response["data"] == []
    end
  end

  # ===========================================================================
  # Invitation Tests
  # ===========================================================================

  describe "create_invitation/1 with mocked responses" do
    test "creates invitation successfully" do
      Backend.HTTPClientMock
      |> expect(:post, fn url, opts ->
        assert url =~ "api.checkr-staging.com/v1/invitations"
        assert opts[:json][:candidate_id] == "e44aa283528e6fde7d542194"
        assert opts[:json][:package] == "tasker_standard"

        {:ok, %{status: 201, body: invitation_response()}}
      end)

      result =
        Checkr.create_invitation(%{
          candidate_id: "e44aa283528e6fde7d542194",
          package: "tasker_standard"
        })

      assert {:ok, invitation} = result
      assert invitation["id"]
      assert invitation["invitation_url"]
      assert invitation["status"] == "pending"
    end

    test "creates invitation with work locations" do
      Backend.HTTPClientMock
      |> expect(:post, fn _url, opts ->
        assert opts[:json][:work_locations]

        {:ok, %{status: 201, body: invitation_response()}}
      end)

      result =
        Checkr.create_invitation(%{
          candidate_id: "e44aa283528e6fde7d542194",
          package: "driver_standard",
          work_locations: [
            %{country: "US", state: "CA"},
            %{country: "US", state: "NY"}
          ]
        })

      assert {:ok, _invitation} = result
    end
  end

  describe "get_invitation/1 with mocked responses" do
    test "retrieves invitation successfully" do
      Backend.HTTPClientMock
      |> expect(:get, fn url, _opts ->
        assert url =~ "api.checkr-staging.com/v1/invitations/5b409f7b3e66c400014a1c1f"

        {:ok, %{status: 200, body: invitation_response()}}
      end)

      result = Checkr.get_invitation("5b409f7b3e66c400014a1c1f")

      assert {:ok, invitation} = result
      assert invitation["id"] == "5b409f7b3e66c400014a1c1f"
    end
  end

  describe "cancel_invitation/1 with mocked responses" do
    test "cancels invitation successfully" do
      Backend.HTTPClientMock
      |> expect(:delete, fn url, _opts ->
        assert url =~ "api.checkr-staging.com/v1/invitations/5b409f7b3e66c400014a1c1f"

        {:ok, %{status: 200, body: deleted_response("5b409f7b3e66c400014a1c1f", "invitation")}}
      end)

      result = Checkr.cancel_invitation("5b409f7b3e66c400014a1c1f")

      assert {:ok, response} = result
      assert response["deleted"] == true
    end
  end

  describe "list_invitations/1 with mocked responses" do
    test "lists invitations successfully" do
      Backend.HTTPClientMock
      |> expect(:get, fn url, _opts ->
        assert url =~ "api.checkr-staging.com/v1/invitations"

        {:ok, %{status: 200, body: invitations_list_response([invitation_response()])}}
      end)

      result = Checkr.list_invitations()

      assert {:ok, response} = result
      assert response["object"] == "list"
      assert length(response["data"]) == 1
    end
  end

  # ===========================================================================
  # Report Tests
  # ===========================================================================

  describe "create_report/1 with mocked responses" do
    test "creates report successfully" do
      Backend.HTTPClientMock
      |> expect(:post, fn url, opts ->
        assert url =~ "api.checkr-staging.com/v1/reports"
        assert opts[:json][:candidate_id] == "e44aa283528e6fde7d542194"
        assert opts[:json][:package] == "tasker_standard"

        {:ok, %{status: 201, body: report_response()}}
      end)

      result =
        Checkr.create_report(%{
          candidate_id: "e44aa283528e6fde7d542194",
          package: "tasker_standard"
        })

      assert {:ok, report} = result
      assert report["id"] == "4722c07dd9a10c3985ae432a"
      assert report["status"] == "complete"
      assert report["result"] == "clear"
    end
  end

  describe "get_report/1 with mocked responses" do
    test "retrieves report successfully" do
      Backend.HTTPClientMock
      |> expect(:get, fn url, _opts ->
        assert url =~ "api.checkr-staging.com/v1/reports/4722c07dd9a10c3985ae432a"

        {:ok, %{status: 200, body: report_response()}}
      end)

      result = Checkr.get_report("4722c07dd9a10c3985ae432a")

      assert {:ok, report} = result
      assert report["id"] == "4722c07dd9a10c3985ae432a"
    end

    test "handles report not found" do
      Backend.HTTPClientMock
      |> expect(:get, fn _url, _opts ->
        {:ok, %{status: 404, body: error_response("Report not found")}}
      end)

      result = Checkr.get_report("nonexistent")

      assert {:error, "Report not found"} = result
    end
  end

  describe "list_reports/1 with mocked responses" do
    test "lists reports successfully" do
      Backend.HTTPClientMock
      |> expect(:get, fn url, opts ->
        assert url =~ "api.checkr-staging.com/v1/reports"
        assert opts[:params][:candidate_id] == "e44aa283528e6fde7d542194"

        {:ok, %{status: 200, body: reports_list_response([report_response()])}}
      end)

      result = Checkr.list_reports(%{candidate_id: "e44aa283528e6fde7d542194"})

      assert {:ok, response} = result
      assert length(response["data"]) == 1
    end

    test "lists reports with status filter" do
      Backend.HTTPClientMock
      |> expect(:get, fn _url, opts ->
        assert opts[:params][:status] == "clear"

        {:ok, %{status: 200, body: reports_list_response([])}}
      end)

      result = Checkr.list_reports(%{status: "clear"})

      assert {:ok, _response} = result
    end
  end

  # ===========================================================================
  # Package Tests
  # ===========================================================================

  describe "list_packages/0 with mocked responses" do
    test "lists packages successfully" do
      Backend.HTTPClientMock
      |> expect(:get, fn url, _opts ->
        assert url =~ "api.checkr-staging.com/v1/packages"

        {:ok,
         %{
           status: 200,
           body: %{
             "object" => "list",
             "data" => [package_response()]
           }
         }}
      end)

      result = Checkr.list_packages()

      assert {:ok, response} = result
      assert length(response["data"]) == 1
    end
  end

  describe "get_package/1 with mocked responses" do
    test "retrieves package successfully" do
      Backend.HTTPClientMock
      |> expect(:get, fn url, _opts ->
        assert url =~ "api.checkr-staging.com/v1/packages/tasker_standard"

        {:ok, %{status: 200, body: package_response()}}
      end)

      result = Checkr.get_package("tasker_standard")

      assert {:ok, package} = result
      assert package["id"] == "tasker_standard"
      assert package["name"] == "Tasker Standard"
      assert is_list(package["screenings"])
    end
  end

  # ===========================================================================
  # Screening Tests
  # ===========================================================================

  describe "get_screening/1 with mocked responses" do
    test "retrieves screening successfully" do
      Backend.HTTPClientMock
      |> expect(:get, fn url, _opts ->
        assert url =~ "api.checkr-staging.com/v1/screenings/539fd88c101897f7cd000001"

        {:ok, %{status: 200, body: screening_response()}}
      end)

      result = Checkr.get_screening("539fd88c101897f7cd000001")

      assert {:ok, screening} = result
      assert screening["id"] == "539fd88c101897f7cd000001"
      assert screening["status"] == "complete"
      assert screening["result"] == "clear"
    end
  end

  # ===========================================================================
  # Environment Configuration Tests
  # ===========================================================================

  describe "environment configuration" do
    test "uses sandbox URL in sandbox environment" do
      Backend.HTTPClientMock
      |> expect(:get, fn url, _opts ->
        assert url =~ "api.checkr-staging.com"

        {:ok, %{status: 200, body: candidate_response()}}
      end)

      Checkr.get_candidate("test_id")
    end

    test "uses production URL in production environment" do
      Application.put_env(:backend, :checkr,
        api_key: "test_api_key_mock",
        environment: "production"
      )

      Backend.HTTPClientMock
      |> expect(:get, fn url, _opts ->
        assert url =~ "api.checkr.com"
        refute url =~ "staging"

        {:ok, %{status: 200, body: candidate_response()}}
      end)

      Checkr.get_candidate("test_id")
    end
  end

  # ===========================================================================
  # Error Handling Tests
  # ===========================================================================

  describe "error handling" do
    test "handles authentication error (401)" do
      Backend.HTTPClientMock
      |> expect(:get, fn _url, _opts ->
        {:ok, %{status: 401, body: error_response("Bad authentication error")}}
      end)

      result = Checkr.get_candidate("test_id")

      assert {:error, "Bad authentication error"} = result
    end

    test "handles rate limiting (429)" do
      Backend.HTTPClientMock
      |> expect(:get, fn _url, _opts ->
        {:ok, %{status: 429, body: error_response("Rate limit exceeded")}}
      end)

      result = Checkr.get_candidate("test_id")

      assert {:error, "Rate limit exceeded"} = result
    end

    test "handles network error" do
      Backend.HTTPClientMock
      |> expect(:get, fn _url, _opts ->
        {:error, %Req.TransportError{reason: :timeout}}
      end)

      result = Checkr.get_candidate("test_id")

      assert {:error, %Req.TransportError{reason: :timeout}} = result
    end

    test "handles unexpected status code" do
      Backend.HTTPClientMock
      |> expect(:get, fn _url, _opts ->
        {:ok, %{status: 503, body: "Service Unavailable"}}
      end)

      result = Checkr.get_candidate("test_id")

      assert {:error, {:unexpected_status, 503, _body}} = result
    end
  end
end
