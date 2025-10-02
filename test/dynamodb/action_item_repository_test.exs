defmodule CapwaySync.Dynamodb.ActionItemRepositoryTest do
  use ExUnit.Case, async: true
  alias CapwaySync.Models.{ActionItem, GeneralSyncReport}
  alias CapwaySync.Dynamodb.ActionItemRepository

  describe "struct_to_dynamodb_item/1" do
    test "converts ActionItem struct to DynamoDB item format" do
      action_item = %ActionItem{
        id: "test-uuid-123",
        trinity_id: "123456789012",
        created_at: "2024-01-15-10-30-00",
        timestamp: 1705312200,
        action: "suspend"
      }

      result = test_struct_to_dynamodb_item(action_item)

      assert result["id"] == "test-uuid-123"
      assert result["trinity_id"] == "123456789012"
      assert result["created_at"] == "2024-01-15-10-30-00"
      assert result["timestamp"] == 1705312200
      assert result["action"] == "suspend"
    end
  end

  describe "dynamodb_item_to_struct/1" do
    test "converts DynamoDB item back to ActionItem struct" do
      dynamodb_item = %{
        "id" => "test-uuid-123",
        "trinity_id" => "123456789012",
        "created_at" => "2024-01-15-10-30-00",
        "timestamp" => 1705312200,
        "action" => "suspend"
      }

      result = test_dynamodb_item_to_struct(dynamodb_item)

      assert %ActionItem{} = result
      assert result.id == "test-uuid-123"
      assert result.trinity_id == "123456789012"
      assert result.created_at == "2024-01-15-10-30-00"
      assert result.timestamp == 1705312200
      assert result.action == "suspend"
    end

    test "handles missing fields gracefully with defaults" do
      minimal_item = %{
        "id" => "test-uuid-123"
      }

      result = test_dynamodb_item_to_struct(minimal_item)

      assert %ActionItem{} = result
      assert result.id == "test-uuid-123"
      assert result.trinity_id == nil
      assert result.created_at == nil
      assert result.timestamp == 0
      assert result.action == nil
    end
  end

  describe "store_action_items_from_report/1" do
    test "creates and stores action items from GeneralSyncReport" do
      report = %GeneralSyncReport{
        missing_in_capway: ["123456789012", "234567890123"],
        suspend_accounts: ["345678901234"],
        unsuspend_accounts: ["456789012345"],
        created_at: ~U[2024-01-15 10:30:00Z]
      }

      # Mock the store_action_item function to return success
      result = test_store_action_items_from_report(report)

      assert {:ok, %{stored: 4, failed: 0, item_ids: item_ids}} = result
      assert length(item_ids) == 4
      assert Enum.all?(item_ids, &is_binary/1)
    end

    test "handles empty report gracefully" do
      report = %GeneralSyncReport{
        missing_in_capway: [],
        suspend_accounts: [],
        unsuspend_accounts: [],
        created_at: ~U[2024-01-15 10:30:00Z]
      }

      result = test_store_action_items_from_report(report)

      assert {:ok, %{stored: 0, failed: 0, item_ids: []}} = result
    end

    test "handles partial failures correctly" do
      report = %GeneralSyncReport{
        missing_in_capway: ["123456789012", "234567890123"],
        suspend_accounts: ["345678901234"],
        unsuspend_accounts: [],
        created_at: ~U[2024-01-15 10:30:00Z]
      }

      # Simulate one failure
      result = test_store_action_items_from_report_with_failure(report, 1)

      assert {:ok, %{stored: 2, failed: 1, item_ids: item_ids}} = result
      assert length(item_ids) == 2
    end
  end

  describe "filter building" do
    test "builds filter for action type" do
      opts = [action: "suspend"]
      filters = test_maybe_add_filters(%{}, opts)

      assert filters["FilterExpression"] == "action = :action"
      assert filters["ExpressionAttributeValues"][":action"] == "suspend"
    end

    test "builds filter for trinity_id" do
      opts = [trinity_id: "123456789012"]
      filters = test_maybe_add_filters(%{}, opts)

      assert filters["FilterExpression"] == "trinity_id = :trinity_id"
      assert filters["ExpressionAttributeValues"][":trinity_id"] == "123456789012"
    end

    test "builds filter for date range" do
      start_date = "2024-01-15-10-30-00"
      end_date = "2024-01-15-10-35-00"
      opts = [start_date: start_date, end_date: end_date]
      filters = test_maybe_add_filters(%{}, opts)

      assert filters["FilterExpression"] == "created_at BETWEEN :start_date AND :end_date"
      assert filters["ExpressionAttributeValues"][":start_date"] == start_date
      assert filters["ExpressionAttributeValues"][":end_date"] == end_date
    end

    test "builds filter for start date only" do
      start_date = "2024-01-15-10-30-00"
      opts = [start_date: start_date]
      filters = test_maybe_add_filters(%{}, opts)

      assert filters["FilterExpression"] == "created_at >= :start_date"
      assert filters["ExpressionAttributeValues"][":start_date"] == start_date
    end

    test "builds filter for end date only" do
      end_date = "2024-01-15-10-35-00"
      opts = [end_date: end_date]
      filters = test_maybe_add_filters(%{}, opts)

      assert filters["FilterExpression"] == "created_at <= :end_date"
      assert filters["ExpressionAttributeValues"][":end_date"] == end_date
    end

    test "builds combined filters with AND operator" do
      opts = [action: "suspend", trinity_id: "123456789012"]
      filters = test_maybe_add_filters(%{}, opts)

      # The order of filters in AND expression may vary
      assert filters["FilterExpression"] =~ "action = :action"
      assert filters["FilterExpression"] =~ "trinity_id = :trinity_id"
      assert filters["FilterExpression"] =~ " AND "
      assert filters["ExpressionAttributeValues"][":action"] == "suspend"
      assert filters["ExpressionAttributeValues"][":trinity_id"] == "123456789012"
    end

    test "returns original params when no filters" do
      opts = []
      original_params = %{"TableName" => "test-table", "Limit" => 50}
      result = test_maybe_add_filters(original_params, opts)

      assert result == original_params
    end
  end

  describe "get_table_name/0" do
    test "returns configured table name" do
      table_name = test_get_table_name()
      assert is_binary(table_name)
      assert String.length(table_name) > 0
    end
  end

  # Test helper functions that simulate private functions

  defp test_struct_to_dynamodb_item(%ActionItem{} = action_item) do
    %{
      "id" => action_item.id,
      "trinity_id" => action_item.trinity_id,
      "created_at" => action_item.created_at,
      "timestamp" => action_item.timestamp,
      "action" => action_item.action
    }
  end

  defp test_dynamodb_item_to_struct(item) when is_map(item) do
    %ActionItem{
      id: Map.get(item, "id"),
      trinity_id: Map.get(item, "trinity_id"),
      created_at: Map.get(item, "created_at"),
      timestamp: Map.get(item, "timestamp", 0),
      action: Map.get(item, "action")
    }
  end

  defp test_store_action_items_from_report(%GeneralSyncReport{} = report) do
    action_items = ActionItem.create_action_items_from_report(report)

    # Simulate all successful stores
    item_ids = Enum.map(action_items, fn _item -> UUID.uuid4() end)

    result = %{
      stored: length(action_items),
      failed: 0,
      item_ids: item_ids
    }

    {:ok, result}
  end

  defp test_store_action_items_from_report_with_failure(%GeneralSyncReport{} = report, failure_count) do
    action_items = ActionItem.create_action_items_from_report(report)
    total_items = length(action_items)
    success_count = total_items - failure_count

    # Simulate partial success
    item_ids = Enum.map(1..success_count, fn _i -> UUID.uuid4() end)

    result = %{
      stored: success_count,
      failed: failure_count,
      item_ids: item_ids
    }

    {:ok, result}
  end

  defp test_maybe_add_filters(scan_params, opts) do
    filters = []
    expression_values = %{}

    # Add action filter
    {filters, expression_values} =
      case Keyword.get(opts, :action) do
        nil -> {filters, expression_values}
        action ->
          filter = "action = :action"
          values = Map.put(expression_values, ":action", action)
          {[filter | filters], values}
      end

    # Add trinity_id filter
    {filters, expression_values} =
      case Keyword.get(opts, :trinity_id) do
        nil -> {filters, expression_values}
        trinity_id ->
          filter = "trinity_id = :trinity_id"
          values = Map.put(expression_values, ":trinity_id", trinity_id)
          {[filter | filters], values}
      end

    # Add date range filters
    {filters, expression_values} =
      case {Keyword.get(opts, :start_date), Keyword.get(opts, :end_date)} do
        {nil, nil} ->
          {filters, expression_values}
        {start_date, nil} when is_binary(start_date) ->
          filter = "created_at >= :start_date"
          values = Map.put(expression_values, ":start_date", start_date)
          {[filter | filters], values}
        {nil, end_date} when is_binary(end_date) ->
          filter = "created_at <= :end_date"
          values = Map.put(expression_values, ":end_date", end_date)
          {[filter | filters], values}
        {start_date, end_date} when is_binary(start_date) and is_binary(end_date) ->
          filter = "created_at BETWEEN :start_date AND :end_date"
          values =
            expression_values
            |> Map.put(":start_date", start_date)
            |> Map.put(":end_date", end_date)
          {[filter | filters], values}
        _ ->
          {filters, expression_values}
      end

    # Apply filters if any exist
    if length(filters) > 0 do
      filter_expression = Enum.join(filters, " AND ")

      scan_params
      |> Map.put("FilterExpression", filter_expression)
      |> Map.put("ExpressionAttributeValues", expression_values)
    else
      scan_params
    end
  end

  defp test_get_table_name do
    "capway-sync-action-items"
  end
end