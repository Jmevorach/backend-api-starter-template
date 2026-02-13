defmodule Backend.ApplicationTest do
  @moduledoc """
  Tests for the Backend.Application module.
  """

  use ExUnit.Case, async: true

  describe "application configuration" do
    test "application is started" do
      # The application should be running during tests
      assert Application.started_applications()
             |> Enum.any?(fn {app, _, _} -> app == :backend end)
    end

    test "repo is started" do
      # Check that Repo process is running
      assert Process.whereis(Backend.Repo) != nil
    end

    test "endpoint is started" do
      # Check that Endpoint is running
      assert Process.whereis(BackendWeb.Endpoint) != nil
    end

    test "pubsub can broadcast" do
      # Test that PubSub is functional by subscribing and broadcasting
      Phoenix.PubSub.subscribe(Backend.PubSub, "test:topic")
      Phoenix.PubSub.broadcast(Backend.PubSub, "test:topic", {:test, "message"})

      assert_receive {:test, "message"}, 1000
    end
  end

  describe "children/0" do
    test "returns a list of child specs" do
      # We can't call children/0 directly as it's private,
      # but we can verify the supervisor has the expected children
      children = Supervisor.which_children(Backend.Supervisor)

      assert is_list(children)
      assert children != []
    end

    test "supervisor contains required children" do
      children = Supervisor.which_children(Backend.Supervisor)
      child_ids = Enum.map(children, fn {id, _, _, _} -> id end)

      # Must have Repo
      assert Backend.Repo in child_ids

      # Must have Endpoint
      assert BackendWeb.Endpoint in child_ids
    end
  end

  describe "start/2" do
    test "application module exports start/2" do
      assert function_exported?(Backend.Application, :start, 2)
    end
  end

  describe "config_change/3" do
    test "config_change/3 is exported" do
      assert function_exported?(Backend.Application, :config_change, 3)
    end

    test "config_change/3 returns :ok" do
      # Call config_change with empty changes
      result = Backend.Application.config_change([], [], [])
      assert result == :ok
    end

    test "config_change/3 handles changes" do
      # Simulate a config change event
      changed = [{:backend, [some: :config]}]
      removed = [:old_key]

      result = Backend.Application.config_change(changed, [], removed)
      assert result == :ok
    end
  end

  describe "supervision tree" do
    test "supervisor uses one_for_one strategy" do
      # Get supervisor state - the structure depends on OTP version
      state = :sys.get_state(Backend.Supervisor)

      # The strategy is in the state tuple
      assert elem(state, 2) == :one_for_one
    end

    test "supervisor name is Backend.Supervisor" do
      assert Process.whereis(Backend.Supervisor) != nil
    end
  end
end
