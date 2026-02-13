ExUnit.start()

# Start the application
{:ok, _} = Application.ensure_all_started(:backend)

# Configure Mox for API client testing
Mox.defmock(Backend.HTTPClientMock, for: Backend.HTTPClient)

# Set the mock as the default HTTP client in test environment
Application.put_env(:backend, :http_client, Backend.HTTPClientMock)

# Configure Ecto sandbox for concurrent tests if database is available
# This allows tests to run even without a database connection
try do
  Ecto.Adapters.SQL.Sandbox.mode(Backend.Repo, :manual)
rescue
  DBConnection.ConnectionError ->
    IO.puts("\n⚠️  Database not available - some tests may be skipped or degraded")
catch
  :exit, _ ->
    IO.puts("\n⚠️  Database not available - some tests may be skipped or degraded")
end
