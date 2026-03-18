defmodule CapwaySync.Reactor.V1.Steps.CachedCapwaySubscribersTest do
  use ExUnit.Case, async: true

  alias CapwaySync.Reactor.V1.Steps.CachedCapwaySubscribers

  setup_all do
    Code.ensure_loaded!(CachedCapwaySubscribers)
    :ok
  end

  describe "module" do
    test "compiles successfully" do
      assert Code.ensure_loaded?(CachedCapwaySubscribers)
    end

    test "implements Reactor.Step behaviour" do
      behaviours =
        CachedCapwaySubscribers.__info__(:attributes)
        |> Keyword.get_values(:behaviour)
        |> List.flatten()

      assert Reactor.Step in behaviours
    end
  end

  describe "run/3" do
    test "function exists with arity 3" do
      assert function_exported?(CachedCapwaySubscribers, :run, 3)
    end
  end

  describe "compensate/4" do
    test "function exists with arity 4" do
      assert function_exported?(CachedCapwaySubscribers, :compensate, 4)
    end
  end

  describe "undo/4" do
    test "function exists with arity 4" do
      assert function_exported?(CachedCapwaySubscribers, :undo, 4)
    end
  end
end
