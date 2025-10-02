defmodule CapwaySync.Reactor.V1.Steps.CancelCapwayContractsTest do
  use ExUnit.Case, async: true
  alias CapwaySync.Reactor.V1.Steps.CancelCapwayContracts
  alias CapwaySync.Models.Subscribers.Canonical

  describe "run/3" do
    test "identifies contracts that need cancellation" do
      # Subscribers with payment method changed from "capway" to something else
      cancel_contracts = [
        %Canonical{
          id_number: "199001012345",
          trinity_id: 123,
          payment_method: "bank",
          origin: :trinity
        },
        %Canonical{
          id_number: "199002023456",
          trinity_id: 124,
          payment_method: "card",
          origin: :trinity
        }
      ]

      comparison_result = %{
        cancel_capway_contracts: cancel_contracts
      }

      arguments = %{comparison_result: comparison_result}

      assert {:ok, result} = CancelCapwayContracts.run(arguments, %{})

      assert result.cancel_capway_count == 2
      assert result.total_analyzed == 2
      assert length(result.cancel_capway_contracts) == 2

      # Verify the actual contracts are returned
      contract_ids = Enum.map(result.cancel_capway_contracts, & &1.id_number)
      assert "199001012345" in contract_ids
      assert "199002023456" in contract_ids
    end

    test "handles no contracts needing cancellation" do
      comparison_result = %{
        cancel_capway_contracts: []
      }

      arguments = %{comparison_result: comparison_result}

      assert {:ok, result} = CancelCapwayContracts.run(arguments, %{})

      assert result.cancel_capway_count == 0
      assert result.total_analyzed == 0
      assert result.cancel_capway_contracts == []
    end

    test "handles missing cancel_capway_contracts key" do
      comparison_result = %{}

      arguments = %{comparison_result: comparison_result}

      assert {:ok, result} = CancelCapwayContracts.run(arguments, %{})

      assert result.cancel_capway_count == 0
      assert result.total_analyzed == 0
      assert result.cancel_capway_contracts == []
    end

    test "returns error for missing comparison_result" do
      arguments = %{}

      assert {:error, "Missing required argument: comparison_result"} =
               CancelCapwayContracts.run(arguments, %{})
    end

    test "returns error for invalid comparison_result type" do
      arguments = %{comparison_result: "invalid"}

      assert {:error, "Argument comparison_result must be a map"} =
               CancelCapwayContracts.run(arguments, %{})
    end
  end

  describe "compensate/4" do
    test "returns :retry" do
      assert :retry = CancelCapwayContracts.compensate(:error, %{}, %{}, [])
    end
  end

  describe "undo/4" do
    test "returns :ok" do
      assert :ok = CancelCapwayContracts.undo(%{}, %{}, %{}, [])
    end
  end
end