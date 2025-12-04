defmodule CapwaySync.Reactor.V1.Steps.CompareDataCancelTest do
  use ExUnit.Case, async: true
  alias CapwaySync.Reactor.V1.Steps.CompareData
  alias CapwaySync.Models.Subscribers.Canonical

  describe "find_missing_items/4 with cancel_capway_contracts logic" do
    test "identifies contracts that need cancellation" do
      # Trinity subscribers with mixed payment methods
      trinity_list = [
        %Canonical{
          id_number: "199001012345",
          trinity_id: 123,
          payment_method: "capway",
          active: true,
          origin: :trinity
        },
        %Canonical{
          id_number: "199002023456",
          trinity_id: 124,
          payment_method: "bank", # Changed from capway
          active: true,
          origin: :trinity
        },
        %Canonical{
          id_number: "199003034567",
          trinity_id: 125,
          payment_method: "card", # Changed from capway
          active: true,
          origin: :trinity
        },
        %Canonical{
          id_number: "199004045678",
          trinity_id: 126,
          payment_method: "bank", # Was never capway
          active: true,
          origin: :trinity
        }
      ]

      # Capway has contracts for first 3 subscribers
      capway_list = [
        %Canonical{
          id_number: "199001012345",
          capway_id: "cap_123",
          active: true,
          origin: :capway
        },
        %Canonical{
          id_number: "199002023456",
          capway_id: "cap_124",
          active: true,
          origin: :capway
        },
        %Canonical{
          id_number: "199003034567",
          capway_id: "cap_125",
          active: true,
          origin: :capway
        }
      ]

      result = CompareData.find_missing_items(trinity_list, capway_list, :id_number, :id_number)

      # Should identify 2 contracts for cancellation (bank and card payment methods)
      assert result.cancel_capway_contracts_count == 2

      cancel_ids = Enum.map(result.cancel_capway_contracts, & &1.id_number)
      assert "199002023456" in cancel_ids # bank payment method
      assert "199003034567" in cancel_ids # card payment method

      # Should NOT include the one with capway payment method
      refute "199001012345" in cancel_ids

      # Should NOT include the one that doesn't exist in Capway
      refute "199004045678" in cancel_ids

      # Missing in Capway should only include Trinity subscribers with payment_method == "capway"
      assert result.missing_capway_count == 0 # 199001012345 exists in both systems

      # Missing in Trinity should include Capway subscribers not in Trinity
      assert result.missing_trinity_count == 0 # All Capway subscribers exist in Trinity

      # Existing in both should include all intersections
      assert result.existing_in_both_count == 3
    end

    test "handles no contracts needing cancellation" do
      # All Trinity subscribers have capway payment method
      trinity_list = [
        %Canonical{
          id_number: "199001012345",
          trinity_id: 123,
          payment_method: "capway",
          origin: :trinity
        },
        %Canonical{
          id_number: "199002023456",
          trinity_id: 124,
          payment_method: "capway",
          origin: :trinity
        }
      ]

      capway_list = [
        %Canonical{
          id_number: "199001012345",
          capway_id: "cap_123",
          origin: :capway
        },
        %Canonical{
          id_number: "199002023456",
          capway_id: "cap_124",
          origin: :capway
        }
      ]

      result = CompareData.find_missing_items(trinity_list, capway_list, :id_number, :id_number)

      assert result.cancel_capway_contracts_count == 0
      assert result.cancel_capway_contracts == []
      assert result.missing_capway_count == 0
      assert result.existing_in_both_count == 2
    end

    test "handles Trinity subscribers with non-capway payment methods that don't exist in Capway" do
      trinity_list = [
        %Canonical{
          id_number: "199001012345",
          trinity_id: 123,
          payment_method: "bank",
          origin: :trinity
        }
      ]

      capway_list = []

      result = CompareData.find_missing_items(trinity_list, capway_list, :id_number, :id_number)

      # No cancellations needed since subscriber doesn't exist in Capway
      assert result.cancel_capway_contracts_count == 0
      assert result.cancel_capway_contracts == []

      # No missing in Capway since payment method is not "capway"
      assert result.missing_capway_count == 0
    end

    test "correctly filters missing_in_capway to only include capway payment method" do
      trinity_list = [
        %Canonical{
          id_number: "199001012345",
          trinity_id: 123,
          payment_method: "capway", # Should be added to Capway
          origin: :trinity
        },
        %Canonical{
          id_number: "199002023456",
          trinity_id: 124,
          payment_method: "bank", # Should NOT be added to Capway
          origin: :trinity
        }
      ]

      capway_list = []

      result = CompareData.find_missing_items(trinity_list, capway_list, :id_number, :id_number)

      # Only the capway payment method subscriber should be missing in Capway
      assert result.missing_capway_count == 1
      missing_ids = Enum.map(result.missing_in_capway, & &1.id_number)
      assert "199001012345" in missing_ids
      refute "199002023456" in missing_ids

      # No cancellations since neither exists in Capway
      assert result.cancel_capway_contracts_count == 0
    end
  end
end