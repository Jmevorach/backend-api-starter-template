defmodule BackendWebTest do
  @moduledoc """
  Tests for the BackendWeb module macros.
  """

  use ExUnit.Case, async: true

  # Define test modules that use the BackendWeb macros
  # This exercises the __using__/1 macro at compile time
  defmodule TestController do
    use BackendWeb, :controller
  end

  defmodule TestRouter do
    use BackendWeb, :router
  end

  defmodule TestChannel do
    use BackendWeb, :channel
  end

  describe "controller/0" do
    test "returns a quoted expression" do
      result = BackendWeb.controller()

      assert is_tuple(result)
      assert elem(result, 0) == :__block__
    end

    test "quoted expression contains Phoenix.Controller use" do
      {:__block__, _, expressions} = BackendWeb.controller()

      # Should contain use Phoenix.Controller
      assert Enum.any?(expressions, fn expr ->
               match?({:use, _, [{:__aliases__, _, [:Phoenix, :Controller]} | _]}, expr)
             end)
    end

    test "quoted expression contains Plug.Conn import" do
      {:__block__, _, expressions} = BackendWeb.controller()

      # Should contain import Plug.Conn
      assert Enum.any?(expressions, fn expr ->
               match?({:import, _, [{:__aliases__, _, [:Plug, :Conn]}]}, expr)
             end)
    end
  end

  describe "router/0" do
    test "returns a quoted expression" do
      result = BackendWeb.router()

      assert is_tuple(result)
      assert elem(result, 0) == :__block__
    end

    test "quoted expression contains Phoenix.Router use" do
      {:__block__, _, expressions} = BackendWeb.router()

      assert Enum.any?(expressions, fn expr ->
               match?({:use, _, [{:__aliases__, _, [:Phoenix, :Router]}]}, expr)
             end)
    end
  end

  describe "channel/0" do
    test "returns a quoted expression" do
      result = BackendWeb.channel()

      assert is_tuple(result)
    end

    test "quoted expression contains Phoenix.Channel use" do
      result = BackendWeb.channel()

      # channel/0 returns a single use expression, not a block
      assert match?({:use, _, [{:__aliases__, _, [:Phoenix, :Channel]}]}, result)
    end
  end

  describe "view/0" do
    test "returns a quoted expression" do
      result = BackendWeb.view()

      assert is_tuple(result)
      assert elem(result, 0) == :__block__
    end
  end

  describe "__using__/1 macro" do
    test "dispatches to controller function" do
      # Ensure module is loaded
      Code.ensure_loaded!(BackendWeb)
      # This verifies the macro mechanism works
      assert :erlang.function_exported(BackendWeb, :controller, 0)
    end

    test "dispatches to router function" do
      Code.ensure_loaded!(BackendWeb)
      assert :erlang.function_exported(BackendWeb, :router, 0)
    end

    test "dispatches to view function" do
      Code.ensure_loaded!(BackendWeb)
      assert :erlang.function_exported(BackendWeb, :view, 0)
    end

    test "dispatches to channel function" do
      Code.ensure_loaded!(BackendWeb)
      assert :erlang.function_exported(BackendWeb, :channel, 0)
    end
  end

  describe "integration - modules using BackendWeb compile correctly" do
    test "BackendWeb.Router uses BackendWeb :router" do
      # If this module exists and compiles, the macro worked
      assert Code.ensure_loaded?(BackendWeb.Router)
    end

    test "BackendWeb.Endpoint uses Phoenix.Endpoint" do
      assert Code.ensure_loaded?(BackendWeb.Endpoint)
    end

    test "controllers use BackendWeb :controller" do
      # Check that a controller module exists
      assert Code.ensure_loaded?(BackendWeb.HealthController)
      assert Code.ensure_loaded?(BackendWeb.HomeController)
      assert Code.ensure_loaded?(BackendWeb.AuthController)
    end
  end
end
