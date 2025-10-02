defmodule CapwaySync.Models.ActionItemTest do
  use ExUnit.Case, async: true
  alias CapwaySync.Models.{ActionItem, GeneralSyncReport}

  describe "struct creation" do
    test "creates ActionItem with all required fields" do
      action_item = %ActionItem{
        id: "test-uuid-123",
        trinity_id: "123456789012",
        created_at: "2024-01-15",
        timestamp: 1705312200,  # 2024-01-15 10:30:00 UTC
        action: "suspend"
      }

      assert action_item.id == "test-uuid-123"
      assert action_item.trinity_id == "123456789012"
      assert action_item.created_at == "2024-01-15"
      assert action_item.timestamp == 1705312200
      assert action_item.action == "suspend"
    end

    test "creates ActionItem with default values" do
      action_item = %ActionItem{}

      assert action_item.id == nil
      assert action_item.trinity_id == nil
      assert action_item.created_at == nil
      assert action_item.timestamp == 0
      assert action_item.action == nil
    end
  end

  describe "create_action_items_from_report/1" do
    test "creates action items from GeneralSyncReport with all action types" do
      report = %GeneralSyncReport{
        missing_in_capway: ["123456789012", "234567890123"],
        suspend_accounts: ["345678901234"],
        unsuspend_accounts: ["456789012345", "567890123456"],
        created_at: ~U[2024-01-15 10:30:00Z]
      }

      action_items = ActionItem.create_action_items_from_report(report)

      assert length(action_items) == 5

      # Check sync_to_capway items
      sync_items = Enum.filter(action_items, &(&1.action == "sync_to_capway"))
      assert length(sync_items) == 2
      assert Enum.map(sync_items, &(&1.trinity_id)) |> Enum.sort() == ["123456789012", "234567890123"]

      # Check suspend items
      suspend_items = Enum.filter(action_items, &(&1.action == "suspend"))
      assert length(suspend_items) == 1
      assert List.first(suspend_items).trinity_id == "345678901234"

      # Check unsuspend items
      unsuspend_items = Enum.filter(action_items, &(&1.action == "unsuspend"))
      assert length(unsuspend_items) == 2
      assert Enum.map(unsuspend_items, &(&1.trinity_id)) |> Enum.sort() == ["456789012345", "567890123456"]

      # Verify all items have same timestamp value
      timestamps = Enum.map(action_items, &(&1.timestamp)) |> Enum.uniq()
      assert length(timestamps) == 1
      expected_timestamp = DateTime.to_unix(~U[2024-01-15 10:30:00Z])
      assert List.first(timestamps) == expected_timestamp

      # Verify all items have same created_at date string
      created_ats = Enum.map(action_items, &(&1.created_at)) |> Enum.uniq()
      assert length(created_ats) == 1
      assert List.first(created_ats) == "2024-01-15"

      # Verify all items have UUIDs
      ids = Enum.map(action_items, &(&1.id))
      assert Enum.all?(ids, &is_binary/1)
      assert Enum.all?(ids, &(String.length(&1) == 36))  # UUID length
    end

    test "creates empty list when no actionable items in report" do
      report = %GeneralSyncReport{
        missing_in_capway: [],
        suspend_accounts: [],
        unsuspend_accounts: [],
        created_at: ~U[2024-01-15 10:30:00Z]
      }

      action_items = ActionItem.create_action_items_from_report(report)

      assert action_items == []
    end

    test "handles nil created_at by using current time" do
      report = %GeneralSyncReport{
        missing_in_capway: ["123456789012"],
        suspend_accounts: [],
        unsuspend_accounts: [],
        created_at: nil
      }

      before_time = DateTime.utc_now() |> DateTime.to_unix()
      action_items = ActionItem.create_action_items_from_report(report)
      after_time = DateTime.utc_now() |> DateTime.to_unix()

      assert length(action_items) == 1
      item = List.first(action_items)
      assert item.timestamp >= before_time
      assert item.timestamp <= after_time
      assert is_binary(item.created_at)
      assert String.length(item.created_at) > 0
    end

    test "converts non-string trinity_ids to strings" do
      report = %GeneralSyncReport{
        missing_in_capway: [123456789012],  # Integer trinity_id
        suspend_accounts: [],
        unsuspend_accounts: [],
        created_at: ~U[2024-01-15 10:30:00Z]
      }

      action_items = ActionItem.create_action_items_from_report(report)

      assert length(action_items) == 1
      item = List.first(action_items)
      assert item.trinity_id == "123456789012"
      assert is_binary(item.trinity_id)
    end
  end

  describe "validate_action/1" do
    test "validates correct action types" do
      assert ActionItem.validate_action("suspend") == :ok
      assert ActionItem.validate_action("unsuspend") == :ok
      assert ActionItem.validate_action("sync_to_capway") == :ok
    end

    test "rejects invalid action types" do
      {:error, message} = ActionItem.validate_action("invalid_action")
      assert message =~ "Invalid action type"
      assert message =~ "suspend, unsuspend, sync_to_capway"

      {:error, message} = ActionItem.validate_action("delete")
      assert message =~ "Invalid action type"

      {:error, message} = ActionItem.validate_action("")
      assert message =~ "Invalid action type"
    end
  end

  describe "valid_actions/0" do
    test "returns list of valid action types" do
      actions = ActionItem.valid_actions()

      assert is_list(actions)
      assert "suspend" in actions
      assert "unsuspend" in actions
      assert "sync_to_capway" in actions
      assert "cancel_capway_contract" in actions
      assert length(actions) == 4
    end
  end

  describe "created_at formatting" do
    test "formats datetime correctly in YYYY-MM-DD format" do
      report = %GeneralSyncReport{
        missing_in_capway: ["123456789012"],
        suspend_accounts: [],
        unsuspend_accounts: [],
        created_at: ~U[2024-01-15 10:30:45.123Z]  # With seconds and microseconds
      }

      action_items = ActionItem.create_action_items_from_report(report)
      item = List.first(action_items)

      # Should format as YYYY-MM-DD date only
      assert item.created_at == "2024-01-15"
    end

    test "handles different time formats correctly" do
      # Test various edge cases for time formatting
      test_cases = [
        {~U[2024-12-31 23:59:59Z], "2024-12-31"},
        {~U[2024-01-01 00:00:00Z], "2024-01-01"},
        {~U[2024-06-15 12:30:45Z], "2024-06-15"}
      ]

      for {datetime, expected_format} <- test_cases do
        report = %GeneralSyncReport{
          missing_in_capway: ["123456789012"],
          suspend_accounts: [],
          unsuspend_accounts: [],
          created_at: datetime
        }

        action_items = ActionItem.create_action_items_from_report(report)
        item = List.first(action_items)

        assert item.created_at == expected_format
      end
    end
  end

  describe "JSON encoding" do
    test "ActionItem can be encoded to JSON" do
      action_item = %ActionItem{
        id: "test-uuid-123",
        trinity_id: "123456789012",
        created_at: "2024-01-15",
        timestamp: 1705312200,
        action: "suspend"
      }

      {:ok, json} = Jason.encode(action_item)
      {:ok, decoded} = Jason.decode(json)

      assert decoded["id"] == "test-uuid-123"
      assert decoded["trinity_id"] == "123456789012"
      assert decoded["created_at"] == "2024-01-15"
      assert decoded["timestamp"] == 1705312200
      assert decoded["action"] == "suspend"
    end
  end
end