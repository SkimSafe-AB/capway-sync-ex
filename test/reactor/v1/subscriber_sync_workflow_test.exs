defmodule CapwaySync.Reactor.V1.SubscriberSyncWorkflowTest do
  use ExUnit.Case, async: false
  alias CapwaySync.Reactor.V1.SubscriberSyncWorkflow

  defp steps do
    {:ok, reactor} = Reactor.Info.to_struct(SubscriberSyncWorkflow)
    Map.new(reactor.steps, &{&1.name, &1})
  end

  defp result_sources(step) do
    for %{source: %Reactor.Template.Result{name: name}} <- step.arguments, do: name
  end

  describe "action-item pipeline wiring" do
    test "suppress_known_contracts sits between compare_data and the store steps" do
      steps = steps()

      assert Map.has_key?(steps, :suppress_known_contracts)

      assert steps[:suppress_known_contracts].impl ==
               {CapwaySync.Reactor.V1.Steps.SuppressKnownContracts, []}

      # Reads the comparison result and is ordered after the contracts-table write.
      assert Enum.sort(result_sources(steps[:suppress_known_contracts])) ==
               [:compare_data, :store_capway_contracts]

      # Both consumers read the filtered result, not the raw comparison.
      assert result_sources(steps[:dynamodb_store_action_items]) == [:suppress_known_contracts]
      assert result_sources(steps[:dynamodb_store_report]) == [:suppress_known_contracts]
    end
  end
end
