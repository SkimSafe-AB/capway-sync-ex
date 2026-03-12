defmodule CapwaySync.Models.Subscribers.Cannonical.HelperTest do
  use ExUnit.Case, async: true

  alias CapwaySync.Models.Subscribers.Cannonical.Helper
  alias CapwaySync.Models.Subscribers.Canonical

  defp build_capway_sub(attrs) do
    Map.merge(
      %Canonical{
        national_id: "199001011234",
        trinity_subscriber_id: 1,
        capway_contract_ref: "C-001",
        capway_active_status: true,
        origin: :capway,
        collection: 0,
        last_invoice_status: nil,
        paid_invoices: 0,
        unpaid_invoices: 0
      },
      attrs
    )
  end

  describe "group/2 :capway" do
    test "keys active_subscribers by capway_contract_ref" do
      sub = build_capway_sub(%{capway_contract_ref: "C-001"})
      result = Helper.group([sub], :capway)

      assert Map.has_key?(result.active_subscribers, "C-001")
      refute Map.has_key?(result.active_subscribers, 1)
    end

    test "two contracts with same trinity_subscriber_id are both preserved" do
      sub1 = build_capway_sub(%{capway_contract_ref: "C-001", trinity_subscriber_id: 1})
      sub2 = build_capway_sub(%{capway_contract_ref: "C-002", trinity_subscriber_id: 1})

      result = Helper.group([sub1, sub2], :capway)

      assert map_size(result.active_subscribers) == 2
      assert Map.has_key?(result.active_subscribers, "C-001")
      assert Map.has_key?(result.active_subscribers, "C-002")
    end

    test "inactive contracts are excluded from active_subscribers" do
      active = build_capway_sub(%{capway_contract_ref: "C-001", capway_active_status: true})
      inactive = build_capway_sub(%{capway_contract_ref: "C-002", capway_active_status: false})

      result = Helper.group([active, inactive], :capway)

      assert map_size(result.active_subscribers) == 1
      assert Map.has_key?(result.active_subscribers, "C-001")
    end

    test "above_collector_threshold only includes active contracts with collection >= 2" do
      active_high =
        build_capway_sub(%{capway_contract_ref: "C-001", collection: 3, capway_active_status: true})

      active_low =
        build_capway_sub(%{capway_contract_ref: "C-002", collection: 0, capway_active_status: true})

      inactive_high =
        build_capway_sub(%{
          capway_contract_ref: "C-003",
          collection: 5,
          capway_active_status: false
        })

      result = Helper.group([active_high, active_low, inactive_high], :capway)

      assert map_size(result.above_collector_threshold) == 1
      assert Map.has_key?(result.above_collector_threshold, "C-001")
    end

    test "orphaned subscribers lack trinity_subscriber_id" do
      orphan = build_capway_sub(%{trinity_subscriber_id: nil, capway_contract_ref: "C-001"})
      result = Helper.group([orphan], :capway)

      assert map_size(result.orphaned_subscribers) == 1
      assert map_size(result.associated_subscribers) == 0
    end

    test "orphaned subscribers lack capway_contract_ref" do
      orphan = build_capway_sub(%{trinity_subscriber_id: 1, capway_contract_ref: nil})
      result = Helper.group([orphan], :capway)

      assert map_size(result.orphaned_subscribers) == 1
      assert map_size(result.associated_subscribers) == 0
    end

    test "map_sets.active_trinity_ids still contains trinity_subscriber_id values" do
      sub1 = build_capway_sub(%{capway_contract_ref: "C-001", trinity_subscriber_id: 1})
      sub2 = build_capway_sub(%{capway_contract_ref: "C-002", trinity_subscriber_id: 1})
      sub3 = build_capway_sub(%{capway_contract_ref: "C-003", trinity_subscriber_id: 2})

      result = Helper.group([sub1, sub2, sub3], :capway)

      assert MapSet.member?(result.map_sets.active_trinity_ids, 1)
      assert MapSet.member?(result.map_sets.active_trinity_ids, 2)
      assert MapSet.size(result.map_sets.active_trinity_ids) == 2
    end

    test "map_sets.active_national_ids works correctly" do
      sub = build_capway_sub(%{national_id: "199001011234"})
      result = Helper.group([sub], :capway)

      assert MapSet.member?(result.map_sets.active_national_ids, "199001011234")
    end

    test "cancelled_subscribers keyed by capway_contract_ref" do
      sub = build_capway_sub(%{capway_contract_ref: "C-001", capway_active_status: false})
      result = Helper.group([sub], :capway)

      assert map_size(result.cancelled_subscribers) == 1
      assert Map.has_key?(result.cancelled_subscribers, "C-001")
    end
  end

  describe "group/2 :trinity" do
    test "still keys by trinity_subscriber_id" do
      sub = %Canonical{
        national_id: "199001011234",
        trinity_subscriber_id: 1,
        origin: :trinity,
        trinity_status: :active,
        subscription_type: :standard,
        payment_method: "capway"
      }

      result = Helper.group([sub], :trinity)

      assert Map.has_key?(result.active_subscribers, 1)
    end
  end
end
