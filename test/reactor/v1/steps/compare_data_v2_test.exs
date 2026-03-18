defmodule CapwaySync.Reactor.V1.Steps.CompareDataV2Test do
  use ExUnit.Case, async: true

  alias CapwaySync.Reactor.V1.Steps.CompareDataV2
  alias CapwaySync.Models.Subscribers.Canonical

  defp build_capway_sub(attrs) do
    Map.merge(
      %Canonical{
        national_id: "199001011234",
        trinity_subscriber_id: 1,
        capway_contract_ref: "C-001",
        capway_active_status: true,
        origin: :capway,
        collection: 3,
        last_invoice_status: "Invoice",
        payment_method: nil,
        trinity_status: nil,
        subscription_type: nil
      },
      attrs
    )
  end

  defp build_trinity_sub(attrs) do
    Map.merge(
      %Canonical{
        national_id: "199001011234",
        trinity_subscriber_id: 1,
        origin: :trinity,
        payment_method: "capway",
        trinity_status: :active,
        subscription_type: :standard,
        capway_active_status: nil,
        collection: nil,
        last_invoice_status: nil
      },
      attrs
    )
  end

  describe "get_accounts_to_suspend_or_cancel/3" do
    test "cancels subscriber with collection >= 2 and unpaid invoice" do
      capway_sub = build_capway_sub(%{collection: 3, last_invoice_status: "Invoice"})
      trinity_sub = build_trinity_sub(%{})

      capway_data = %{"C-001" => capway_sub}
      trinity_data = %{1 => trinity_sub}
      trinity_map_set = %{active_national_ids: MapSet.new(["199001011234"])}

      {suspend, cancel} =
        CompareDataV2.get_accounts_to_suspend_or_cancel(capway_data, trinity_data, trinity_map_set)

      assert map_size(cancel) == 1
      assert map_size(suspend) == 0
      assert Map.has_key?(cancel, "C-001")
    end

    test "excludes subscriber with last_invoice_status Paid from cancel" do
      capway_sub = build_capway_sub(%{collection: 3, last_invoice_status: "Paid"})
      trinity_sub = build_trinity_sub(%{})

      capway_data = %{"C-001" => capway_sub}
      trinity_data = %{1 => trinity_sub}
      trinity_map_set = %{active_national_ids: MapSet.new(["199001011234"])}

      {suspend, cancel} =
        CompareDataV2.get_accounts_to_suspend_or_cancel(capway_data, trinity_data, trinity_map_set)

      assert map_size(cancel) == 0
      assert map_size(suspend) == 0
    end

    test "suspends locked subscriber even with Paid invoice" do
      capway_sub = build_capway_sub(%{collection: 3, last_invoice_status: "Paid"})
      trinity_sub = build_trinity_sub(%{subscription_type: :locked})

      capway_data = %{"C-001" => capway_sub}
      trinity_data = %{1 => trinity_sub}
      trinity_map_set = %{active_national_ids: MapSet.new(["199001011234"])}

      {suspend, cancel} =
        CompareDataV2.get_accounts_to_suspend_or_cancel(capway_data, trinity_data, trinity_map_set)

      assert map_size(suspend) == 1
      assert map_size(cancel) == 0
      assert Map.has_key?(suspend, "C-001")
    end

    test "excludes pending_cancel subscriber from cancel" do
      capway_sub = build_capway_sub(%{collection: 3, last_invoice_status: "Invoice"})
      trinity_sub = build_trinity_sub(%{trinity_status: :pending_cancel})

      capway_data = %{"C-001" => capway_sub}
      trinity_data = %{1 => trinity_sub}
      trinity_map_set = %{active_national_ids: MapSet.new(["199001011234"])}

      {suspend, cancel} =
        CompareDataV2.get_accounts_to_suspend_or_cancel(capway_data, trinity_data, trinity_map_set)

      assert map_size(cancel) == 0
      assert map_size(suspend) == 0
    end

    test "excludes non-capway payment method from cancel" do
      capway_sub = build_capway_sub(%{collection: 3, last_invoice_status: "Reminder"})
      trinity_sub = build_trinity_sub(%{payment_method: "invoice"})

      capway_data = %{"C-001" => capway_sub}
      trinity_data = %{1 => trinity_sub}
      trinity_map_set = %{active_national_ids: MapSet.new(["199001011234"])}

      {suspend, cancel} =
        CompareDataV2.get_accounts_to_suspend_or_cancel(capway_data, trinity_data, trinity_map_set)

      assert map_size(cancel) == 0
      assert map_size(suspend) == 0
    end

    test "cancels subscriber with Collection Agency status" do
      capway_sub = build_capway_sub(%{collection: 4, last_invoice_status: "Collection Agency"})
      trinity_sub = build_trinity_sub(%{})

      capway_data = %{"C-001" => capway_sub}
      trinity_data = %{1 => trinity_sub}
      trinity_map_set = %{active_national_ids: MapSet.new(["199001011234"])}

      {suspend, cancel} =
        CompareDataV2.get_accounts_to_suspend_or_cancel(capway_data, trinity_data, trinity_map_set)

      assert map_size(cancel) == 1
      assert map_size(suspend) == 0
    end

    test "cancels subscriber with Reminder status" do
      capway_sub = build_capway_sub(%{collection: 2, last_invoice_status: "Reminder"})
      trinity_sub = build_trinity_sub(%{})

      capway_data = %{"C-001" => capway_sub}
      trinity_data = %{1 => trinity_sub}
      trinity_map_set = %{active_national_ids: MapSet.new(["199001011234"])}

      {suspend, cancel} =
        CompareDataV2.get_accounts_to_suspend_or_cancel(capway_data, trinity_data, trinity_map_set)

      assert map_size(cancel) == 1
      assert map_size(suspend) == 0
    end

    test "two active contracts for same customer produce two separate action items" do
      capway_sub_1 =
        build_capway_sub(%{
          capway_contract_ref: "C-001",
          collection: 3,
          last_invoice_status: "Invoice"
        })

      capway_sub_2 =
        build_capway_sub(%{
          capway_contract_ref: "C-002",
          collection: 4,
          last_invoice_status: "Reminder"
        })

      trinity_sub = build_trinity_sub(%{})

      capway_data = %{"C-001" => capway_sub_1, "C-002" => capway_sub_2}
      trinity_data = %{1 => trinity_sub}
      trinity_map_set = %{active_national_ids: MapSet.new(["199001011234"])}

      {suspend, cancel} =
        CompareDataV2.get_accounts_to_suspend_or_cancel(capway_data, trinity_data, trinity_map_set)

      assert map_size(cancel) == 2
      assert map_size(suspend) == 0
      assert Map.has_key?(cancel, "C-001")
      assert Map.has_key?(cancel, "C-002")
    end

    test "two locked contracts produce two separate suspend action items" do
      capway_sub_1 =
        build_capway_sub(%{
          capway_contract_ref: "C-001",
          collection: 3
        })

      capway_sub_2 =
        build_capway_sub(%{
          capway_contract_ref: "C-002",
          collection: 2
        })

      trinity_sub = build_trinity_sub(%{subscription_type: :locked})

      capway_data = %{"C-001" => capway_sub_1, "C-002" => capway_sub_2}
      trinity_data = %{1 => trinity_sub}
      trinity_map_set = %{active_national_ids: MapSet.new(["199001011234"])}

      {suspend, cancel} =
        CompareDataV2.get_accounts_to_suspend_or_cancel(capway_data, trinity_data, trinity_map_set)

      assert map_size(suspend) == 2
      assert map_size(cancel) == 0
      assert Map.has_key?(suspend, "C-001")
      assert Map.has_key?(suspend, "C-002")
    end

    test "action item includes capway_contract_ref" do
      capway_sub = build_capway_sub(%{collection: 3, capway_contract_ref: "C-999"})
      trinity_sub = build_trinity_sub(%{subscription_type: :locked})

      capway_data = %{"C-999" => capway_sub}
      trinity_data = %{1 => trinity_sub}
      trinity_map_set = %{active_national_ids: MapSet.new(["199001011234"])}

      {suspend, _cancel} =
        CompareDataV2.get_accounts_to_suspend_or_cancel(capway_data, trinity_data, trinity_map_set)

      action_item = Map.get(suspend, "C-999")
      assert action_item.capway_contract_ref == "C-999"
      assert action_item.trinity_subscriber_id == 1
      assert action_item.national_id == "199001011234"
    end

    test "excludes already suspended subscriber" do
      capway_sub = build_capway_sub(%{collection: 3, last_invoice_status: "Invoice"})
      trinity_sub = build_trinity_sub(%{trinity_status: :suspended})

      capway_data = %{"C-001" => capway_sub}
      trinity_data = %{1 => trinity_sub}
      trinity_map_set = %{active_national_ids: MapSet.new(["199001011234"])}

      {suspend, cancel} =
        CompareDataV2.get_accounts_to_suspend_or_cancel(capway_data, trinity_data, trinity_map_set)

      assert map_size(suspend) == 0
      assert map_size(cancel) == 0
    end

    test "excludes already cancelled subscriber" do
      capway_sub = build_capway_sub(%{collection: 3, last_invoice_status: "Invoice"})
      trinity_sub = build_trinity_sub(%{trinity_status: :cancelled})

      capway_data = %{"C-001" => capway_sub}
      trinity_data = %{1 => trinity_sub}
      trinity_map_set = %{active_national_ids: MapSet.new(["199001011234"])}

      {suspend, cancel} =
        CompareDataV2.get_accounts_to_suspend_or_cancel(capway_data, trinity_data, trinity_map_set)

      assert map_size(suspend) == 0
      assert map_size(cancel) == 0
    end

    test "excludes suspended subscriber even with locked subscription" do
      capway_sub = build_capway_sub(%{collection: 3})
      trinity_sub = build_trinity_sub(%{subscription_type: :locked, trinity_status: :suspended})

      capway_data = %{"C-001" => capway_sub}
      trinity_data = %{1 => trinity_sub}
      trinity_map_set = %{active_national_ids: MapSet.new(["199001011234"])}

      {suspend, cancel} =
        CompareDataV2.get_accounts_to_suspend_or_cancel(capway_data, trinity_data, trinity_map_set)

      assert map_size(suspend) == 0
      assert map_size(cancel) == 0
    end
  end

  describe "get_contracts_to_update/2" do
    test "marks contract for update when national_id differs and trinity pnr is valid" do
      capway_sub = build_capway_sub(%{national_id: "198507099805", trinity_subscriber_id: 1})
      trinity_sub = build_trinity_sub(%{national_id: "196403273813"})

      capway_data = %{"C-001" => capway_sub}
      trinity_data = %{1 => trinity_sub}

      result = CompareDataV2.get_contracts_to_update(capway_data, trinity_data)

      assert map_size(result) == 1
      assert Map.has_key?(result, "C-001")
    end

    test "does not mark contract for update when national_ids match" do
      capway_sub = build_capway_sub(%{national_id: "196403273813", trinity_subscriber_id: 1})
      trinity_sub = build_trinity_sub(%{national_id: "196403273813"})

      capway_data = %{"C-001" => capway_sub}
      trinity_data = %{1 => trinity_sub}

      result = CompareDataV2.get_contracts_to_update(capway_data, trinity_data)

      assert map_size(result) == 0
    end

    test "does not mark contract for update when trinity national_id is invalid personnummer" do
      capway_sub = build_capway_sub(%{national_id: "198507099805", trinity_subscriber_id: 1})
      trinity_sub = build_trinity_sub(%{national_id: "invalid_pnr"})

      capway_data = %{"C-001" => capway_sub}
      trinity_data = %{1 => trinity_sub}

      result = CompareDataV2.get_contracts_to_update(capway_data, trinity_data)

      assert map_size(result) == 0
    end

    test "does not mark contract for update when trinity national_id is nil" do
      capway_sub = build_capway_sub(%{national_id: "196403273813", trinity_subscriber_id: 1})
      trinity_sub = build_trinity_sub(%{national_id: nil})

      capway_data = %{"C-001" => capway_sub}
      trinity_data = %{1 => trinity_sub}

      result = CompareDataV2.get_contracts_to_update(capway_data, trinity_data)

      assert map_size(result) == 0
    end

    test "does not match when capway trinity_subscriber_id is nil" do
      capway_sub =
        build_capway_sub(%{
          national_id: "196403273813",
          trinity_subscriber_id: nil,
          capway_contract_ref: "C-001"
        })

      trinity_sub = build_trinity_sub(%{national_id: "196403273813"})

      capway_data = %{"C-001" => capway_sub}
      trinity_data = %{1 => trinity_sub}

      result = CompareDataV2.get_contracts_to_update(capway_data, trinity_data)

      # No match because Map.has_key?(trinity_data, nil) is false
      assert map_size(result) == 0
    end
  end

  describe "get_contracts_to_cancel/2" do
    test "cancels contract with no matching trinity_subscriber_id" do
      capway_sub =
        build_capway_sub(%{
          trinity_subscriber_id: 9999,
          capway_contract_ref: "C-orphan"
        })

      trinity_sub = build_trinity_sub(%{})

      capway_data = %{"C-orphan" => capway_sub}
      trinity_data = %{1 => trinity_sub}

      result = CompareDataV2.get_contracts_to_cancel(capway_data, trinity_data)

      assert map_size(result) == 1
      assert Map.has_key?(result, "C-orphan")
    end

    test "does not cancel contract when matched by trinity_subscriber_id" do
      capway_sub = build_capway_sub(%{trinity_subscriber_id: 1, capway_contract_ref: "C-001"})
      trinity_sub = build_trinity_sub(%{})

      capway_data = %{"C-001" => capway_sub}
      trinity_data = %{1 => trinity_sub}

      result = CompareDataV2.get_contracts_to_cancel(capway_data, trinity_data)

      assert map_size(result) == 0
    end

    test "cancels contract even if national_id matches but trinity_subscriber_id does not" do
      capway_sub =
        build_capway_sub(%{
          trinity_subscriber_id: 9999,
          national_id: "199001011234",
          capway_contract_ref: "C-001"
        })

      trinity_sub = build_trinity_sub(%{})

      capway_data = %{"C-001" => capway_sub}
      trinity_data = %{1 => trinity_sub}

      result = CompareDataV2.get_contracts_to_cancel(capway_data, trinity_data)

      assert map_size(result) == 1
    end
  end

  describe "exclude_existing_by_national_id/2" do
    test "removes create action when national_id exists in capway active national ids" do
      action_item = %CapwaySync.Models.Dynamodb.ActionItem{
        national_id: "196403273813",
        trinity_subscriber_id: 1,
        capway_contract_ref: nil,
        action: :capway_create_contract,
        status: :pending
      }

      create_contracts = %{1 => action_item}
      capway_map_sets = %{active_national_ids: MapSet.new(["196403273813"])}

      result = CompareDataV2.exclude_existing_by_national_id(create_contracts, capway_map_sets)

      assert map_size(result) == 0
    end

    test "keeps create action when national_id does not exist in capway" do
      action_item = %CapwaySync.Models.Dynamodb.ActionItem{
        national_id: "196403273813",
        trinity_subscriber_id: 1,
        capway_contract_ref: nil,
        action: :capway_create_contract,
        status: :pending
      }

      create_contracts = %{1 => action_item}
      capway_map_sets = %{active_national_ids: MapSet.new(["198507099805"])}

      result = CompareDataV2.exclude_existing_by_national_id(create_contracts, capway_map_sets)

      assert map_size(result) == 1
      assert Map.has_key?(result, 1)
    end

    test "filters mixed results correctly" do
      existing_item = %CapwaySync.Models.Dynamodb.ActionItem{
        national_id: "196403273813",
        trinity_subscriber_id: 1,
        action: :capway_create_contract,
        status: :pending
      }

      new_item = %CapwaySync.Models.Dynamodb.ActionItem{
        national_id: "198507099805",
        trinity_subscriber_id: 2,
        action: :capway_create_contract,
        status: :pending
      }

      create_contracts = %{1 => existing_item, 2 => new_item}
      capway_map_sets = %{active_national_ids: MapSet.new(["196403273813"])}

      result = CompareDataV2.exclude_existing_by_national_id(create_contracts, capway_map_sets)

      assert map_size(result) == 1
      assert Map.has_key?(result, 2)
    end

    test "returns empty map when all are excluded" do
      item1 = %CapwaySync.Models.Dynamodb.ActionItem{
        national_id: "196403273813",
        trinity_subscriber_id: 1,
        action: :capway_create_contract,
        status: :pending
      }

      item2 = %CapwaySync.Models.Dynamodb.ActionItem{
        national_id: "198507099805",
        trinity_subscriber_id: 2,
        action: :capway_create_contract,
        status: :pending
      }

      create_contracts = %{1 => item1, 2 => item2}

      capway_map_sets = %{
        active_national_ids: MapSet.new(["196403273813", "198507099805"])
      }

      result = CompareDataV2.exclude_existing_by_national_id(create_contracts, capway_map_sets)

      assert map_size(result) == 0
    end

    test "handles empty create_contracts" do
      capway_map_sets = %{active_national_ids: MapSet.new(["196403273813"])}

      result = CompareDataV2.exclude_existing_by_national_id(%{}, capway_map_sets)

      assert map_size(result) == 0
    end
  end
end
