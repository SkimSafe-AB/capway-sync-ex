defmodule CapwaySync.Models.ActionItemCancelTest do
  use ExUnit.Case, async: true
  alias CapwaySync.Models.ActionItem
  alias CapwaySync.Models.GeneralSyncReport

  describe "create_action_items_from_report/1 with cancel_capway_contract" do
    test "creates action items including cancel_capway_contract" do
      report = %GeneralSyncReport{
        created_at: ~U[2024-01-15 10:30:00Z],
        missing_in_capway: ["123456789012"],
        suspend_accounts: ["234567890123"],
        unsuspend_accounts: ["345678901234"],
        cancel_capway_contracts: ["456789012345", "567890123456"]
      }

      items = ActionItem.create_action_items_from_report(report)

      # Should have 5 total items: 1 sync + 1 suspend + 1 unsuspend + 2 cancel
      assert length(items) == 5

      actions = Enum.map(items, & &1.action) |> Enum.sort()

      assert actions == [
               "cancel_capway_contract",
               "cancel_capway_contract",
               "suspend",
               "sync_to_capway",
               "unsuspend"
             ]

      # Check cancel_capway_contract items specifically
      cancel_items = Enum.filter(items, &(&1.action == "cancel_capway_contract"))
      assert length(cancel_items) == 2

      cancel_trinity_ids = Enum.map(cancel_items, & &1.trinity_id) |> Enum.sort()
      assert cancel_trinity_ids == ["456789012345", "567890123456"]

      # Verify all items have correct metadata
      Enum.each(cancel_items, fn item ->
        assert item.status == :pending
        assert item.created_at == "2024-01-15"
        assert item.timestamp == DateTime.to_unix(~U[2024-01-15 10:30:00Z])
        # UUID length
        assert String.length(item.id) == 36
      end)
    end

    test "handles missing cancel_capway_contracts field" do
      report = %GeneralSyncReport{
        created_at: ~U[2024-01-15 10:30:00Z],
        missing_in_capway: ["123456789012"],
        suspend_accounts: [],
        unsuspend_accounts: []
        # cancel_capway_contracts field missing
      }

      items = ActionItem.create_action_items_from_report(report)

      # Should have 1 item (only sync_to_capway)
      assert length(items) == 1

      actions = Enum.map(items, & &1.action)
      assert actions == ["sync_to_capway"]

      # No cancel items should be created
      cancel_items = Enum.filter(items, &(&1.action == "cancel_capway_contract"))
      assert length(cancel_items) == 0
    end

    test "handles empty cancel_capway_contracts list" do
      report = %GeneralSyncReport{
        created_at: ~U[2024-01-15 10:30:00Z],
        missing_in_capway: [],
        suspend_accounts: [],
        unsuspend_accounts: [],
        cancel_capway_contracts: []
      }

      items = ActionItem.create_action_items_from_report(report)

      # Should have no items
      assert length(items) == 0

      # No cancel items should be created
      cancel_items = Enum.filter(items, &(&1.action == "cancel_capway_contract"))
      assert length(cancel_items) == 0
    end
  end

  describe "validate_action/1 with cancel_capway_contract" do
    test "validates cancel_capway_contract as valid action" do
      assert :ok = ActionItem.validate_action("cancel_capway_contract")
    end

    test "includes cancel_capway_contract in valid_actions list" do
      valid_actions = ActionItem.valid_actions()
      assert "cancel_capway_contract" in valid_actions
    end

    test "error message includes cancel_capway_contract" do
      assert {:error, error_msg} = ActionItem.validate_action("invalid_action")
      assert String.contains?(error_msg, "cancel_capway_contract")
    end
  end
end
